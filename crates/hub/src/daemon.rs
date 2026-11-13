//! The Hub Daemon: owns every Worker's terminal, worktree, and messages.
//! It never writes into the Orchestrator's terminal; the Orchestrator reads with `echoctl wait`.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::RecvTimeoutError;
use std::sync::{Arc, Condvar, Mutex, Weak};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::chat;
use crate::cli;
use crate::db::{self, kind, state, Worker};
use crate::holder;
use crate::kiro_chat;
use crate::kiro_usage;
use crate::launch;
use crate::lessons;
use crate::paths;
use crate::profile::{self, Launch};
use crate::proto;
use crate::pty::{Live, Spawn};
use crate::remote::{self, Remote};
use crate::repo;
use crate::screen::{self, Look};
use crate::settings;
use crate::stats;
use crate::team;

/// How long a turn may take to start before `worker.start` gives up on it.
const START_TIMEOUT: Duration = Duration::from_secs(90);
/// A new worktree's setup (`pnpm install` and the like) runs before the turn can start.
const SETUP_TIMEOUT: Duration = Duration::from_secs(20 * 60);
/// An unchanged idle screen this long, with no Final Report, is a blocker.
const IDLE_BLOCKER: Duration = Duration::from_secs(60);
/// Settled Workers stay on the Dashboard this long.
const KEEP_SETTLED_SECONDS: i64 = 10 * 60;
/// Echo's Done list keeps a done, ended, or failed Worker this long, read or not (features/0030).
const KEEP_REPORTS_SECONDS: i64 = 5 * 60;
/// A blocked or lost Worker still needs the human, so Echo keeps it this long unless dismissed.
const KEEP_NEEDS_SECONDS: i64 = 7 * 24 * 60 * 60;
const SCREEN_LINES: usize = 25;
/// How long `wait` holds a message that woke it, for others to arrive with it.
const COALESCE: Duration = Duration::from_secs(5);
/// How many times a failed verification sends a writer back to fix its change.
const MAX_RETRIES: i64 = 1;
/// An Orchestrator is renewed only after it sat unchanged at its input box this long, and only
/// once its session has made this many requests (a new one is never renewed at once).
const RENEW_QUIET: Duration = Duration::from_secs(120);
const MIN_RENEW_REQUESTS: usize = 20;
/// How often a quiet Orchestrator's transcript is measured.
const RENEW_CHECK: Duration = Duration::from_secs(600);

pub struct Hub {
    db: Mutex<Connection>,
    live: Mutex<HashMap<i64, Arc<Live>>>,
    /// Each live agent's terminal (Orchestrators and Normal sessions), by agent id.
    agents: Mutex<HashMap<i64, Arc<Live>>>,
    /// A login shell in each agent's checkout, by agent id: its terminal while the agent itself
    /// is not running, and a Terminal agent's only one. Started when first attached.
    shells: Mutex<HashMap<i64, Arc<Live>>>,
    /// A login shell per checkout, by its real path: what Echo shows under the Files column. It
    /// belongs to the folder, not to an agent, so it stays while agents come and go.
    side_shells: Mutex<HashMap<String, Arc<Live>>>,
    /// When each Normal session's waiting permission prompt was first seen, by agent id.
    agent_prompts: Mutex<HashMap<i64, i64>>,
    tick: Mutex<u64>,
    changed: Condvar,
    usage: Mutex<Usage>,
    hub_dir: PathBuf,
    /// Tests only: run this program with the spec instead of `claude`.
    test_agent: Option<String>,
    /// What reads Kiro's credits for the usage bar; none in a test daemon unless `HUB_TEST_KIRO` names one.
    kiro_usage: Option<String>,
    /// Echo Remote, the phone web app (ADR 0008).
    remote: Remote,
    /// What agents asked Echo to show with `echoctl ui`, newest last; each stays `UI_KEEP` seconds.
    ui: Mutex<Vec<Value>>,
    /// How many of Echo's event streams follow each repo, so `echoctl ui` can tell no one is looking.
    watchers: Mutex<HashMap<String, usize>>,
}

/// How long a request from `echoctl ui` stays in the snapshot for Echo to act on.
const UI_KEEP: i64 = 30;

/// How often account usage is re-read while someone watches the events stream.
const USAGE_EVERY: Duration = Duration::from_secs(5 * 60);
/// After a failed read, the next try comes this much sooner than USAGE_EVERY.
const USAGE_RETRY: Duration = Duration::from_secs(60);
/// `claude -p /usage` now and then prints a cost summary instead of the plan limits; it is tried
/// this many times per refresh.
const USAGE_ATTEMPTS: usize = 3;

/// The Claude account's plan limits, as `claude -p /usage` prints them, and after them Kiro's credits.
#[derive(Default)]
struct Usage {
    limits: Vec<Value>,
    updated_at: Option<i64>,
    error: Option<String>,
    refreshing: bool,
    refreshed: Option<Instant>,
    /// Kiro's credits as a limit entry (features/0078): read on their own thread and cadence, so
    /// Claude's refresh and `error` never wait for or show anything of them.
    kiro: Option<Value>,
    kiro_refreshing: bool,
    kiro_refreshed: Option<Instant>,
}

impl Usage {
    fn view(&self) -> Value {
        let mut limits = self.limits.clone();
        limits.extend(self.kiro.clone());
        json!({ "limits": limits, "updatedAt": self.updated_at, "error": self.error, "refreshing": self.refreshing })
    }

    /// A reading replaces the last one; no `kiro-cli`, or no login, clears it; a failure keeps it
    /// and brings the next try forward, as for Claude's.
    fn finish_kiro(&mut self, outcome: kiro_usage::Outcome) {
        self.kiro_refreshing = false;
        match outcome {
            kiro_usage::Outcome::Reading(entry) => self.kiro = Some(entry),
            kiro_usage::Outcome::Absent => self.kiro = None,
            kiro_usage::Outcome::Failed(_) | kiro_usage::Outcome::Skipped(_) => {
                self.kiro_refreshed = Instant::now().checked_sub(USAGE_EVERY - USAGE_RETRY);
            }
        }
    }
}

/// The program that reads Kiro's credits: `kiro-cli`, or what `HUB_TEST_KIRO` names. A daemon
/// under `HUB_TEST_AGENT` reads none without it, so tests never run a real Kiro.
fn kiro_usage_program(test_agent: Option<&str>) -> Option<String> {
    match std::env::var("HUB_TEST_KIRO") {
        Ok(program) if !program.is_empty() => Some(program),
        _ if test_agent.is_some() => None,
        _ => Some("kiro-cli".into()),
    }
}

/// Runs `<claude> -p /usage` outside any agent session and parses its limits; gives up after a minute.
fn run_usage(program: &str) -> Result<Vec<Value>> {
    let mut command = std::process::Command::new(program);
    command
        .args(["-p", "/usage"])
        .current_dir(paths::state_dir())
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    for key in inherited_agent_vars() {
        command.env_remove(key);
    }
    let mut child = command
        .spawn()
        .with_context(|| format!("running {program} -p /usage"))?;
    let deadline = Instant::now() + Duration::from_secs(60);
    while child.try_wait()?.is_none() {
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            bail!("`claude -p /usage` took over a minute");
        }
        std::thread::sleep(Duration::from_millis(200));
    }
    let mut text = String::new();
    child.stdout.take().context("no output")?.read_to_string(&mut text)?;
    Ok(parse_usage(&text))
}

/// The limit lines of `/usage`, e.g. "Current week (all models): 9% used · resets Oct 23 at 11pm (Asia/Saigon)".
fn parse_usage(text: &str) -> Vec<Value> {
    text.lines()
        .filter_map(|line| {
            let rest = line.trim().strip_prefix("Current ")?;
            let (name, rest) = rest.split_once(": ")?;
            let (percent, rest) = rest.split_once("% used")?;
            let percent: i64 = percent.trim().parse().ok()?;
            let resets = rest
                .split_once("resets ")
                .map(|(_, at)| at.split(" (").next().unwrap_or(at).trim().to_string());
            let name = match name {
                "session" => "Session".to_string(),
                "week (all models)" => "Week".to_string(),
                other => {
                    let mut name = other.to_string();
                    name[..1].make_ascii_uppercase();
                    name
                }
            };
            Some(json!({ "name": name, "percent": percent, "resets": resets }))
        })
        .collect()
}

pub fn run() -> Result<()> {
    std::fs::create_dir_all(paths::state_dir())?;
    // One daemon per state folder: two `echoctl` commands at once may both start one, and the second
    // must not take the socket from the first. The lock lives as long as this process.
    let lock = std::fs::File::create(paths::state_dir().join("hubd.lock"))?;
    if unsafe { libc::flock(std::os::fd::AsRawFd::as_raw_fd(&lock), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        bail!("a Hub Daemon is already running for {}", paths::state_dir().display());
    }
    std::mem::forget(lock);
    let socket = paths::socket();
    if UnixStream::connect(&socket).is_ok() {
        bail!("a Hub Daemon is already running on {}", socket.display());
    }
    let _ = std::fs::remove_file(&socket);
    let listener = UnixListener::bind(&socket).with_context(|| format!("binding {}", socket.display()))?;
    std::fs::set_permissions(&socket, std::fs::Permissions::from_mode(0o600))?;

    let conn = db::open(&paths::database())?;
    let hub = Arc::new(Hub {
        db: Mutex::new(conn),
        live: Mutex::new(HashMap::new()),
        agents: Mutex::new(HashMap::new()),
        shells: Mutex::new(HashMap::new()),
        side_shells: Mutex::new(HashMap::new()),
        agent_prompts: Mutex::new(HashMap::new()),
        tick: Mutex::new(0),
        changed: Condvar::new(),
        usage: Mutex::new(Usage::default()),
        hub_dir: paths::hub_dir(),
        test_agent: std::env::var("HUB_TEST_AGENT").ok(),
        kiro_usage: kiro_usage_program(std::env::var("HUB_TEST_AGENT").ok().as_deref()),
        remote: Remote::load(),
        ui: Mutex::new(Vec::new()),
        watchers: Mutex::new(HashMap::new()),
    });
    hub.recover()?;
    remote::start_if_enabled(&hub);
    eprintln!("hubd {}: listening on {}", std::process::id(), socket.display());

    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        let hub = Arc::clone(&hub);
        std::thread::spawn(move || {
            if let Err(error) = hub.handle(stream) {
                eprintln!("hubd: {error:#}");
            }
        });
    }
    Ok(())
}

/// `path` as lowercase hex, which names a side shell in the holder (keys are plain words).
pub fn hex(path: &str) -> String {
    path.bytes().map(|b| format!("{b:02x}")).collect()
}

/// The path `hex` made, or None when `text` is not hex or not UTF-8.
pub fn unhex(text: &str) -> Option<String> {
    if text.is_empty() || text.len() % 2 != 0 || !text.is_ascii() {
        return None;
    }
    let bytes: Option<Vec<u8>> = (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&text[i..i + 2], 16).ok())
        .collect();
    String::from_utf8(bytes?).ok()
}

/// The folder a side shell works in: absolute, existing, and spelt as the system does.
fn side_dir(path: &str) -> Result<PathBuf> {
    let path = Path::new(path);
    if !path.is_absolute() {
        bail!("{} is not an absolute path", path.display());
    }
    let dir = path
        .canonicalize()
        .with_context(|| format!("{} does not exist", path.display()))?;
    if !dir.is_dir() {
        bail!("{} is not a folder", dir.display());
    }
    Ok(dir)
}

/// Whether the client on the other end of `stream` has gone away.
fn peer_gone(stream: &UnixStream) -> bool {
    let mut byte = [0u8; 1];
    let n = unsafe {
        libc::recv(
            std::os::fd::AsRawFd::as_raw_fd(stream),
            byte.as_mut_ptr().cast(),
            1,
            libc::MSG_PEEK | libc::MSG_DONTWAIT,
        )
    };
    n == 0 || (n < 0 && std::io::Error::last_os_error().kind() != std::io::ErrorKind::WouldBlock)
}

fn param<'a>(params: &'a Value, key: &str) -> Result<&'a Value> {
    match params.get(key) {
        Some(value) if !value.is_null() => Ok(value),
        _ => bail!("missing parameter {key}"),
    }
}

fn str_param<'a>(params: &'a Value, key: &str) -> Result<&'a str> {
    param(params, key)?
        .as_str()
        .with_context(|| format!("parameter {key} must be a string"))
}

fn id_param(params: &Value, key: &str) -> Result<i64> {
    param(params, key)?
        .as_i64()
        .with_context(|| format!("parameter {key} must be a number"))
}

fn timeout_param(params: &Value, default: Duration) -> Duration {
    params
        .get("timeout_ms")
        .and_then(Value::as_u64)
        .map(Duration::from_millis)
        .unwrap_or(default)
}

/// The first line of the spec, without a Markdown heading or a "Task:" label.
pub fn title_from_spec(spec: &str) -> String {
    let first = spec
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("Task");
    let title = first.trim_start_matches('#').trim().trim_start_matches("Task:").trim();
    title.chars().take(60).collect()
}

impl Hub {
    fn db(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.db.lock().unwrap()
    }

    fn notify(&self) {
        *self.tick.lock().unwrap() += 1;
        self.changed.notify_all();
    }

    pub(crate) fn tick(&self) -> u64 {
        *self.tick.lock().unwrap()
    }

    /// Waits until something changes after `seen`, or `timeout` passes; the tick it is at now.
    pub(crate) fn wait_change(&self, seen: u64, timeout: Duration) -> u64 {
        let guard = self.tick.lock().unwrap();
        if *guard != seen {
            return *guard;
        }
        *self.changed.wait_timeout(guard, timeout).unwrap().0
    }

    pub(crate) fn remote(&self) -> &Remote {
        &self.remote
    }

    /// Under test: nothing outside the test's own folder, like Tailscale, is touched.
    pub(crate) fn is_test(&self) -> bool {
        self.test_agent.is_some()
    }

    /// Every repo's snapshot, for Echo Remote.
    pub(crate) fn world(&self) -> Result<Value> {
        let mut repos: Vec<String> = db::agents(&self.db(), None)?.into_iter().map(|a| a.repo).collect();
        repos.sort();
        repos.dedup();
        let mut out = Vec::new();
        for repo in &repos {
            let mut snapshot = self.snapshot(repo)?;
            snapshot.as_object_mut().map(|s| s.remove("usage"));
            out.push(snapshot);
        }
        Ok(json!({ "repos": out, "usage": self.usage.lock().unwrap().view() }))
    }

    /// An agent's terminal (or, while it is stopped, its shell) or a Worker's, if one runs; never
    /// starts one.
    pub(crate) fn running_terminal(&self, agent: Option<i64>, worker: Option<i64>) -> Option<Arc<Live>> {
        match (agent, worker) {
            (Some(id), _) => self.agent_live(id).ok().or_else(|| {
                self.shells
                    .lock()
                    .unwrap()
                    .get(&id)
                    .filter(|live| live.is_alive())
                    .cloned()
            }),
            (None, Some(id)) => self.live(id).ok(),
            (None, None) => None,
        }
    }

    /// The CLI an agent or Worker runs on, found as at its start (`cli::recovered`), for choosing
    /// whose transcript its chat reads. None for a CLI Echo does not run.
    fn chat_cli(&self, stored: Option<&str>, repo: &str, profile: Option<&str>) -> Option<cli::Cli> {
        if stored.is_some_and(|name| cli::Cli::parse(name).is_err()) {
            return None;
        }
        let (state, repo) = (paths::state_dir(), Path::new(repo));
        let profile = profile
            .and_then(|name| profile::load(&self.hub_dir, &state, Some(repo), name).ok())
            .map(|profile| profile.choice());
        let picked = cli::Choice {
            cli: stored.map(String::from),
            model: None,
        };
        Some(cli::recovered(&state, Some(repo), profile.as_ref(), &[&picked]))
    }

    fn chat_read(&self, p: &Value) -> Result<Value> {
        // Whose transcript, its CLI, its running terminal, the texts Echo or others typed in, and
        // (for an agent) its earlier sessions, oldest first.
        let (session, cli, live, inputs, earlier) = match p.get("worker").and_then(Value::as_i64) {
            Some(id) => {
                let worker = db::worker(&self.db(), id)?;
                let inputs = db::inputs(&self.db(), id)?;
                let cli = self.chat_cli(worker.cli.as_deref(), &worker.repo, Some(&worker.profile));
                (worker.session_id, cli, self.live(id).ok(), inputs, vec![])
            }
            None => {
                let agent = db::agent(&self.db(), id_param(p, "agent")?)?;
                let echo =
                    [launch::RESUMED, launch::RENEWED].map(|text| (db::origin::ECHO.to_string(), text.to_string()));
                let earlier = db::agent_sessions(&self.db(), agent.id)?;
                let cli = self.chat_cli(self.agent_stored_cli(&agent).as_deref(), &agent.repo, None);
                (
                    agent.session_id,
                    cli,
                    self.agent_live(agent.id).ok(),
                    echo.to_vec(),
                    earlier,
                )
            }
        };
        let kiro = cli == Some(cli::Cli::Kiro);
        let inputs = if kiro { kiro_chat::typed_inputs(&inputs) } else { inputs };
        let limit = p.get("limit").and_then(Value::as_u64).unwrap_or(200) as usize;
        let projects = stats::projects_dir();
        // The transcript file of a session, and a read of it, by whichever CLI wrote it.
        let transcript = |session: &str| {
            if kiro {
                cli::kiro_transcript(session)
            } else {
                stats::transcript(&projects, session)
            }
        };
        let read = |path: &Path, after: Option<u64>, before: Option<u64>| {
            if kiro {
                kiro_chat::read(path, limit, after, before)
            } else {
                chat::read(path, limit, after, before)
            }
        };
        // The session before `of`, among the earlier ones.
        let previous = |of: &str| -> Option<String> {
            if of == session {
                return earlier.last().cloned();
            }
            let at = earlier.iter().position(|s| s == of)?;
            at.checked_sub(1).map(|at| earlier[at].clone())
        };
        // An older page: the lines before `before` in `page_session`, else the session before it.
        if let Some(before) = p.get("before").and_then(Value::as_u64) {
            let mut page_session = str_param(p, "page_session")?.to_string();
            let before = Some(before).filter(|&b| b > 0);
            let mut renewed = None;
            if before.is_none() {
                let Some(prev) = previous(&page_session) else {
                    return Ok(json!({ "items": [], "start": 0, "page_session": page_session, "more": false }));
                };
                renewed = Some(chat::renewed(&page_session));
                page_session = prev;
            }
            let page = transcript(&page_session)
                .map(|path| read(&path, None, before))
                .transpose()?
                .unwrap_or(chat::Page {
                    items: vec![],
                    start: 0,
                    end: 0,
                });
            let mut items = page.items;
            chat::mark_origins(&mut items, &inputs);
            items.extend(renewed);
            let more = page.start > 0 || previous(&page_session).is_some();
            return Ok(json!({ "items": items, "start": page.start, "page_session": page_session, "more": more }));
        }
        let state = chat_state(live.as_deref());
        let more = !earlier.is_empty();
        if matches!(cli, None | Some(cli::Cli::Codex)) {
            return Ok(
                json!({ "session": session, "supported": false, "items": [], "end": 0, "start": 0,
                              "more": false, "state": state }),
            );
        }
        let Some(path) = transcript(&session) else {
            return Ok(
                json!({ "session": session, "supported": true, "items": [], "end": 0, "start": 0,
                              "more": more, "state": state }),
            );
        };
        let same = p.get("session").and_then(Value::as_str) == Some(session.as_str());
        let after = p.get("after").and_then(Value::as_u64).filter(|_| same);
        let page = read(&path, after, None)?;
        let mut items = page.items;
        chat::mark_origins(&mut items, &inputs);
        Ok(
            json!({ "session": session, "supported": true, "items": items, "end": page.end, "start": page.start,
                   "more": more || page.start > 0, "state": state }),
        )
    }

    /// Re-runs `check` after every change until it yields, `timeout` passes, or `gone` says stop.
    fn wait_until<T>(
        &self,
        timeout: Duration,
        gone: impl Fn() -> bool,
        mut check: impl FnMut() -> Result<Option<T>>,
    ) -> Result<Option<T>> {
        let deadline = Instant::now() + timeout;
        loop {
            let seen = *self.tick.lock().unwrap();
            if let Some(value) = check()? {
                return Ok(Some(value));
            }
            let now = Instant::now();
            if now >= deadline || gone() {
                return Ok(None);
            }
            let guard = self.tick.lock().unwrap();
            if *guard == seen {
                // Wake at least every second to notice a client that hung up.
                let _ = self
                    .changed
                    .wait_timeout(guard, (deadline - now).min(Duration::from_secs(1)));
            }
        }
    }

    fn live(&self, id: i64) -> Result<Arc<Live>> {
        match self.live.lock().unwrap().get(&id) {
            Some(live) => Ok(Arc::clone(live)),
            None => bail!("w{id} has no live terminal"),
        }
    }

    /// The terminal a request names: `{"id": n}` for a Worker, `{"agent": n}` for an Orchestrator
    /// or Normal session, `{"orchestrator": repo}` for the repo's first Orchestrator.
    fn terminal(self: &Arc<Self>, p: &Value) -> Result<Arc<Live>> {
        if let Some(path) = p.get("side").and_then(Value::as_str) {
            return self.side_shell(path);
        }
        if let Some(id) = p.get("agent").and_then(Value::as_i64) {
            return self.agent_live(id).or_else(|_| self.shell(id));
        }
        match p.get("orchestrator").and_then(Value::as_str) {
            Some(repo) => {
                let first = db::first_orchestrator(&self.db(), repo)?;
                match first {
                    Some(agent) => self.agent_live(agent.id),
                    None => bail!("no Orchestrator for {repo}"),
                }
            }
            None => self.live(id_param(p, "id")?),
        }
    }

    fn agent_live(&self, id: i64) -> Result<Arc<Live>> {
        match self.agents.lock().unwrap().get(&id) {
            Some(live) => Ok(Arc::clone(live)),
            None => bail!("agent {id} has no live terminal"),
        }
    }

    fn agent_is_live(&self, id: i64) -> bool {
        self.agents.lock().unwrap().contains_key(&id)
    }

    /// The agent's shell, started in its checkout when it has none.
    fn shell(self: &Arc<Self>, id: i64) -> Result<Arc<Live>> {
        let mut shells = self.shells.lock().unwrap();
        if let Some(live) = shells.get(&id).filter(|live| live.is_alive()) {
            return Ok(Arc::clone(live));
        }
        let agent = db::agent(&self.db(), id)?;
        let mut env = self.agent_env(None, None)?;
        env.push(("SHELL".into(), login_shell()));
        let spawn = Spawn {
            // A plain shell: nothing reads its screen, so any CLI's reader would do.
            cli: cli::Cli::Claude,
            program: login_shell(),
            args: vec!["-l".into()],
            cwd: PathBuf::from(agent.home()),
            env,
            // The terminal app that started the daemon is not this one: macOS's zshrc would
            // restore that app's saved session into it.
            env_remove: inherited_agent_vars()
                .into_iter()
                .chain(["TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID"].map(String::from))
                .collect(),
        };
        let live = Live::spawn(&format!("s{id}"), id, spawn, self.shell_exit())?;
        shells.insert(id, Arc::clone(&live));
        Ok(live)
    }

    fn shell_exit(self: &Arc<Self>) -> impl FnOnce(i64) + Send + 'static {
        let hub: Weak<Hub> = Arc::downgrade(self);
        move |id| {
            if let Some(hub) = hub.upgrade() {
                // Only this shell: a newer one may have taken its place.
                let mut shells = hub.shells.lock().unwrap();
                if shells.get(&id).is_some_and(|live| !live.is_alive()) {
                    shells.remove(&id);
                }
            }
        }
    }

    /// Ends the agent's shell, so whoever follows the agent attaches to it when it starts.
    fn stop_shell(&self, id: i64) {
        if let Some(live) = self.shells.lock().unwrap().remove(&id) {
            live.kill();
        }
    }

    /// The checkout's side shell, started there when it has none. `path` must be an existing
    /// folder; it is named by its real path, so two spellings of one folder share a shell.
    fn side_shell(self: &Arc<Self>, path: &str) -> Result<Arc<Live>> {
        let dir = side_dir(path)?;
        let key = dir.display().to_string();
        let mut shells = self.side_shells.lock().unwrap();
        if let Some(live) = shells.get(&key).filter(|live| live.is_alive()) {
            return Ok(Arc::clone(live));
        }
        let mut env = self.agent_env(None, None)?;
        env.push(("SHELL".into(), login_shell()));
        let spawn = Spawn {
            // A plain shell: nothing reads its screen as an agent's.
            cli: cli::Cli::Claude,
            program: login_shell(),
            args: vec!["-l".into()],
            cwd: dir,
            env,
            env_remove: inherited_agent_vars()
                .into_iter()
                .chain(["TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID"].map(String::from))
                .collect(),
        };
        let live = Live::spawn(&format!("t{}", hex(&key)), 0, spawn, self.side_exit(key.clone()))?;
        shells.insert(key, Arc::clone(&live));
        Ok(live)
    }

    fn side_exit(self: &Arc<Self>, key: String) -> impl FnOnce(i64) + Send + 'static {
        let hub: Weak<Hub> = Arc::downgrade(self);
        move |_| {
            if let Some(hub) = hub.upgrade() {
                // Only this shell: a newer one may have taken its place.
                let mut shells = hub.side_shells.lock().unwrap();
                if shells.get(&key).is_some_and(|live| !live.is_alive()) {
                    shells.remove(&key);
                }
            }
        }
    }

    /// Whether the checkout's side shell runs, and how long since it last printed: Echo shows a
    /// busy mark while a command streams. Never starts one.
    fn side_status(&self, p: &Value) -> Result<Value> {
        let key = side_dir(str_param(p, "path")?)?.display().to_string();
        let live = self
            .side_shells
            .lock()
            .unwrap()
            .get(&key)
            .filter(|l| l.is_alive())
            .cloned();
        let lines = p.get("lines").and_then(Value::as_u64).unwrap_or(0) as usize;
        Ok(match live {
            Some(live) => {
                let screen = live.screen();
                json!({
                    "live": true,
                    "quiet_ms": live.quiet_for().as_millis() as u64,
                    "screen": if lines > 0 { screen::tail(&screen, lines) } else { String::new() },
                })
            }
            None => json!({ "live": false }),
        })
    }

    /// Ends the checkout's side shell.
    fn side_stop(&self, p: &Value) -> Result<Value> {
        let key = side_dir(str_param(p, "path")?)?.display().to_string();
        if let Some(live) = self.side_shells.lock().unwrap().remove(&key) {
            live.kill();
        }
        Ok(json!({}))
    }

    /// `session.open`, as `echoctl` and older clients call it: starts the Orchestrator working in
    /// `checkout` (a worktree, or the repo's own folder), else the repo's first, or a new one when
    /// the repo has none.
    fn open_session(self: &Arc<Self>, p: &Value) -> Result<Value> {
        let repo = repo::root(Path::new(str_param(p, "repo")?))?.display().to_string();
        let mut params = p.clone();
        params["repo"] = json!(repo);
        params["kind"] = json!(db::agent_kind::ORCHESTRATOR);
        let orchestrators: Vec<db::Agent> = db::agents(&self.db(), Some(&repo))?
            .into_iter()
            .filter(|agent| agent.kind == db::agent_kind::ORCHESTRATOR)
            .collect();
        let real = |path: &Path| path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
        let checkout = p
            .get("checkout")
            .and_then(Value::as_str)
            .map(|path| real(Path::new(path)));
        let here = checkout.and_then(|checkout| {
            orchestrators
                .iter()
                .find(|agent| real(Path::new(agent.home())) == checkout)
        });
        if let Some(agent) = here.or(orchestrators.first()) {
            params["agent"] = json!(agent.id);
        }
        self.open_agent(&params)
    }

    /// Starts an agent: an existing one by `agent` id (resuming its Claude session), or a new
    /// `kind` (orchestrator, claude, or terminal) in `repo` with an optional `name` and `model`.
    /// A Terminal agent runs nothing of its own: attaching to it starts its shell.
    fn open_agent(self: &Arc<Self>, p: &Value) -> Result<Value> {
        let picked = |key: &str| {
            p.get(key)
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|v| !v.is_empty())
                .map(String::from)
        };
        let id = match p.get("agent").and_then(Value::as_i64) {
            Some(id) => {
                if let Some(name) = picked("team") {
                    let agent = db::agent(&self.db(), id)?;
                    self.check_team(&agent.kind, &agent.repo, &name)?;
                }
                id
            }
            None => {
                let root = repo::root(Path::new(str_param(p, "repo")?))?;
                let repo = root.display().to_string();
                let kind = p
                    .get("kind")
                    .and_then(Value::as_str)
                    .unwrap_or(db::agent_kind::ORCHESTRATOR);
                // A Team that cannot be used refuses the open before a worktree or an agent exists.
                if let Some(name) = picked("team") {
                    self.check_team(kind, &repo, &name)?;
                }
                // Where it works: a branch the human picked, a new branch in a new worktree, or
                // (neither) the repo's own checkout. Made first, so a bad branch starts nothing.
                let place = if let Some(branch) = picked("branch") {
                    Some((repo::checkout(&root, &branch)?, branch))
                } else if let Some(branch) = picked("new_branch") {
                    // A branch that already exists is worked on where it is, not made again.
                    if repo::branches(&root)?.1.iter().any(|b| b.name == branch) {
                        Some((repo::checkout(&root, &branch)?, branch))
                    } else {
                        let base = picked("base").unwrap_or_else(|| "HEAD".into());
                        Some((repo::new_branch_worktree(&root, &branch, &base)?, branch))
                    }
                } else {
                    None
                };
                let id = db::insert_agent(
                    &self.db(),
                    &repo,
                    kind,
                    picked("name").as_deref(),
                    picked("model").as_deref(),
                )?;
                if let Some((cwd, branch)) = &place {
                    repo::copy_into(&root, cwd, &repo::prep(&root)?)?;
                    // The repo's own checkout is no worktree of its own.
                    let cwd = (cwd != &root).then(|| cwd.display().to_string());
                    db::set_agent_place(&self.db(), id, cwd.as_deref(), Some(branch))?;
                }
                self.notify();
                id
            }
        };
        // A model picked now is kept, so a later start or `echoctl` resumes with it.
        if let Some(model) = picked("model") {
            db::set_agent_model(&self.db(), id, &model)?;
        }
        if let Some(cli) = picked("cli") {
            cli::Cli::parse(&cli)?;
            db::set_agent_cli(&self.db(), id, &cli)?;
        }
        if let Some(team) = picked("team") {
            db::set_agent_team(&self.db(), id, &team)?;
        }
        if let Some(name) = picked("name") {
            db::set_agent_name(&self.db(), id, &name)?;
        }
        let agent = db::agent(&self.db(), id)?;
        let view = |started: bool, resumed: bool| {
            json!({ "repo": agent.repo, "agent": agent.id, "kind": agent.kind, "started": started,
                    "resumed": resumed, "model": agent.model, "name": agent.name })
        };
        if self.agent_is_live(id) || agent.kind == db::agent_kind::TERMINAL {
            return Ok(view(false, false));
        }
        let extra: Vec<String> = p
            .get("args")
            .and_then(Value::as_array)
            .map(|args| args.iter().filter_map(|a| a.as_str().map(String::from)).collect())
            .unwrap_or_default();
        let repo = PathBuf::from(&agent.repo);
        let home = PathBuf::from(agent.home());
        let orchestrator = agent.kind == db::agent_kind::ORCHESTRATOR;
        // Read at every start and resume, so an edited Team takes effect at the next one.
        let team = self.agent_team(&agent)?;
        let (agent_cli, model, effort) = agent_pick(&paths::state_dir(), &repo, &agent, team.as_ref())?;
        let resume = agent_cli.has_session(&agent.session_id);
        // What the human asked for up front, like an issue to work on; a resumed session has its own.
        let request = picked("request").filter(|_| !resume);
        let (program, args) = match &self.test_agent {
            Some(test) => {
                // Tests name a Normal session after the fake agent script it should run.
                let script = match orchestrator {
                    true => "orchestrator".to_string(),
                    false => agent.name.clone().unwrap_or_else(|| "claude".into()),
                };
                (test.clone(), std::iter::once(script).chain(request).collect())
            }
            None => {
                let session = launch::Session {
                    id: agent.session_id.clone(),
                    resume,
                    request,
                    model,
                    effort,
                    extra,
                };
                let start = if orchestrator {
                    launch::orchestrator_start(
                        &self.hub_dir,
                        &repo,
                        agent.cwd.as_deref().zip(agent.branch.as_deref()),
                        session,
                        team.as_ref(),
                    )?
                } else {
                    launch::normal_start(&self.hub_dir, &agent, session)
                };
                let start = cli::Start {
                    cwd: Some(home.clone()),
                    ..start
                };
                (agent_cli.program().to_string(), agent_cli.args(&self.hub_dir, &start)?)
            }
        };
        let mut spawn = Spawn {
            cli: agent_cli,
            program,
            args,
            cwd: home,
            env: self.agent_env(None, Some(agent.id))?,
            env_remove: inherited_agent_vars(),
        };
        // Its own worktree, started for the first time: the repo's setup runs there first.
        if !resume && agent.cwd.is_some() {
            if let Some(setup) = repo::prep(&repo)?.setup {
                spawn = with_setup(spawn, &setup);
            }
        }
        let live = Live::spawn(&format!("a{}", agent.id), agent.id, spawn, self.agent_exit())?;
        self.agents.lock().unwrap().insert(agent.id, Arc::clone(&live));
        // Only once the agent is live: an attach before that would start a new shell in its place.
        self.stop_shell(agent.id);
        let hub = Arc::clone(self);
        std::thread::spawn(move || hub.watch_agent(live));
        self.notify();
        Ok(view(true, resume))
    }

    /// A Team an agent may start with: only an Orchestrator has one, and it must exist and validate.
    fn check_team(&self, kind: &str, repo: &str, name: &str) -> Result<()> {
        if kind != db::agent_kind::ORCHESTRATOR {
            bail!("a Team is for an Orchestrator; a Normal session and a Terminal have none");
        }
        self.load_team(repo, name).map(drop)
    }

    fn load_team(&self, repo: &str, name: &str) -> Result<team::Team> {
        team::load(&self.hub_dir, &paths::state_dir(), Some(Path::new(repo)), name)
            .with_context(|| format!("the Team {name:?}"))
    }

    /// The Team an agent starts with, read now; none for an agent with no Team.
    fn agent_team(&self, agent: &db::Agent) -> Result<Option<team::Team>> {
        agent
            .team
            .as_deref()
            .map(|name| self.load_team(&agent.repo, name))
            .transpose()
    }

    /// The CLI an agent is known by before it runs: its own, else its Team's.
    fn agent_stored_cli(&self, agent: &db::Agent) -> Option<String> {
        agent.cli.clone().or_else(|| {
            self.agent_team(agent)
                .ok()
                .flatten()?
                .orchestrator
                .and_then(|setup| setup.cli)
        })
    }

    /// Renews an idle Orchestrator whose context passed the human's `orchestratorRotateAt`
    /// (features/0061). Nothing happens unless that setting is on, the session has made enough
    /// requests to be worth it, and no Worker, message, or question is waiting on it.
    fn renew_if_due(self: &Arc<Self>, id: i64) -> Result<bool> {
        let agent = db::agent(&self.db(), id)?;
        // A Team that cannot be read now leaves the human's size; renewing then reports the Team.
        let team = self.agent_team(&agent).ok().flatten();
        let Some(at) = team::rotate_at(&settings::read(&paths::state_dir())?, team.as_ref()) else {
            return Ok(false);
        };
        if db::agent_has_work(&self.db(), &agent.repo, id)? {
            return Ok(false);
        }
        let Some((requests, context)) = stats::session_context(&agent.session_id) else {
            return Ok(false);
        };
        if requests < MIN_RENEW_REQUESTS || context < at {
            return Ok(false);
        }
        eprintln!("hubd: renewing a{id} at {context} tokens of context after {requests} requests");
        self.renew_agent(id)?;
        Ok(true)
    }

    /// Starts an Orchestrator again on a new Claude session, for a fresh context; the old session
    /// stays in Claude Code's history. What it needs, it reads with `echoctl brief`.
    fn renew_agent(self: &Arc<Self>, id: i64) -> Result<Value> {
        let agent = db::agent(&self.db(), id)?;
        if agent.kind != db::agent_kind::ORCHESTRATOR {
            bail!("only an Orchestrator's session is renewed");
        }
        // Before the session is ended: a Team that cannot start must not leave it stopped.
        self.agent_team(&agent)?;
        db::end_agent_session(&self.db(), id, &agent.session_id)?;
        db::set_agent_session(&self.db(), id, &uuid::Uuid::new_v4().to_string())?;
        self.stop_agent(id);
        for _ in 0..200 {
            if !self.agent_is_live(id) {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        self.open_agent(&json!({ "agent": id, "request": launch::RENEWED }))
    }

    fn agent_exit(self: &Arc<Self>) -> impl FnOnce(i64) + Send + 'static {
        let hub: Weak<Hub> = Arc::downgrade(self);
        move |id| {
            if let Some(hub) = hub.upgrade() {
                hub.agents.lock().unwrap().remove(&id);
                hub.agent_prompts.lock().unwrap().remove(&id);
                hub.notify();
            }
        }
    }

    /// Stops an agent's terminal; it stays on the repo's list, ready to resume.
    fn stop_agent(&self, id: i64) {
        if let Some(live) = self.agents.lock().unwrap().get(&id) {
            live.kill();
        }
    }

    /// Every repo with agents, each with its agents. `live` and `model` describe the repo's first
    /// Orchestrator, as older clients read them.
    fn list_sessions(&self) -> Result<Value> {
        let agents = db::agents(&self.db(), None)?;
        let mut repos: Vec<String> = agents.iter().map(|a| a.repo.clone()).collect();
        repos.sort();
        repos.dedup();
        let out: Vec<Value> = repos
            .iter()
            .map(|repo| {
                let mine: Vec<&db::Agent> = agents.iter().filter(|a| &a.repo == repo).collect();
                let first = mine.iter().find(|a| a.kind == db::agent_kind::ORCHESTRATOR);
                json!({
                    "repo": repo,
                    "session_id": first.map(|a| a.session_id.clone()),
                    "live": mine.iter().any(|a| self.agent_is_live(a.id)),
                    "model": first.and_then(|a| a.model.clone()),
                    "agents": mine.iter().map(|a| self.agent_view(a)).collect::<Vec<_>>(),
                })
            })
            .collect();
        Ok(json!({ "sessions": out }))
    }

    fn agent_view(&self, agent: &db::Agent) -> Value {
        json!({
            "id": agent.id,
            "kind": agent.kind,
            "name": agent.name,
            "model": agent.model,
            "team": agent.team,
            // A Terminal is always ready: attaching starts its shell.
            "live": self.agent_is_live(agent.id) || agent.kind == db::agent_kind::TERMINAL,
            "branch": agent.branch,
            "cwd": agent.cwd,
            "head": repo::head_branch(Path::new(agent.home())),
        })
    }

    /// Names an unnamed agent after the first line the human types into it.
    fn name_from_input(&self, agent: i64, line: &str) -> Result<bool> {
        let Some(name) = name_from_request(line) else {
            return Ok(false);
        };
        let db = self.db();
        if db::agent(&db, agent)?.name.is_some() {
            return Ok(true);
        }
        db::set_agent_name(&db, agent, &name)?;
        drop(db);
        self.notify();
        Ok(true)
    }

    /// The human's multiplexer around one agent's or Worker's terminal, as the line an Echo pane
    /// runs in a login shell (`echoctl mux`): `command` (e.g.
    /// `tmux new-session -A -s {session} -c {dir} {command}`) with `{session}` a stable name for
    /// the target, `{dir}` where it works, and `{command}` a `echoctl attach --follow` that shows the
    /// target in the multiplexer's first pane. The pane runs it itself, so no daemon shell and no
    /// relay sit between Echo and the multiplexer.
    fn mux_command(&self, p: &Value) -> Result<Value> {
        let template = str_param(p, "command")?;
        let (label, repo, dir) = if let Some(id) = p.get("agent").and_then(Value::as_i64) {
            let agent = db::agent(&self.db(), id)?;
            (format!("a{id}"), agent.repo.clone(), agent.home().to_string())
        } else {
            let id = id_param(p, "id")?;
            let worker = db::worker(&self.db(), id)?;
            (format!("w{id}"), worker.repo, worker.cwd)
        };
        let name = Path::new(&repo)
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let session = mux_session(&name, &label);
        // The multiplexer's server may have been started elsewhere, so this daemon is named.
        let attach = [
            "env".to_string(),
            format!("HUB_STATE={}", paths::state_dir().display()),
            std::env::current_exe()?.display().to_string(),
            "attach".into(),
            "--follow".into(),
            label,
        ]
        .iter()
        .map(|word| shell_quote(word))
        .collect::<Vec<_>>()
        .join(" ");
        let command = template
            .replace("{session}", &shell_quote(&session))
            .replace("{dir}", &shell_quote(&dir))
            .replace("{command}", &shell_quote(&attach));
        Ok(json!({ "command": command, "session": session, "dir": dir }))
    }

    /// Takes over every terminal the holder kept while no daemon ran; a Worker that was live and
    /// whose terminal is gone is lost.
    fn recover(self: &Arc<Self>) -> Result<()> {
        let state = paths::state_dir();
        for key in holder::list() {
            // A checkout's side shell: `t` and the hex of its path. One whose path is gone is let go.
            if let Some(hex) = key.strip_prefix('t') {
                let path = unhex(hex).filter(|path| side_dir(path).is_ok());
                match path {
                    Some(path) => {
                        let path = side_dir(&path)?.display().to_string();
                        match Live::adopt(&key, 0, cli::Cli::Claude, self.side_exit(path.clone())) {
                            Ok(Some(live)) => {
                                self.side_shells.lock().unwrap().insert(path, live);
                                eprintln!("hubd: took over {key}");
                            }
                            Ok(None) => {}
                            Err(error) => eprintln!("hubd: could not take over {key}: {error:#}"),
                        }
                    }
                    None => {
                        if let Ok(Some(live)) = Live::adopt(&key, 0, cli::Cli::Claude, |_| {}) {
                            live.kill();
                        }
                    }
                }
                continue;
            }
            let (Some(kind), Ok(id)) = (key.chars().next(), key[1..].parse::<i64>()) else {
                continue;
            };
            let adopted = match kind {
                'w' => db::worker(&self.db(), id).ok().map(|worker| {
                    let repo = Path::new(&worker.repo);
                    let picked = cli::Choice {
                        cli: worker.cli.clone(),
                        model: worker.model.clone(),
                    };
                    let profile = profile::load(&self.hub_dir, &state, Some(repo), &worker.profile)
                        .ok()
                        .map(|profile| profile.choice());
                    let worker_cli = cli::recovered(&state, Some(repo), profile.as_ref(), &[&picked]);
                    Live::adopt(&key, id, worker_cli, self.worker_exit()).map(|live| {
                        live.map(|live| {
                            self.live.lock().unwrap().insert(id, Arc::clone(&live));
                            let hub = Arc::clone(self);
                            std::thread::spawn(move || hub.watch(live));
                        })
                    })
                }),
                'a' => db::agent(&self.db(), id).ok().map(|agent| {
                    let choice = cli::Choice {
                        cli: self.agent_stored_cli(&agent),
                        model: agent.model.clone(),
                    };
                    let agent_cli = cli::recovered(&state, Some(Path::new(&agent.repo)), None, &[&choice]);
                    Live::adopt(&key, id, agent_cli, self.agent_exit()).map(|live| {
                        live.map(|live| {
                            self.agents.lock().unwrap().insert(id, Arc::clone(&live));
                            let hub = Arc::clone(self);
                            std::thread::spawn(move || hub.watch_agent(live));
                        })
                    })
                }),
                's' => Some(Live::adopt(&key, id, cli::Cli::Claude, self.shell_exit()).map(|live| {
                    live.map(|live| {
                        self.shells.lock().unwrap().insert(id, live);
                    })
                })),
                _ => None,
            };
            match adopted {
                Some(Ok(_)) => eprintln!("hubd: took over {key}"),
                Some(Err(error)) => eprintln!("hubd: could not take over {key}: {error:#}"),
                // Nothing in the database owns it any more.
                None => {
                    if let Ok(Some(live)) = Live::adopt(&key, id, cli::Cli::Claude, |_| {}) {
                        live.kill();
                    }
                }
            }
        }
        let held: Vec<i64> = self.live.lock().unwrap().keys().copied().collect();
        let db = self.db();
        for worker in db::mark_lost(&db, &held)? {
            let body = format!(
                "The Hub Daemon restarted while w{} was live; its terminal is gone. Resume it: echoctl worker resume w{}",
                worker.id, worker.id
            );
            db::insert_message(&db, &worker, kind::LOST, &body)?;
        }
        Ok(())
    }

    fn handle(self: &Arc<Self>, stream: UnixStream) -> Result<()> {
        let mut reader = BufReader::new(stream.try_clone()?);
        let mut line = String::new();
        if reader.read_line(&mut line)? == 0 {
            return Ok(());
        }
        let request: proto::Request = serde_json::from_str(&line).context("bad request line")?;
        if request.method == "attach" {
            return self.attach(&request.params, reader, stream);
        }
        if request.method == "events" {
            return self.events(&request.params, stream);
        }
        let response = match self.dispatch(&request.method, &request.params, &stream) {
            Ok(result) => proto::ok(result),
            Err(error) => proto::err(&error),
        };
        let mut out = stream;
        proto::write_line(&mut out, &response)
    }

    fn dispatch(self: &Arc<Self>, method: &str, p: &Value, stream: &UnixStream) -> Result<Value> {
        match method {
            // `exe` is the `echoctl` that Echo's terminal panes run (`echoctl attach --echo`).
            "ping" => Ok(json!({
                "pid": std::process::id(),
                "exe": std::env::current_exe()?.display().to_string(),
            })),
            "worker.start" => self.start_worker(p),
            "worker.list" => self.list_workers(str_param(p, "repo")?, p.get("agent").and_then(Value::as_i64)),
            "status" => self.status(str_param(p, "repo")?),
            "worker.read" => {
                let live = self.live(id_param(p, "id")?)?;
                let lines = p.get("lines").and_then(Value::as_u64).unwrap_or(0) as usize;
                let screen = live.screen();
                Ok(json!({ "screen": if lines > 0 { screen::tail(&screen, lines) } else { screen } }))
            }
            "worker.send" => {
                let id = id_param(p, "id")?;
                let live = self.live(id)?;
                if !p.get("force").and_then(Value::as_bool).unwrap_or(false) {
                    refuse_over_dialog(&live)?;
                }
                let text = str_param(p, "text")?;
                if !p.get("enter").and_then(Value::as_bool).unwrap_or(true) {
                    live.write(text.as_bytes())?;
                    return Ok(json!({}));
                }
                db::insert_input(&self.db(), id, db::origin::ORCHESTRATOR, text)?;
                type_in(&live, text)?;
                Ok(json!({ "started": started(&live) }))
            }
            "worker.key" => {
                let live = self.live(id_param(p, "id")?)?;
                for key in param(p, "keys")?.as_array().context("keys must be a list")? {
                    live.write(&key_bytes(key.as_str().unwrap_or_default())?)?;
                    std::thread::sleep(Duration::from_millis(100));
                }
                Ok(json!({}))
            }
            // Bytes exactly as given, for what Echo types itself: dropped paths, notes, tmux keys.
            "terminal.write" => {
                self.terminal(p)?.write(str_param(p, "text")?.as_bytes())?;
                Ok(json!({}))
            }
            "terminal.resize" => {
                let live = self.terminal(p)?;
                live.resize(id_param(p, "rows")? as u16, id_param(p, "cols")? as u16)?;
                Ok(json!({}))
            }
            "side.status" => self.side_status(p),
            "side.stop" => self.side_stop(p),
            // Echo Remote's message box and keys: an agent's or Worker's running terminal only.
            "terminal.send" => {
                let agent = p.get("agent").and_then(Value::as_i64);
                let live = self
                    .running_terminal(agent, p.get("id").and_then(Value::as_i64))
                    .context("it is not running")?;
                let text = str_param(p, "text")?;
                // Several lines as one paste, so the first line break does not send the rest early.
                if text.contains('\n') && live.with_screen(|s| s.bracketed_paste()) {
                    live.write(format!("\x1b[200~{text}\x1b[201~").as_bytes())?;
                } else {
                    live.write(text.as_bytes())?;
                }
                if p.get("enter").and_then(Value::as_bool).unwrap_or(true) {
                    std::thread::sleep(Duration::from_millis(150));
                    live.write(b"\r")?;
                }
                if let Some(id) = agent.filter(|&id| self.agent_is_live(id)) {
                    self.name_from_input(id, text.lines().next().unwrap_or(""))?;
                }
                Ok(json!({}))
            }
            "terminal.key" => {
                let live = self
                    .running_terminal(
                        p.get("agent").and_then(Value::as_i64),
                        p.get("id").and_then(Value::as_i64),
                    )
                    .context("it is not running")?;
                for key in param(p, "keys")?.as_array().context("keys must be a list")? {
                    live.write(&key_bytes(key.as_str().unwrap_or_default())?)?;
                    std::thread::sleep(Duration::from_millis(100));
                }
                Ok(json!({}))
            }
            // An agent's conversation as chat items (ADR 0010). `after` continues from the `end` a
            // read gave, while the agent stays on the same `session`.
            // An agent's or Worker's conversation as chat items (ADR 0010). `after` continues from
            // the `end` a read gave, while it stays on the same `session`.
            "chat.read" => self.chat_read(p),
            // What `/` completes in the chat's message box.
            "chat.commands" => {
                let (session, cwd, cli) = match p.get("worker").and_then(Value::as_i64) {
                    Some(id) => {
                        let worker = db::worker(&self.db(), id)?;
                        let cli = self.chat_cli(worker.cli.as_deref(), &worker.repo, Some(&worker.profile));
                        (worker.session_id, PathBuf::from(worker.cwd), cli)
                    }
                    None => {
                        let agent = db::agent(&self.db(), id_param(p, "agent")?)?;
                        let cwd = agent
                            .cwd
                            .clone()
                            .map(PathBuf::from)
                            .unwrap_or_else(|| PathBuf::from(&agent.repo));
                        let cli = self.chat_cli(self.agent_stored_cli(&agent).as_deref(), &agent.repo, None);
                        (agent.session_id, cwd, cli)
                    }
                };
                // Kiro's slash commands are not Claude Code's, and no fixed list of its own is
                // known (features/0077), so its chat completes none.
                if cli == Some(cli::Cli::Kiro) {
                    return Ok(json!({ "commands": [] }));
                }
                let transcript = stats::transcript(&stats::projects_dir(), &session);
                let dirs = [paths::home().join(".claude/commands"), cwd.join(".claude/commands")];
                Ok(json!({ "commands": chat::commands(transcript.as_deref(), &dirs) }))
            }
            // The chat's message box: typed at the input box, never over a prompt it shows
            // (features/0045), so text cannot answer it. Into a Worker it is an Intervention.
            "chat.send" => {
                let text = str_param(p, "text")?;
                let live = match p.get("worker").and_then(Value::as_i64) {
                    Some(id) => self.live(id).context("it is not running")?,
                    None => self
                        .agent_live(id_param(p, "agent")?)
                        .context("it is not running; start it first")?,
                };
                match live.cli.look(&live.screen()) {
                    Look::PermissionPrompt => bail!("it shows a permission prompt; Approve or Deny it first"),
                    Look::TrustPrompt => bail!("it still shows its folder-trust dialog; try again in a moment"),
                    _ => {}
                }
                match p.get("worker").and_then(Value::as_i64) {
                    Some(id) => db::insert_input(&self.db(), id, db::origin::HUMAN, text)?,
                    None => {
                        self.name_from_input(id_param(p, "agent")?, text.lines().next().unwrap_or(""))?;
                    }
                }
                type_in(&live, text)?;
                Ok(json!({}))
            }
            // Esc from the chat: interrupts the turn.
            "chat.interrupt" => {
                let live = match p.get("worker").and_then(Value::as_i64) {
                    Some(id) => self.live(id)?,
                    None => self.agent_live(id_param(p, "agent")?).context("it is not running")?,
                };
                live.write(b"\x1b")?;
                Ok(json!({}))
            }
            "remote.status" => Ok(remote::status(self)),
            "remote.enable" => remote::enable(self, p.get("port").and_then(Value::as_u64).map(|p| p as u16)),
            "remote.disable" => remote::disable(self),
            "remote.pair" => remote::new_pairing(self),
            "session.open" => self.open_session(p),
            "session.close" => {
                let repo = repo::root(Path::new(str_param(p, "repo")?))?.display().to_string();
                for agent in db::agents(&self.db(), Some(&repo))? {
                    self.stop_agent(agent.id);
                }
                Ok(json!({}))
            }
            "agent.open" => self.open_agent(p),
            "agent.renew" => self.renew_agent(id_param(p, "agent")?),
            "ui" => self.ui(p),
            "agent.close" => {
                self.stop_agent(id_param(p, "agent")?);
                Ok(json!({}))
            }
            "agent.forget" => {
                let id = id_param(p, "agent")?;
                self.stop_agent(id);
                self.stop_shell(id);
                db::close_agent(&self.db(), id)?;
                self.notify();
                Ok(json!({}))
            }
            "agent.rename" => {
                let name = str_param(p, "name")?.trim();
                if name.is_empty() {
                    bail!("a name cannot be empty");
                }
                db::set_agent_name(&self.db(), id_param(p, "agent")?, name)?;
                self.notify();
                Ok(json!({}))
            }
            "sessions.list" => self.list_sessions(),
            "mux.command" => self.mux_command(p),
            "shell.env" => Ok(json!(shell_env())),
            "usage.refresh" => {
                self.refresh_usage();
                self.refresh_kiro_usage();
                Ok(json!({}))
            }
            "usage" => Ok(self.usage.lock().unwrap().view()),
            "stats" => {
                let days = p.get("days").and_then(Value::as_i64).unwrap_or(7).max(1);
                let since = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)?
                    .as_secs() as i64
                    - days * 86_400;
                let workers = db::worker_sessions_since(&self.db(), since)?;
                let orchestrators = db::orchestrator_sessions_since(&self.db(), since)?;
                let mut report = stats::report(&workers);
                report["orchestrators"] = stats::orchestrators(&orchestrators, since);
                Ok(report)
            }
            "decide" => self.decide(p),
            "worker.close" => self.close_worker(id_param(p, "id")?),
            "worker.dismiss" => {
                db::mark_dismissed(&self.db(), id_param(p, "id")?)?;
                self.notify();
                Ok(json!({}))
            }
            "worker.resume" => self.resume_worker(id_param(p, "id")?),
            "worker.task" => {
                let mut spec = p
                    .get("spec")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .trim_end()
                    .to_string();
                if let Some(from) = p.get("from_report").and_then(Value::as_i64) {
                    let source = db::worker(&self.db(), from).with_context(|| format!("--from-report w{from}"))?;
                    spec = spec_with_report(&spec, &source)?;
                }
                if spec.trim().is_empty() {
                    bail!("give --spec, --spec-file, or --from-report");
                }
                self.next_task(id_param(p, "id")?, &spec, db::origin::ORCHESTRATOR)
            }
            "worker.diff" => {
                let worker = db::worker(&self.db(), id_param(p, "id")?)?;
                let cwd = Path::new(&worker.cwd);
                if !cwd.exists() {
                    bail!("w{}'s folder {} is gone", worker.id, worker.cwd);
                }
                let home = self.home_of(worker.agent_id, &worker.repo);
                let (diff, cut) = repo::diff(&home, cwd, worker.branch.is_some())?;
                Ok(json!({ "diff": diff, "truncated": cut, "branch": worker.branch, "cwd": worker.cwd }))
            }
            "worker.review" => self.review_worker(p),
            "worker.fanout" => self.fan_out(p),
            "branches.list" => {
                let root = repo::root(Path::new(str_param(p, "repo")?))?;
                let (current, branches) = repo::branches(&root)?;
                let agents = db::agents(&self.db(), Some(&root.display().to_string()))?;
                let rows: Vec<Value> = branches
                    .iter()
                    .map(|b| {
                        let agent = agents
                            .iter()
                            .find(|a| a.branch.as_deref() == Some(b.name.as_str()))
                            .map(|a| a.id);
                        json!({ "name": b.name, "checkout": b.checkout, "agent": agent })
                    })
                    .collect();
                Ok(json!({ "current": current, "branches": rows }))
            }
            "profiles.list" => {
                let repo = p
                    .get("repo")
                    .and_then(Value::as_str)
                    .map(|r| repo::root(Path::new(r)))
                    .transpose()?;
                let state = paths::state_dir();
                let mut broken = Vec::new();
                let mut profiles = Vec::new();
                for entry in profile::entries(&self.hub_dir, &state, repo.as_deref()) {
                    let p = match &entry.profile {
                        Ok(p) => p,
                        Err(e) => {
                            broken.push(json!({ "name": entry.name, "level": entry.level.label(), "path": entry.path, "error": e }));
                            continue;
                        }
                    };
                    let (cli, model, problem) = match cli::pick(&state, repo.as_deref(), Some(&p.choice()), &[]) {
                        Ok((cli, model)) => (cli.name().to_string(), model, None),
                        Err(e) => (
                            p.cli.clone().unwrap_or_else(|| "claude".into()),
                            p.model.clone(),
                            Some(e.to_string()),
                        ),
                    };
                    profiles.push(json!({
                        "name": p.name, "description": p.description, "writes": p.writes,
                        // What it runs with here, and what its own file says.
                        "cli": cli, "model": model.unwrap_or_else(|| format!("{cli} default")),
                        "ownCli": p.cli, "ownModel": p.model, "effort": p.effort,
                        "level": entry.level.label(), "path": entry.path,
                        "replaces": entry.replaces.iter().map(|l| l.label()).collect::<Vec<_>>(),
                        "problem": problem,
                    }));
                }
                Ok(json!({ "profiles": profiles, "broken": broken }))
            }
            "profile.copy" | "profile.new" | "profile.reset" | "profile.set" => {
                let repo = p
                    .get("repo")
                    .and_then(Value::as_str)
                    .map(|r| repo::root(Path::new(r)))
                    .transpose()?;
                let state = paths::state_dir();
                let name = str_param(p, "name")?;
                let level = profile::Level::parse(p.get("level").and_then(Value::as_str).unwrap_or("yours"))?;
                let path = match method {
                    "profile.copy" => profile::copy(&self.hub_dir, &state, repo.as_deref(), name, level)?.0,
                    "profile.new" => profile::create(&self.hub_dir, &state, repo.as_deref(), name, level)?,
                    "profile.reset" => {
                        profile::reset(&state, repo.as_deref(), name, level)?;
                        PathBuf::new()
                    }
                    _ => {
                        // A field set on Echo's own Profile goes into a copy of it first.
                        let dir = profile::level_dir(&state, repo.as_deref(), level)?;
                        let path = dir.join(format!("{name}.md"));
                        if !path.exists() {
                            profile::copy(&self.hub_dir, &state, repo.as_deref(), name, level)?;
                        }
                        let fields = param(p, "fields")?.as_object().context("fields must be an object")?;
                        let mut set = Vec::new();
                        for key in ["cli", "model", "effort", "description"] {
                            if let Some(value) = fields.get(key) {
                                set.push((key, value.as_str().filter(|v| !v.is_empty())));
                            }
                        }
                        profile::set_fields(&path, &set)?;
                        path
                    }
                };
                Ok(json!({ "path": path }))
            }
            "memory.get" => {
                let state = paths::state_dir();
                let prefs_path = lessons::preferences_path(&state, &self.hub_dir);
                let prefs = std::fs::read_to_string(&prefs_path).unwrap_or_default();
                let mut out = json!({ "preferences": { "path": prefs_path, "sections": lessons::sections(&prefs),
                                                     "bullets": lessons::bullets(&prefs) } });
                if let Some(repo) = p.get("repo").and_then(Value::as_str) {
                    let key = repo::root(Path::new(repo))?.display().to_string();
                    let path = lessons::lessons_path(&state, &key);
                    let text = std::fs::read_to_string(&path).unwrap_or_default();
                    out["lessons"] =
                        json!({ "path": path, "bullets": lessons::bullets(&text), "limit": lessons::LIMIT });
                }
                Ok(out)
            }
            "memory.add" | "memory.remove" => {
                let state = paths::state_dir();
                let path = match str_param(p, "file")? {
                    "preferences" => lessons::preferences_path(&state, &self.hub_dir),
                    "lessons" => {
                        let key = repo::root(Path::new(str_param(p, "repo")?))?.display().to_string();
                        lessons::lessons_path(&state, &key)
                    }
                    other => bail!("no such file {other:?}; preferences or lessons"),
                };
                let text = str_param(p, "text")?;
                if method == "memory.remove" {
                    lessons::remove(&path, text)?;
                } else if str_param(p, "file")? == "lessons" {
                    let today: String = self
                        .db()
                        .query_row("select date('now', 'localtime')", [], |row| row.get(0))?;
                    let key = repo::root(Path::new(str_param(p, "repo")?))?.display().to_string();
                    lessons::add(&state, &key, "you", &today, &[text.to_string()])?;
                } else {
                    let today: String = self
                        .db()
                        .query_row("select date('now', 'localtime')", [], |row| row.get(0))?;
                    lessons::add_to_section(
                        &path,
                        p.get("section").and_then(Value::as_str).unwrap_or(""),
                        text,
                        &today,
                    )?;
                }
                Ok(json!({}))
            }
            "repo.settings.get" | "repo.settings.set" => {
                let root = repo::root(Path::new(str_param(p, "repo")?))?;
                let dir = root.join(".echo");
                if method == "repo.settings.set" {
                    let patch = param(p, "settings")?
                        .as_object()
                        .context("settings must be an object")?;
                    if let Some(key) = patch.keys().find(|k| !["copy", "setup"].contains(&k.as_str())) {
                        bail!("unknown repo setting {key:?}; copy or setup");
                    }
                    // Checked before it is written, so a bad path never reaches the file.
                    let mut check = settings::read(&dir)?;
                    check.extend(patch.clone());
                    repo::prep_from(&check)?;
                    settings::update(&dir, patch)?;
                }
                let prep = repo::prep(&root)?;
                Ok(json!({ "repo": root, "path": dir.join("settings.json"), "copy": prep.copy, "setup": prep.setup }))
            }
            "settings.get" => {
                let all = settings::read(&paths::state_dir())?;
                Ok(
                    json!({ "cli": all.get("cli"), "model": all.get("model"), "forceCli": all.get("forceCli"),
                           "orchestratorModel": all.get("orchestratorModel"),
                           "orchestratorEffort": all.get("orchestratorEffort"),
                           "orchestratorLessons": settings::orchestrator_lessons(&all),
                           "orchestratorRotateAt": settings::orchestrator_rotate_at(&all),
                           "orchestrator": settings::Rules::from(&all).view() }),
                )
            }
            "settings.set" => {
                let patch = param(p, "settings")?
                    .as_object()
                    .context("settings must be an object")?;
                let allowed = [
                    "cli",
                    "model",
                    "forceCli",
                    "orchestratorModel",
                    "orchestratorEffort",
                    "orchestratorLessons",
                    "orchestratorRotateAt",
                    "maxWorkers",
                    "planApproval",
                    "review",
                    "mergeWithoutAsking",
                ];
                if let Some(key) = patch.keys().find(|k| !allowed.contains(&k.as_str())) {
                    bail!("unknown setting {key:?}");
                }
                if let Some(name) = patch.get("cli").and_then(Value::as_str).filter(|v| !v.is_empty()) {
                    cli::Cli::parse(name)?;
                }
                if let Some(force) = patch.get("forceCli") {
                    if !(force.is_boolean() || force.is_null() || force.as_str() == Some("")) {
                        bail!("forceCli must be true or false");
                    }
                }
                if let Some(effort) = patch
                    .get("orchestratorEffort")
                    .and_then(Value::as_str)
                    .filter(|v| !v.is_empty())
                {
                    if !settings::EFFORTS.contains(&effort) {
                        bail!("orchestratorEffort must be one of {}", settings::EFFORTS.join(", "));
                    }
                }
                let all = settings::update(&paths::state_dir(), patch)?;
                Ok(
                    json!({ "cli": all.get("cli"), "model": all.get("model"), "forceCli": all.get("forceCli"),
                           "orchestratorModel": all.get("orchestratorModel"),
                           "orchestratorEffort": all.get("orchestratorEffort"),
                           "orchestratorLessons": settings::orchestrator_lessons(&all),
                           "orchestratorRotateAt": settings::orchestrator_rotate_at(&all),
                           "orchestrator": settings::Rules::from(&all).view() }),
                )
            }
            "worker.pick" => self.pick_worker(id_param(p, "id")?),
            "send" => {
                let worker = db::worker(&self.db(), id_param(p, "worker")?)?;
                let message_kind = str_param(p, "kind")?;
                if ![kind::ESCALATION, kind::STATUS].contains(&message_kind) {
                    bail!("send --type must be escalation or status (use echoctl ask, echoctl done for the rest)");
                }
                let id = db::insert_message(&self.db(), &worker, message_kind, str_param(p, "body")?)?;
                self.notify();
                Ok(json!({ "message": id }))
            }
            "ask" => self.ask(p, stream),
            "done" => {
                let id = id_param(p, "worker")?;
                let final_state = str_param(p, "state")?;
                if ![state::DONE, state::BLOCKED].contains(&final_state) {
                    bail!("done --state must be done or blocked");
                }
                let mut body = str_param(p, "body")?.to_string();
                let new: Vec<String> = p
                    .get("lessons")
                    .and_then(Value::as_array)
                    .map(|all| all.iter().filter_map(Value::as_str).map(str::to_string).collect())
                    .unwrap_or_default();
                let db = self.db();
                let worker = db::worker(&db, id)?;
                if !state::is_live(&worker.state) {
                    bail!("w{id} already settled as {}", worker.state);
                }
                if !new.is_empty() {
                    let today: String = db.query_row("select date('now', 'localtime')", [], |row| row.get(0))?;
                    let state = paths::state_dir();
                    let count = lessons::add(&state, &worker.repo, &format!("w{id}"), &today, &new)?;
                    body = format!("{}\n\nLessons added:\n", body.trim_end());
                    for lesson in &new {
                        body += &format!("- {lesson}\n");
                    }
                    if count > lessons::LIMIT {
                        body += &format!(
                            "The repo now has {count} Lessons, over {}: have an ino Worker merge {}.\n",
                            lessons::LIMIT,
                            lessons::lessons_path(&state, &worker.repo).display()
                        );
                    }
                }
                db::settle(&db, id, final_state, &body)?;
                // A verifier reports to the daemon, and a writer it verifies is heard of only
                // once the verdict is in (features/0055); the Orchestrator hears of neither yet.
                let verifying = worker.verify && final_state == state::DONE;
                if worker.verifies.is_none() && !verifying {
                    db::insert_message(&db, &worker, kind::DONE, &body)?;
                }
                drop(db);
                self.notify();
                let hub = Arc::clone(self);
                if let Some(writer) = worker.verifies {
                    let final_state = final_state.to_string();
                    std::thread::spawn(move || hub.verified(id, writer, &final_state, &body));
                } else if verifying {
                    std::thread::spawn(move || hub.verify(id));
                }
                Ok(json!({}))
            }
            "session" => {
                let session = str_param(p, "session_id")?;
                if let Some(worker) = p.get("worker").and_then(Value::as_i64) {
                    db::set_worker_session(&self.db(), worker, session)?;
                } else if let Some(agent) = p.get("agent").and_then(Value::as_i64) {
                    db::set_agent_session(&self.db(), agent, session)?;
                }
                Ok(json!({}))
            }
            "notify" => {
                let live = self.live(id_param(p, "worker")?)?;
                let kind = str_param(p, "kind")?;
                // Idle only because a background shell still runs: nothing for the human to do.
                if !(kind == "idle_prompt" && live.cli.look(&live.screen()) == Look::Waiting) {
                    self.report_blocker(&live, kind, p["message"].as_str().unwrap_or(""))?;
                }
                Ok(json!({}))
            }
            "wait" => self.wait(
                str_param(p, "repo")?,
                p.get("agent").and_then(Value::as_i64),
                timeout_param(p, Duration::from_secs(3600)),
                stream,
            ),
            "reply" => {
                let id = id_param(p, "id")?;
                let body = str_param(p, "body")?;
                let db = self.db();
                db::answer(&db, id, body)?;
                if p.get("by_human").and_then(Value::as_bool).unwrap_or(false) {
                    let question = db::message(&db, id)?;
                    let worker = db::worker(&db, question.worker_id)?;
                    let note = format!(
                        "The human answered question #{id} from w{} in the Hub App:\n{body}",
                        worker.id
                    );
                    db::insert_message(&db, &worker, kind::HUMAN, &note)?;
                }
                drop(db);
                self.notify();
                Ok(json!({}))
            }
            "inbox" => {
                let repo = str_param(p, "repo")?;
                let db = self.db();
                let mut open = Vec::new();
                for worker in db::workers(&db, repo)? {
                    open.extend(db::open_questions(&db, worker.id)?);
                }
                Ok(json!({ "open_questions": open }))
            }
            "shutdown" => {
                // Without --force the terminals keep running in the holder, for the next daemon.
                if !p.get("force").and_then(Value::as_bool).unwrap_or(false) {
                    let _ = std::fs::remove_file(paths::socket());
                    std::thread::spawn(|| {
                        std::thread::sleep(Duration::from_millis(200));
                        std::process::exit(0);
                    });
                    return Ok(json!({}));
                }
                let killed: Vec<Arc<Live>> = self.live.lock().unwrap().values().cloned().collect();
                for live in &killed {
                    live.closing.store(true, std::sync::atomic::Ordering::SeqCst);
                    live.kill();
                }
                // Record the closes now: the process exits before every exit callback runs.
                let db = self.db();
                for live in &killed {
                    let worker = db::worker(&db, live.id)?;
                    if state::is_live(&worker.state) {
                        db::settle(&db, live.id, state::EXITED, "stopped by echoctl shutdown --force")?;
                    }
                    db::mark_closed(&db, live.id)?;
                }
                drop(db);
                for live in self.agents.lock().unwrap().values() {
                    live.kill();
                }
                for live in self.shells.lock().unwrap().values() {
                    live.kill();
                }
                for live in self.side_shells.lock().unwrap().values() {
                    live.kill();
                }
                holder::quit();
                let _ = std::fs::remove_file(paths::socket());
                std::thread::spawn(|| {
                    std::thread::sleep(Duration::from_millis(200));
                    std::process::exit(0);
                });
                Ok(json!({}))
            }
            other => bail!("unknown method {other}"),
        }
    }

    /// A Worker's Profile and the CLI and model picked for it.
    fn pick_for(&self, worker: &Worker) -> Result<(profile::Profile, cli::Cli, Option<String>)> {
        let repo = Path::new(&worker.repo);
        let profile = profile::load(&self.hub_dir, &paths::state_dir(), Some(repo), &worker.profile)?;
        let picked = cli::Choice {
            cli: worker.cli.clone(),
            model: worker.model.clone(),
        };
        let (worker_cli, model) = cli::pick(&paths::state_dir(), Some(repo), Some(&profile.choice()), &[&picked])?;
        Ok((profile, worker_cli, model))
    }

    fn spawn_for(&self, worker: &Worker, launch: Launch) -> Result<Spawn> {
        let launch_kind = match launch {
            Launch::New { .. } => LaunchKind::New,
            Launch::Resume { .. } | Launch::Next { .. } => LaunchKind::Resume,
        };
        let (worker_cli, program, args) = match &self.test_agent {
            Some(agent) => {
                let spec = match launch {
                    Launch::New { spec } | Launch::Next { spec } => spec.to_string(),
                    Launch::Resume { .. } => "resume".to_string(),
                };
                (cli::Cli::Claude, agent.clone(), vec![spec])
            }
            None => {
                let (profile, worker_cli, model) = self.pick_for(worker)?;
                let start = profile::start(
                    &self.hub_dir,
                    &worker.repo,
                    &profile,
                    &worker.title,
                    &worker.session_id,
                    launch,
                    (worker_cli, model),
                )?;
                let start = cli::Start {
                    cwd: Some(PathBuf::from(&worker.cwd)),
                    ..start
                };
                (
                    worker_cli,
                    worker_cli.program().to_string(),
                    worker_cli.args(&self.hub_dir, &start)?,
                )
            }
        };
        let fresh = matches!(launch_kind, LaunchKind::New) && worker.branch.is_some();
        let spawn = Spawn {
            cli: worker_cli,
            program,
            args,
            cwd: PathBuf::from(&worker.cwd),
            env: self.agent_env(Some(worker.id), None)?,
            env_remove: inherited_agent_vars(),
        };
        Ok(match repo::prep(Path::new(&worker.repo))?.setup.filter(|_| fresh) {
            Some(setup) => with_setup(spawn, &setup),
            None => spawn,
        })
    }

    /// Environment for an agent terminal. This `echoctl` comes first on PATH, so the agent's `echoctl`
    /// commands and its Notification hook reach this daemon.
    fn agent_env(&self, worker: Option<i64>, agent: Option<i64>) -> Result<Vec<(String, String)>> {
        let exe_dir = std::env::current_exe()?
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_default();
        let path = format!("{}:{}", exe_dir.display(), std::env::var("PATH").unwrap_or_default());
        let mut env = vec![
            ("PATH".to_string(), path),
            ("ECHO_REPO".into(), self.hub_dir.display().to_string()),
            ("HUB_STATE".into(), paths::state_dir().display().to_string()),
            ("TERM".into(), "xterm-256color".into()),
            ("COLORTERM".into(), "truecolor".into()),
        ];
        if let Some(id) = worker {
            env.push(("HUB_WORKER".into(), id.to_string()));
        }
        // An Orchestrator's `echoctl worker start` and `echoctl wait` name it, so Workers and their
        // messages stay with the Orchestrator that started them.
        if let Some(id) = agent {
            env.push(("HUB_AGENT".into(), id.to_string()));
        }
        Ok(env)
    }

    fn launch(self: &Arc<Self>, worker: &Worker, launch: Launch) -> Result<()> {
        let spawn = self.spawn_for(worker, launch)?;
        let live = Live::spawn(&format!("w{}", worker.id), worker.id, spawn, self.worker_exit())?;
        self.live.lock().unwrap().insert(worker.id, Arc::clone(&live));
        let hub = Arc::clone(self);
        std::thread::spawn(move || hub.watch(live));
        Ok(())
    }

    fn worker_exit(self: &Arc<Self>) -> impl FnOnce(i64) + Send + 'static {
        let hub: Weak<Hub> = Arc::downgrade(self);
        move |id| {
            if let Some(hub) = hub.upgrade() {
                if let Err(error) = hub.on_exit(id) {
                    eprintln!("hubd: w{id} exit: {error:#}");
                }
            }
        }
    }

    fn start_worker(self: &Arc<Self>, p: &Value) -> Result<Value> {
        // The repo's main checkout, as every other method keys it, whatever path names it.
        let repo_root = repo::root(Path::new(str_param(p, "repo")?))?;
        let profile_name = str_param(p, "profile")?;
        let profile = profile::load(&self.hub_dir, &paths::state_dir(), Some(&repo_root), profile_name)?;
        let picked = |key: &str| {
            p.get(key)
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|v| !v.is_empty())
        };
        let runs = cli::Choice {
            cli: picked("cli").map(String::from),
            model: picked("model").map(String::from),
        };
        // A CLI or model that cannot run, or a Kiro Worker without its notes, fails here, before a
        // worktree is made for it.
        let (worker_cli, _) = cli::pick(&paths::state_dir(), Some(&repo_root), Some(&profile.choice()), &[&runs])?;
        worker_cli.check_worker_notes(&self.hub_dir)?;
        let spec = str_param(p, "spec")?;
        let title = match p.get("title").and_then(Value::as_str) {
            Some(title) if !title.trim().is_empty() => title.to_string(),
            _ => title_from_spec(spec),
        };
        // The Orchestrator starting it (`HUB_AGENT` via `echoctl worker start`), else the repo's first.
        let agent = match p.get("agent").and_then(Value::as_i64) {
            Some(agent) => Some(agent),
            None => db::first_orchestrator(&self.db(), &repo_root.display().to_string())?.map(|a| a.id),
        };
        // In place means where its Orchestrator works, which may be that agent's own worktree.
        let home = self.home_of(agent, &repo_root.display().to_string());
        let choice = p.get("worktree").and_then(Value::as_str).unwrap_or("current");
        let (cwd, branch) = if choice == "current" {
            (home.clone(), None)
        } else if let Some(branch) = choice.strip_prefix("new:") {
            (
                repo::create_worktree(&repo_root, branch, &home)?,
                Some(branch.to_string()),
            )
        } else if let Some(path) = choice.strip_prefix("path:") {
            let path = PathBuf::from(path);
            if repo::root(&path)? != repo_root {
                bail!("{} is not a worktree of {}", path.display(), repo_root.display());
            }
            (path, None)
        } else if let Some(target) = choice.strip_prefix("worker:") {
            // Where another Worker works, as a verifier does, without listing every Worker for it.
            let id = target
                .strip_prefix('w')
                .and_then(|n| n.parse::<i64>().ok())
                .with_context(|| format!("--worktree worker:<w id> needs a Worker id like w12, not {target:?}"))?;
            let other = db::worker(&self.db(), id).with_context(|| format!("--worktree worker:{target}"))?;
            if other.repo != repo_root.display().to_string() {
                bail!("{target} works in {}, not in {}", other.repo, repo_root.display());
            }
            let cwd = PathBuf::from(&other.cwd);
            if !cwd.is_dir() {
                bail!("{target}'s folder {} is gone", cwd.display());
            }
            (cwd, None)
        } else {
            bail!("--worktree must be current, new:<type>/<task>, path:<abs path>, or worker:<w id>");
        };
        // A worktree of its own gets the repo's ignored files now; its setup runs in its terminal.
        let prep = repo::prep(&repo_root)?;
        if cwd != repo_root {
            repo::copy_into(&repo_root, &cwd, &prep)?;
        }
        let session_id = uuid::Uuid::new_v4().to_string();
        let id = db::insert_worker(
            &self.db(),
            &db::NewWorker {
                repo: &repo_root.display().to_string(),
                profile: profile_name,
                title: &title,
                spec,
                cwd: &cwd.display().to_string(),
                branch: branch.as_deref(),
                session_id: &session_id,
                agent,
                fanout: p.get("fanout").and_then(Value::as_str),
                cli: runs.cli.as_deref(),
                model: runs.model.as_deref(),
            },
        )?;
        // Verifying by the daemon only happens while the human's Settings have a review on.
        let flag = |key: &str| p.get(key).and_then(Value::as_bool).unwrap_or(false);
        let review = settings::Rules::from(&settings::read(&paths::state_dir()).unwrap_or_default()).review;
        db::set_worker_role(
            &self.db(),
            id,
            flag("keep"),
            flag("verify") && review,
            p.get("verifies").and_then(Value::as_i64),
        )?;
        // Echo's fan-out is the human's Task; the daemon's verifier is Echo's; the rest, the Orchestrator's.
        let from = match p.get("origin").and_then(Value::as_str) {
            Some("human") => db::origin::HUMAN,
            Some("echo") => db::origin::ECHO,
            _ => db::origin::ORCHESTRATOR,
        };
        db::insert_task(&self.db(), id, from, spec)?;
        let worker = db::worker(&self.db(), id)?;
        if let Err(error) = self.launch(&worker, Launch::New { spec }) {
            db::settle(&self.db(), id, state::EXITED, &format!("could not start: {error:#}"))?;
            return Err(error);
        }
        self.notify();

        let sets_up = branch.is_some() && prep.setup.is_some();
        let started = self.wait_until(
            if sets_up { SETUP_TIMEOUT } else { START_TIMEOUT },
            || false,
            || {
                let now = db::worker(&self.db(), id)?;
                Ok((now.state != state::STARTING).then_some(now.state))
            },
        )?;
        let view = json!({ "id": format!("w{id}"), "cwd": cwd, "branch": branch, "session_id": session_id,
                           "title": title, "verify": worker.verify });
        match started.as_deref() {
            Some(state::EXITED) => {
                // Its terminal may be gone already; the exit message kept its last screen.
                let tail = match self.live(id) {
                    Ok(live) => screen::tail(&live.screen(), SCREEN_LINES),
                    Err(_) => db::last_message(&self.db(), id, kind::EXITED)?
                        .map(|m| m.body.split_once("Last screen:\n").map_or(m.body.clone(), |(_, t)| t.to_string()))
                        .unwrap_or_default(),
                };
                bail!("w{id} exited before starting its turn:\n{tail}")
            }
            Some(_) => Ok(view),
            None => bail!("w{id} never started its turn; read it with `echoctl worker read w{id}`, stop it with `echoctl worker close w{id}`"),
        }
    }

    fn resume_worker(self: &Arc<Self>, id: i64) -> Result<Value> {
        if self.live(id).is_ok() {
            bail!("w{id} is already live");
        }
        let worker = db::worker(&self.db(), id)?;
        if ![state::LOST, state::EXITED, state::ENDED].contains(&worker.state.as_str()) {
            bail!("w{id} is {}; only lost, exited, or ended Workers resume", worker.state);
        }
        let worker_cli = match &self.test_agent {
            Some(_) => cli::Cli::Claude,
            None => self.pick_for(&worker)?.1,
        };
        let (spec, message) = resume_message(&self.db(), id, worker_cli)?;
        db::set_state(&self.db(), id, state::STARTING)?;
        let worker = db::worker(&self.db(), id)?;
        // What the Worker is sent, so the chat can tell it from the human's words.
        db::insert_input(&self.db(), id, db::origin::ECHO, &message)?;
        self.launch(&worker, Launch::Resume { spec: &spec })?;
        self.notify();
        Ok(json!({ "id": format!("w{id}") }))
    }

    /// A settled Worker's next Task, in the same session and worktree: typed in at its input box, or
    /// its session resumed on it when its terminal is gone.
    fn next_task(self: &Arc<Self>, id: i64, spec: &str, from: &str) -> Result<Value> {
        let worker = db::worker(&self.db(), id)?;
        if state::is_live(&worker.state) {
            bail!("w{id} is still on its Task; give it the next one after its Final Report");
        }
        db::insert_task(&self.db(), id, from, spec)?;
        let started = match self.live(id) {
            Ok(live) => {
                self.hand_over(&live, &worker, spec)?;
                self.notify();
                Some(started(&live))
            }
            Err(_) => {
                db::set_state(&self.db(), id, state::STARTING)?;
                let worker = db::worker(&self.db(), id)?;
                self.launch(&worker, Launch::Next { spec })?;
                None
            }
        };
        self.notify();
        Ok(json!({ "id": format!("w{id}"), "started": started }))
    }

    /// Types work into a Worker at its input box; a settled one is running again, so its next
    /// `echoctl done` is taken.
    fn hand_over(&self, live: &Live, worker: &Worker, text: &str) -> Result<()> {
        refuse_over_dialog(live)?;
        // Running before the text goes in, so a report it sends at once is taken.
        *live.handed.lock().unwrap() = Some(Instant::now());
        if !state::is_live(&worker.state) {
            db::set_state(&self.db(), worker.id, state::RUNNING)?;
        }
        type_in(live, text)
    }

    /// The human's review of a Worker's changes: typed into the Worker when it is live and that is
    /// where it goes, else told to the Orchestrator, which decides what happens next.
    fn review_worker(&self, p: &Value) -> Result<Value> {
        let id = id_param(p, "id")?;
        let body = str_param(p, "body")?.trim();
        if body.is_empty() {
            bail!("a review needs at least one comment");
        }
        match str_param(p, "to")? {
            "worker" => {
                let live = self.live(id)?;
                let worker = db::worker(&self.db(), id)?;
                let review = format!("The human reviewed your changes. Address each comment:\n\n{body}");
                db::insert_input(&self.db(), id, db::origin::HUMAN, &review)?;
                self.hand_over(&live, &worker, &review)?;
                let db = self.db();
                let note = format!("The human sent w{id} a review of its changes in Echo:\n{body}");
                db::insert_message(&db, &worker, kind::HUMAN, &note)?;
            }
            "orchestrator" => {
                let db = self.db();
                let worker = db::worker(&db, id)?;
                let note = format!("The human reviewed w{id}'s changes in Echo and wants them addressed:\n{body}");
                db::insert_message(&db, &worker, kind::HUMAN, &note)?;
            }
            other => bail!("a review goes to worker or orchestrator, not {other}"),
        }
        self.notify();
        Ok(json!({}))
    }

    /// Starts `count` Workers on the same Task, each in its own worktree on `<branch>-<n>`, so the
    /// human can compare them and keep one.
    fn fan_out(self: &Arc<Self>, p: &Value) -> Result<Value> {
        let count = id_param(p, "count")?;
        if !(2..=5).contains(&count) {
            bail!("a fan-out is 2 to 5 Workers");
        }
        let branch = str_param(p, "branch")?;
        repo::parse_branch(branch)?;
        let fanout = uuid::Uuid::new_v4().to_string();
        let starts: Vec<_> = (1..=count)
            .map(|n| {
                let mut params = p.clone();
                params["worktree"] = json!(format!("new:{branch}-{n}"));
                params["fanout"] = json!(fanout);
                params["origin"] = json!("human");
                let hub = Arc::clone(self);
                std::thread::spawn(move || hub.start_worker(&params))
            })
            .collect();
        let mut started = Vec::new();
        let mut failed = Vec::new();
        for start in starts {
            match start.join().map_err(|_| anyhow::anyhow!("a start panicked"))? {
                Ok(view) => started.push(view["id"].clone()),
                Err(error) => failed.push(format!("{error:#}")),
            }
        }
        if started.is_empty() {
            bail!("no Worker started: {}", failed.join("; "));
        }
        started.sort_by_key(|id| id.as_str().and_then(|id| id[1..].parse::<i64>().ok()));
        Ok(json!({ "fanout": fanout, "workers": started, "failed": failed }))
    }

    /// Keeps one try of a fan-out: commits what it left uncommitted, merges its branch into the
    /// repo's checked-out branch, and closes the other tries and removes their worktrees (their
    /// branches stay). The Orchestrator is told.
    fn pick_worker(&self, id: i64) -> Result<Value> {
        let winner = db::worker(&self.db(), id)?;
        let fanout = winner
            .fanout
            .clone()
            .with_context(|| format!("w{id} is not part of a fan-out"))?;
        let branch = winner
            .branch
            .clone()
            .with_context(|| format!("w{id} has no branch to merge"))?;
        if state::is_live(&winner.state) {
            bail!("w{id} is still working; pick it once it sends its Final Report or stops");
        }
        let repo = PathBuf::from(&winner.repo);
        repo::commit_all(Path::new(&winner.cwd), &format!("{} (w{id})", winner.title))?;
        // Into the branch its Orchestrator works on.
        let into = repo::merge(&self.home_of(winner.agent_id, &winner.repo), &branch)?;
        let others: Vec<db::Worker> = db::workers(&self.db(), &winner.repo)?
            .into_iter()
            .filter(|w| w.id != id && w.fanout.as_deref() == Some(fanout.as_str()))
            .collect();
        for other in &others {
            self.close_worker(other.id)?;
            // Gone from Echo's Done list too: the kept try speaks for the Task.
            db::mark_dismissed(&self.db(), other.id)?;
            if other.branch.is_some() && Path::new(&other.cwd).exists() {
                repo::remove_worktree(&repo, Path::new(&other.cwd))?;
            }
        }
        let closed: Vec<String> = others.iter().map(|w| format!("w{}", w.id)).collect();
        let mut note = format!("The human picked w{id} of a fan-out in Echo and merged {branch} into {into}.");
        if !closed.is_empty() {
            note += &format!(
                " {} closed; their worktrees are removed, their branches kept.",
                closed.join(", ")
            );
        }
        db::insert_message(&self.db(), &winner, kind::HUMAN, &note)?;
        self.notify();
        Ok(json!({ "branch": branch, "into": into, "closed": closed }))
    }

    /// Where an agent works (`db::Agent::home`), or the repo's checkout without one.
    fn home_of(&self, agent: Option<i64>, repo: &str) -> PathBuf {
        agent
            .and_then(|id| db::agent(&self.db(), id).ok())
            .map(|a| PathBuf::from(a.home()))
            .unwrap_or_else(|| PathBuf::from(repo))
    }

    fn close_worker(&self, id: i64) -> Result<Value> {
        match self.live(id) {
            Ok(live) => {
                live.closing.store(true, std::sync::atomic::Ordering::SeqCst);
                live.kill();
            }
            Err(_) => {
                db::mark_closed(&self.db(), id)?;
                self.notify();
            }
        }
        Ok(json!({}))
    }

    fn on_exit(&self, id: i64) -> Result<()> {
        let Some(live) = self.live.lock().unwrap().remove(&id) else {
            return Ok(());
        };
        let closing = live.closing.load(std::sync::atomic::Ordering::SeqCst);
        let db = self.db();
        let worker = db::worker(&db, id)?;
        if state::is_live(&worker.state) {
            let screen = live.screen();
            let tail = screen::tail(&screen, SCREEN_LINES);
            // A Worker that finished its turn and then was closed or quit did its work; it only
            // skipped `echoctl done`. Its last screen is the report the human reads.
            let ended = worker.state == state::RUNNING && live.cli.turn_ended(&screen);
            let (final_state, verb) = if ended {
                (state::ENDED, "ended")
            } else {
                (state::EXITED, "exited")
            };
            let report = if ended {
                format!("Ended at its input box without a Final Report. Its last screen:\n\n```\n{tail}\n```")
            } else {
                "exited without a Final Report".to_string()
            };
            db::settle(&db, id, final_state, &report)?;
            if !closing {
                let body = format!("w{id} {verb} without a Final Report.\n\nLast screen:\n{tail}");
                db::insert_message(&db, &worker, kind::EXITED, &body)?;
            }
        }
        if closing {
            db::mark_closed(&db, id)?;
        }
        drop(db);
        self.notify();
        Ok(())
    }

    /// Reports a blocker once per stretch: cleared when the screen shows the Worker working again.
    /// Lock order everywhere: the database before a Worker's blocker, never the reverse.
    fn report_blocker(&self, live: &Live, blocker_kind: &str, message: &str) -> Result<()> {
        let worker = db::worker(&self.db(), live.id)?;
        if !state::is_live(&worker.state) {
            return Ok(()); // idle after the Final Report is the expected end state
        }
        {
            let mut current = live.blocker.lock().unwrap();
            if current.is_some() {
                return Ok(());
            }
            *current = Some(blocker_kind.to_string());
        }
        let screen = live.screen();
        let prompt = match blocker_kind {
            "permission_prompt" => live.cli.prompt_lines(&screen),
            _ => String::new(),
        };
        let body = blocker_body(blocker_kind, message, &prompt, &screen::tail(&screen, SCREEN_LINES));
        db::insert_message(&self.db(), &worker, kind::BLOCKER, &body)?;
        self.notify();
        Ok(())
    }

    /// Reads the Worker's screen every second: answers the trust dialog, notices the turn
    /// starting, and reports permission prompts and unexplained idling.
    fn watch(self: Arc<Self>, live: Arc<Live>) {
        let mut last_screen = String::new();
        let mut changed_at = Instant::now();
        let mut trusted_at: Option<Instant> = None;
        while live.is_alive() {
            std::thread::sleep(Duration::from_secs(1));
            let screen = live.screen();
            if screen != last_screen {
                last_screen = screen.clone();
                changed_at = Instant::now();
            }
            let look = live.cli.look(&screen);
            let waiting = look == Look::Waiting;
            if live.waiting.swap(waiting, std::sync::atomic::Ordering::SeqCst) != waiting {
                self.notify();
            }
            let Ok(worker) = db::worker(&self.db(), live.id) else {
                break;
            };
            let result = (|| -> Result<()> {
                match look {
                    Look::TrustPrompt => {
                        // The human approved this Task, so trusting its folder is part of starting it.
                        if trusted_at.is_none_or(|at| at.elapsed() > Duration::from_secs(5)) {
                            trusted_at = Some(Instant::now());
                            for key in live.cli.trust_keys() {
                                live.write(key)?;
                                std::thread::sleep(Duration::from_millis(300));
                            }
                        }
                    }
                    Look::PermissionPrompt => {
                        self.report_blocker(&live, "permission_prompt", "A permission prompt is waiting on screen.")?
                    }
                    Look::Working | Look::Waiting => {
                        if live.blocker.lock().unwrap().take().is_some() {
                            self.notify();
                        }
                    }
                    Look::Idle => {
                        // An answered or cancelled prompt ends that blocker; idling after it is a new one.
                        let mut blocker = live.blocker.lock().unwrap();
                        if blocker.as_deref() == Some("permission_prompt") {
                            blocker.take();
                            changed_at = Instant::now();
                            drop(blocker);
                            self.notify();
                        }
                    }
                }
                // A permission prompt also means a turn is under way.
                let started = matches!(look, Look::Working | Look::Waiting | Look::PermissionPrompt)
                    || live.cli.has_session(&worker.session_id);
                if worker.state == state::STARTING && started {
                    db::set_state(&self.db(), live.id, state::RUNNING)?;
                    self.notify();
                }
                let handed = live
                    .handed
                    .lock()
                    .unwrap()
                    .is_none_or(|at| at.elapsed() >= IDLE_BLOCKER);
                let idle =
                    look == Look::Idle && changed_at.elapsed() >= IDLE_BLOCKER && live.age() >= IDLE_BLOCKER && handed;
                if worker.state == state::RUNNING && idle && db::open_questions(&self.db(), live.id)?.is_empty() {
                    self.report_blocker(&live, "idle_prompt", "Idle at its input box with no Final Report.")?;
                }
                Ok(())
            })();
            if let Err(error) = result {
                eprintln!("hubd: watching w{}: {error:#}", live.id);
            }
        }
    }

    fn ask(&self, p: &Value, stream: &UnixStream) -> Result<Value> {
        let worker_id = id_param(p, "worker")?;
        let question = match p.get("question").and_then(Value::as_i64) {
            Some(id) => {
                let question = db::message(&self.db(), id)?;
                if question.worker_id != worker_id || question.kind != kind::QUESTION {
                    bail!("#{id} is not a question from w{worker_id}");
                }
                id
            }
            None => {
                let worker = db::worker(&self.db(), worker_id)?;
                let id = db::insert_message(&self.db(), &worker, kind::QUESTION, str_param(p, "body")?)?;
                self.notify();
                id
            }
        };
        let answer = self.wait_until(
            timeout_param(p, Duration::from_secs(540)),
            || peer_gone(stream),
            || Ok(db::message(&self.db(), question)?.answer),
        )?;
        Ok(json!({ "question": question, "answer": answer }))
    }

    /// Returns once a message that wakes the Orchestrator has waited `COALESCE` for others, with
    /// every message then waiting; a `status` alone never wakes it (features/0054).
    fn wait(&self, repo: &str, agent: Option<i64>, timeout: Duration, stream: &UnixStream) -> Result<Value> {
        let hold = std::env::var("HUB_COALESCE_MS")
            .ok()
            .and_then(|ms| ms.parse().ok())
            .map_or(COALESCE, Duration::from_millis);
        let mut woken_at: Option<Instant> = None;
        let mut messages = self.wait_until(
            timeout,
            || peer_gone(stream),
            || {
                if peer_gone(stream) {
                    return Ok(None); // never hand messages to a listener that hung up
                }
                if !db::has_waking(&self.db(), repo, agent)? {
                    woken_at = None;
                    return Ok(None);
                }
                if woken_at.get_or_insert_with(Instant::now).elapsed() < hold {
                    return Ok(None);
                }
                Ok(Some(db::take_undelivered(&self.db(), repo, agent)?))
            },
        )?;
        // Time ran out during the hold: what woke it is still owed.
        if messages.is_none() && !peer_gone(stream) && db::has_waking(&self.db(), repo, agent)? {
            messages = Some(db::take_undelivered(&self.db(), repo, agent)?);
        }
        let db = self.db();
        let mut out = Vec::new();
        let mut to_close = Vec::new();
        for message in messages.unwrap_or_default() {
            let worker = db::worker(&db, message.worker_id)?;
            // Its Final Report reached the Orchestrator: a Worker with no branch of its own and
            // not asked to stay is done for good (features/0056).
            if message.kind == kind::DONE
                && worker.branch.is_none()
                && !worker.keep
                && !state::is_live(&worker.state)
                && worker.closed_at.is_none()
            {
                to_close.push(worker.id);
            }
            out.push(json!({
                "id": message.id,
                "kind": message.kind,
                "worker": format!("w{}", worker.id),
                "profile": worker.profile,
                "title": worker.title,
                "state": worker.state,
                "branch": worker.branch,
                "body": message.body,
                "closed": to_close.contains(&worker.id),
            }));
        }
        drop(db);
        for id in to_close {
            self.close_worker(id)?;
        }
        Ok(json!({ "messages": out }))
    }

    /// A writer started `--verify` reported done: a `sasuke` checks it in the same worktree before
    /// the Orchestrator hears of it.
    fn verify(self: &Arc<Self>, writer: i64) {
        if let Err(error) = self.start_verifier(writer) {
            self.deliver(writer, &format!("Verification did not start: {error:#}"), "");
        }
    }

    fn start_verifier(self: &Arc<Self>, writer_id: i64) -> Result<()> {
        let (writer, task) = {
            let db = self.db();
            (db::worker(&db, writer_id)?, db::worker_spec(&db, writer_id)?)
        };
        let spec = format!(
            "Verify the work of w{writer_id} ({}: {}) in this worktree.\n\n\
             Begin your Final Report with one line, `Verdict: pass` or `Verdict: fail`, then your findings.\n\n\
             The Task it was given:\n\n{}\n\nIts Final Report:\n\n{}\n",
            writer.profile,
            writer.title,
            task.trim_end(),
            writer.final_report.as_deref().unwrap_or("").trim_end()
        );
        self.start_worker(&json!({
            "repo": writer.repo,
            "profile": "sasuke",
            "spec": spec,
            "worktree": format!("worker:w{writer_id}"),
            "agent": writer.agent_id,
            "title": format!("verify w{writer_id}: {}", writer.title),
            "verifies": writer_id,
            "origin": "echo",
        }))?;
        Ok(())
    }

    /// The verifier's report is in: a pass, a failure the writer gets one retry for, or anything
    /// else, which the Orchestrator decides. Only then does the Orchestrator hear of the writer.
    fn verified(self: &Arc<Self>, verifier: i64, writer_id: i64, final_state: &str, report: &str) {
        let outcome = (|| -> Result<()> {
            let writer = db::worker(&self.db(), writer_id)?;
            let verdict = if final_state == state::DONE {
                verdict(report)
            } else {
                None
            };
            match verdict {
                Some(true) => self.deliver(writer_id, &format!("Verified by w{verifier}: pass."), report),
                Some(false) if writer.retries < MAX_RETRIES => {
                    db::add_retry(&self.db(), writer_id)?;
                    let task = format!(
                        "w{verifier} (sasuke) verified your change and it failed. Fix every P0 and P1 finding \
                         within this Task and its scope, run the verify command again, and finish with \
                         `echoctl done` as before.\n\n{}",
                        report.trim_end()
                    );
                    if let Err(error) = self.next_task(writer_id, &task, db::origin::ECHO) {
                        let note = format!(
                            "Verification by w{verifier} failed and w{writer_id} could not take the retry: {error:#}"
                        );
                        self.deliver(writer_id, &note, report);
                    }
                }
                Some(false) => {
                    let note =
                        format!("Verification by w{verifier} failed again after {MAX_RETRIES} retry: needs the human.");
                    self.deliver(writer_id, &note, report)
                }
                None => {
                    let note = format!(
                        "w{verifier} ended {final_state} without a `Verdict:` line: judge its report yourself."
                    );
                    self.deliver(writer_id, &note, report)
                }
            }
            Ok(())
        })();
        if let Err(error) = outcome {
            eprintln!("hubd: verifying w{writer_id}: {error:#}");
        }
        if let Err(error) = self.close_worker(verifier) {
            eprintln!("hubd: closing w{verifier}: {error:#}");
        }
    }

    /// The one message the Orchestrator gets for a verified writer: its Final Report and how the
    /// verification ended.
    fn deliver(&self, writer_id: i64, outcome: &str, verifier_report: &str) {
        let result = (|| -> Result<()> {
            let db = self.db();
            let writer = db::worker(&db, writer_id)?;
            let mut body = format!(
                "{}\n\n{outcome}",
                writer.final_report.as_deref().unwrap_or("").trim_end()
            );
            if !verifier_report.trim().is_empty() {
                body += &format!("\n\nVerifier's report:\n{}", verifier_report.trim_end());
            }
            db::insert_message(&db, &writer, kind::DONE, &body)?;
            Ok(())
        })();
        if let Err(error) = result {
            eprintln!("hubd: delivering w{writer_id}: {error:#}");
        }
        self.notify();
    }

    fn view(&self, db: &Connection, worker: &Worker) -> Result<Value> {
        let open: Vec<i64> = db::open_questions(db, worker.id)?.iter().map(|m| m.id).collect();
        let blocker = self
            .live(worker.id)
            .ok()
            .and_then(|live| live.blocker.lock().unwrap().clone());
        Ok(json!({
            "id": format!("w{}", worker.id),
            "profile": worker.profile,
            "title": worker.title,
            "state": worker.state,
            "live": self.live(worker.id).is_ok(),
            "open_questions": open,
            "blocker": blocker,
            "cwd": worker.cwd,
            "branch": worker.branch,
            "session_id": worker.session_id,
            "final_report": worker.final_report,
            "quiet_seconds": db::now() - worker.last_message_at.unwrap_or(worker.created_at),
        }))
    }

    /// The repo's open Workers; with an `agent`, only the ones that Orchestrator started.
    fn list_workers(&self, repo: &str, agent: Option<i64>) -> Result<Value> {
        let db = self.db();
        let mut out = Vec::new();
        for worker in db::workers(&db, repo)? {
            if worker.closed_at.is_none() && agent.is_none_or(|agent| worker.agent_id == Some(agent)) {
                out.push(self.view(&db, &worker)?);
            }
        }
        Ok(json!({ "workers": out }))
    }

    /// The Dashboard rows: live Workers, and settled ones for a while after.
    fn status(&self, repo: &str) -> Result<Value> {
        Ok(json!({ "workers": self.rows(repo, false)? }))
    }

    /// One row per recent Worker, ordered needs you, running or waiting, failed, then done or
    /// ended. `state` is the
    /// Dashboard state; `phase` is the Worker's lifecycle state. For Echo (`for_echo`), settled
    /// Workers stay until dismissed or five minutes old (a week when blocked or lost); the
    /// Orchestrator's `echoctl status` drops them after ten minutes.
    fn rows(&self, repo: &str, for_echo: bool) -> Result<Vec<Value>> {
        let db = self.db();
        let now = db::now();
        let mut rows = Vec::new();
        for worker in db::workers(&db, repo)? {
            let recent = match worker.settled_at {
                None => true,
                Some(at) if for_echo => {
                    let needs_human = matches!(worker.state.as_str(), state::BLOCKED | state::LOST);
                    let keep = if needs_human {
                        KEEP_NEEDS_SECONDS
                    } else {
                        KEEP_REPORTS_SECONDS
                    };
                    worker.dismissed_at.is_none() && now - at < keep
                }
                Some(at) => now - at < KEEP_SETTLED_SECONDS,
            };
            if !recent {
                continue;
            }
            let live = self.live(worker.id).ok();
            let blocker = live.as_ref().and_then(|live| live.blocker.lock().unwrap().clone());
            let open: Vec<i64> = db::open_questions(&db, worker.id)?.iter().map(|m| m.id).collect();
            let profile = profile::load(
                &self.hub_dir,
                &paths::state_dir(),
                Some(Path::new(&worker.repo)),
                &worker.profile,
            )
            .ok();
            // The CLI and model it runs with, as `spawn_for` picks them: `forceCli` puts the Profile's
            // own aside. Its effort is the Profile's, which the CLI gets whatever the force.
            let choice = cli::Choice {
                cli: worker.cli.clone(),
                model: worker.model.clone(),
            };
            let own = profile.as_ref().map(|profile| profile.choice());
            let picked = cli::pick(
                &paths::state_dir(),
                Some(Path::new(&worker.repo)),
                own.as_ref(),
                &[&choice],
            );
            let (worker_cli, model) = match picked {
                Ok(picked) => picked,
                Err(_) => (
                    cli::Cli::Claude,
                    worker
                        .model
                        .clone()
                        .or_else(|| profile.as_ref().and_then(|p| p.model.clone())),
                ),
            };
            // The Worker's latest `echoctl send --type status`, first line only: the ledger's progress line.
            let progress = db::last_message(&db, worker.id, kind::STATUS)?
                .and_then(|m| m.body.lines().map(str::trim).find(|l| !l.is_empty()).map(String::from));
            let row_state = match worker.state.as_str() {
                state::DONE => "done",
                state::ENDED => "ended",
                state::BLOCKED | state::LOST => "needs you",
                state::EXITED => "failed",
                _ if blocker.is_some() || !open.is_empty() => "needs you",
                _ if live
                    .as_ref()
                    .is_some_and(|l| l.waiting.load(std::sync::atomic::Ordering::SeqCst)) =>
                {
                    "waiting"
                }
                _ => "running",
            };
            let quiet_since = worker.last_message_at.unwrap_or(worker.created_at);
            let mut row = json!({
                "id": format!("w{}", worker.id),
                "profile": worker.profile,
                "title": worker.title,
                "state": row_state,
                "phase": worker.state,
                "place": place(Path::new(repo), Path::new(&worker.cwd)),
                "branch": worker.branch,
                // Where it works, for Echo's Files column.
                "cwd": worker.cwd,
                "live": live.is_some(),
                "blocker": blocker,
                "openQuestions": open,
                "finalReport": worker.final_report,
                "agent": worker.agent_id,
                // The model it runs, as the human reads it: "claude-haiku-5-5", not "anthropic/claude-haiku-5-5".
                "model": model.map(|m| m.rsplit('/').next().unwrap_or(&m).to_string()),
                "effort": profile.as_ref().and_then(|p| p.effort.clone()),
                "progress": progress,
                "settledAt": worker.settled_at,
                "fanout": worker.fanout,
            });
            // Only a CLI other than claude is named, so a Claude Worker's row is what it always was.
            if worker_cli != cli::Cli::Claude {
                row["cli"] = json!(worker_cli.name());
            }
            // Echo counts the quiet time up itself, so an unchanged repo sends an unchanged snapshot.
            if for_echo {
                row["quietSince"] = json!(quiet_since);
            } else {
                row["quietSeconds"] = json!((now - quiet_since).max(0));
            }
            rows.push((quiet_since, row));
        }
        let order = |row: &Value| match row["state"].as_str() {
            Some("needs you") => 0,
            Some("running" | "waiting") => 1,
            Some("failed") => 2,
            _ => 3,
        };
        rows.sort_by_key(|(quiet_since, row)| (order(row), std::cmp::Reverse(*quiet_since)));
        Ok(rows.into_iter().map(|(_, row)| row).collect())
    }

    /// What needs the human now: open questions and waiting permission prompts, oldest first.
    fn needs(&self, repo: &str) -> Result<Vec<Value>> {
        let db = self.db();
        let mut needs = Vec::new();
        for worker in db::workers(&db, repo)? {
            for question in db::open_questions(&db, worker.id)? {
                needs.push(json!({
                    "kind": "question",
                    "message": question.id,
                    "agent": worker.agent_id,
                    "worker": format!("w{}", worker.id),
                    "profile": worker.profile,
                    "title": worker.title,
                    "body": question.body,
                    "at": question.created_at,
                }));
            }
            let Ok(live) = self.live(worker.id) else { continue };
            let blocker = live.blocker.lock().unwrap().clone();
            if let (Some(blocker), Some(message)) = (blocker, db::last_message(&db, worker.id, kind::BLOCKER)?) {
                // The prompt's own lines, so the Hub App can show the exact command, not the whole screen.
                let prompt = match blocker.as_str() {
                    "permission_prompt" => live.cli.prompt_lines(&live.screen()),
                    _ => String::new(),
                };
                needs.push(json!({
                    "kind": blocker,
                    "message": message.id,
                    "agent": worker.agent_id,
                    "worker": format!("w{}", worker.id),
                    "profile": worker.profile,
                    "title": worker.title,
                    "body": message.body,
                    "prompt": prompt,
                    "at": message.created_at,
                }));
            }
        }
        drop(db);
        // An Orchestrator's or Normal session's own permission prompt: there is no one to tell but
        // the human, who may be looking at another agent or away from Echo.
        for agent in db::agents(&self.db(), Some(repo))? {
            let Some(at) = self.agent_prompts.lock().unwrap().get(&agent.id).copied() else {
                continue;
            };
            let Ok(live) = self.agent_live(agent.id) else { continue };
            needs.push(json!({
                "kind": "permission_prompt",
                "message": 0,
                "agent": agent.id,
                "worker": null,
                "profile": if agent.kind == db::agent_kind::ORCHESTRATOR { "orchestrator" } else { "claude" },
                "title": agent.name.clone().unwrap_or_else(|| {
                    if agent.kind == db::agent_kind::ORCHESTRATOR { "Orchestrator" } else { "Claude Code" }.into()
                }),
                "body": "A permission prompt is waiting on screen.",
                "prompt": live.cli.prompt_lines(&live.screen()),
                "at": at,
            }));
        }
        needs.sort_by_key(|need| need["at"].as_i64().unwrap_or(0));
        Ok(needs)
    }

    /// Everything the app draws for one repo: its agents, their Workers, and what needs the human.
    fn snapshot(&self, repo: &str) -> Result<Value> {
        // Read before the json! below: its other parts take the database lock themselves.
        let agents = db::agents(&self.db(), Some(repo))?;
        let first = agents.iter().find(|a| a.kind == db::agent_kind::ORCHESTRATOR);
        Ok(json!({
            "repo": repo,
            "orchestrator": {
                "live": first.is_some_and(|a| self.agent_is_live(a.id)),
                "model": first.and_then(|a| a.model.clone()),
            },
            "agents": agents.iter().map(|a| self.agent_view(a)).collect::<Vec<_>>(),
            "workers": self.rows(repo, true)?,
            "needs": self.needs(repo)?,
            "usage": self.usage.lock().unwrap().view(),
            "ui": self.ui_requests(repo),
        }))
    }

    /// This repo's requests from `echoctl ui` that are still fresh.
    fn ui_requests(&self, repo: &str) -> Vec<Value> {
        let fresh = db::now() - UI_KEEP;
        let ui = self.ui.lock().unwrap();
        ui.iter()
            .filter(|r| r["repo"] == repo && r["at"].as_i64().is_some_and(|at| at > fresh))
            .cloned()
            .collect()
    }

    /// `echoctl ui`: an agent asks Echo to open a file, show a Worker or agent or a Worker's diff,
    /// post a notification, or start an Orchestrator and show it. Echo acts on it from the
    /// snapshot and never comes to the front for it (features/0033).
    fn ui(self: &Arc<Self>, p: &Value) -> Result<Value> {
        let action = str_param(p, "action")?;
        let mut request = json!({
            "id": uuid::Uuid::new_v4().to_string(),
            "at": db::now(),
            "action": action,
            "from": p.get("from").cloned().unwrap_or(Value::Null),
        });
        let mut result = json!({});
        let repo = match action {
            "open" => {
                let path = Path::new(str_param(p, "path")?);
                let path = path
                    .canonicalize()
                    .with_context(|| format!("{} does not exist", path.display()))?;
                if !path.is_file() {
                    bail!("{} is not a file", path.display());
                }
                let dir = path.parent().context("a file is in a folder")?;
                let root = repo::toplevel(dir)?;
                let root = root.canonicalize().unwrap_or(root);
                let relative = path.strip_prefix(&root).context("the file is outside its checkout")?;
                request["root"] = json!(root.display().to_string());
                request["path"] = json!(relative.display().to_string());
                request["line"] = p.get("line").cloned().unwrap_or(Value::Null);
                repo::root(dir)?.display().to_string()
            }
            "show" | "diff" => {
                let repo = repo::root(Path::new(str_param(p, "repo")?))?.display().to_string();
                let target = str_param(p, "target")?;
                if let Some(id) = target.strip_prefix('a').and_then(|id| id.parse::<i64>().ok()) {
                    if action == "diff" {
                        bail!("only a Worker has a diff to show; {target} is an agent");
                    }
                    if !db::agents(&self.db(), Some(&repo))?.iter().any(|a| a.id == id) {
                        bail!("no agent {target} in this repo");
                    }
                    request["agent"] = json!(id);
                } else {
                    let id: i64 = target
                        .trim_start_matches(['w', '#'])
                        .parse()
                        .with_context(|| format!("{target:?} is not a Worker like w12 or an agent like a3"))?;
                    if db::worker(&self.db(), id).map_or(true, |w| w.repo != repo) {
                        bail!("no Worker w{id} in this repo");
                    }
                    request["worker"] = json!(format!("w{id}"));
                }
                repo
            }
            "settings" => {
                const SECTIONS: &[&str] = &[
                    "window",
                    "theme",
                    "background",
                    "font",
                    "multiplexer",
                    "agents",
                    "worktrees",
                    "memory",
                    "remote",
                ];
                let section = p.get("section").and_then(Value::as_str).unwrap_or("agents");
                if !SECTIONS.contains(&section) {
                    bail!("no Settings section {section:?}; there are {}", SECTIONS.join(", "));
                }
                request["text"] = json!(section);
                repo::root(Path::new(str_param(p, "repo")?))?.display().to_string()
            }
            "notify" => {
                let text = str_param(p, "text")?.trim();
                if text.is_empty() {
                    bail!("a notification needs some text");
                }
                request["text"] = json!(text);
                repo::root(Path::new(str_param(p, "repo")?))?.display().to_string()
            }
            "orchestrator" => {
                let repo = repo::root(Path::new(str_param(p, "repo")?))?.display().to_string();
                let mut open = json!({ "repo": repo, "kind": db::agent_kind::ORCHESTRATOR });
                for key in ["branch", "new_branch", "base", "name", "request", "team"] {
                    if let Some(value) = p.get(key).filter(|v| !v.is_null()) {
                        open[key] = value.clone();
                    }
                }
                result = self.open_agent(&open)?;
                request["action"] = json!("show");
                request["agent"] = result["agent"].clone();
                // It runs whether or not Echo is open; Echo just shows it when it is.
                if !self.watched(&repo) {
                    return Ok(result);
                }
                repo
            }
            other => bail!("unknown ui action {other:?}"),
        };
        if !self.watched(&repo) {
            let name = Path::new(&repo)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or(repo);
            bail!("Echo is not open on {name}, so there is nothing to show this in");
        }
        request["repo"] = json!(repo);
        {
            let fresh = db::now() - UI_KEEP;
            let mut ui = self.ui.lock().unwrap();
            ui.retain(|r| r["at"].as_i64().is_some_and(|at| at > fresh));
            ui.push(request);
        }
        self.notify();
        Ok(result)
    }

    fn watched(&self, repo: &str) -> bool {
        self.watchers.lock().unwrap().get(repo).is_some_and(|count| *count > 0)
    }

    fn refresh_usage(self: &Arc<Self>) {
        {
            let mut usage = self.usage.lock().unwrap();
            if usage.refreshing {
                return;
            }
            usage.refreshing = true;
            usage.refreshed = Some(Instant::now());
        }
        let program = self.test_agent.clone().unwrap_or_else(|| "claude".into());
        let hub = Arc::clone(self);
        std::thread::spawn(move || {
            let mut result = Ok(Vec::new());
            for attempt in 0..USAGE_ATTEMPTS {
                if attempt > 0 {
                    std::thread::sleep(Duration::from_secs(3));
                }
                result = run_usage(&program);
                if result.as_ref().is_ok_and(|limits| !limits.is_empty()) {
                    break;
                }
            }
            let mut usage = hub.usage.lock().unwrap();
            usage.refreshing = false;
            match result {
                Ok(limits) if !limits.is_empty() => {
                    usage.limits = limits;
                    usage.updated_at = Some(db::now());
                    usage.error = None;
                }
                // Keep the last good limits on screen; try again sooner than usual.
                failed => {
                    usage.error = Some(match failed {
                        Err(error) => format!("{error:#}"),
                        Ok(_) => "`claude -p /usage` printed no plan limits".into(),
                    });
                    usage.refreshed = Instant::now().checked_sub(USAGE_EVERY - USAGE_RETRY);
                }
            }
            drop(usage);
            hub.notify();
        });
    }

    /// Reads Kiro's credits on a thread of their own, on the same cadence and retry rules as Claude's.
    /// Nothing happens when there is no `kiro-cli` to ask.
    fn refresh_kiro_usage(self: &Arc<Self>) {
        let Some(program) = self.kiro_usage.clone() else {
            return;
        };
        {
            let mut usage = self.usage.lock().unwrap();
            if usage.kiro_refreshing {
                return;
            }
            usage.kiro_refreshing = true;
            usage.kiro_refreshed = Some(Instant::now());
        }
        let hub = Arc::clone(self);
        std::thread::spawn(move || {
            let parent = paths::state_dir();
            let mut outcome = kiro_usage::Outcome::Failed("not tried".into());
            for attempt in 0..USAGE_ATTEMPTS {
                if attempt > 0 {
                    std::thread::sleep(Duration::from_secs(3));
                }
                outcome = kiro_usage::read(&program, &parent);
                if !matches!(outcome, kiro_usage::Outcome::Failed(_)) {
                    break;
                }
            }
            hub.usage.lock().unwrap().finish_kiro(outcome);
            hub.notify();
        });
    }

    /// Streams a snapshot line now, after every change, and every 5 seconds, until the client leaves.
    fn events(self: &Arc<Self>, p: &Value, mut stream: UnixStream) -> Result<()> {
        let repo = match str_param(p, "repo").and_then(|repo| repo::root(Path::new(repo))) {
            Ok(repo) => repo.display().to_string(),
            Err(error) => return proto::write_line(&mut stream, &proto::err(&error)),
        };
        proto::write_line(&mut stream, &proto::ok(json!({ "repo": repo })))?;
        *self.watchers.lock().unwrap().entry(repo.clone()).or_default() += 1;
        let _watching = Watching { hub: self, repo: &repo };
        let mut last = None;
        loop {
            let (stale, kiro_stale) = {
                let usage = self.usage.lock().unwrap();
                (
                    usage.refreshed.is_none_or(|at| at.elapsed() >= USAGE_EVERY),
                    usage.kiro_refreshed.is_none_or(|at| at.elapsed() >= USAGE_EVERY),
                )
            };
            if stale {
                self.refresh_usage();
            }
            if kiro_stale {
                self.refresh_kiro_usage();
            }
            let seen = *self.tick.lock().unwrap();
            let snapshot = self.snapshot(&repo)?;
            // Each line redraws Echo's window, so an unchanged snapshot is not sent again.
            if last.as_ref() != Some(&snapshot) {
                if proto::write_line(&mut stream, &snapshot).is_err() {
                    return Ok(());
                }
                last = Some(snapshot);
            }
            let deadline = Instant::now() + Duration::from_secs(5);
            loop {
                let guard = self.tick.lock().unwrap();
                let now = Instant::now();
                if *guard != seen || now >= deadline {
                    break;
                }
                let _ = self.changed.wait_timeout(guard, deadline - now);
            }
            if peer_gone(&stream) {
                return Ok(());
            }
        }
    }

    /// The human's answer to a waiting permission prompt, from the Hub App: press the key on the
    /// Worker, then tell the Orchestrator, so it never has to be typed to.
    fn decide(&self, p: &Value) -> Result<Value> {
        let approve = param(p, "approve")?
            .as_bool()
            .context("approve must be true or false")?;
        if let Some(agent) = p.get("agent").and_then(Value::as_i64) {
            return self.decide_agent(agent, approve, p.get("note").and_then(Value::as_str));
        }
        let id = id_param(p, "worker")?;
        let live = self.live(id)?;
        let screen = live.screen();
        if live.cli.look(&screen) != Look::PermissionPrompt {
            bail!("no permission prompt is waiting on w{id}");
        }
        let prompt = live.cli.prompt_lines(&screen);
        if approve {
            press(&live, live.cli.approve_keys())?;
        } else {
            press(&live, live.cli.deny_keys())?;
            std::thread::sleep(Duration::from_millis(500));
            let note = p
                .get("note")
                .and_then(Value::as_str)
                .filter(|note| !note.trim().is_empty())
                .unwrap_or(
                    "Do not run it. Continue another way within your Task, or finish blocked with echoctl done.",
                );
            live.write(format!("The human denied that command. {note}").as_bytes())?;
            std::thread::sleep(Duration::from_millis(150));
            live.write(b"\r")?;
        }
        let db = self.db();
        let worker = db::worker(&db, id)?;
        let verb = if approve { "approved" } else { "denied" };
        let body = format!("The human {verb} this permission prompt on w{id} in the Hub App:\n{prompt}");
        db::insert_message(&db, &worker, kind::HUMAN, &body)?;
        drop(db);
        self.notify();
        Ok(json!({}))
    }

    /// Approve or Deny on an Orchestrator's or Normal session's own prompt: press the key; the human
    /// is the only one to tell.
    fn decide_agent(&self, id: i64, approve: bool, note: Option<&str>) -> Result<Value> {
        let live = self.agent_live(id)?;
        if live.cli.look(&live.screen()) != Look::PermissionPrompt {
            bail!("no permission prompt is waiting on agent {id}");
        }
        if approve {
            press(&live, live.cli.approve_keys())?;
        } else {
            press(&live, live.cli.deny_keys())?;
            if let Some(note) = note.map(str::trim).filter(|n| !n.is_empty()) {
                std::thread::sleep(Duration::from_millis(500));
                live.write(note.as_bytes())?;
                std::thread::sleep(Duration::from_millis(150));
                live.write(b"\r")?;
            }
        }
        self.agent_prompts.lock().unwrap().remove(&id);
        self.notify();
        Ok(json!({}))
    }

    /// Watches an Orchestrator's or Normal session's screen for permission prompts, so they reach
    /// Needs you.
    fn watch_agent(self: Arc<Self>, live: Arc<Live>) {
        let orchestrator = db::agent(&self.db(), live.id).is_ok_and(|a| a.kind == db::agent_kind::ORCHESTRATOR);
        let mut quiet = Quiet::default();
        while live.is_alive() {
            std::thread::sleep(Duration::from_secs(1));
            let screen = live.screen();
            if orchestrator && quiet.settled(live.cli.look(&screen), &screen, Instant::now()) {
                match self.renew_if_due(live.id) {
                    Ok(true) => return,
                    Ok(false) => {}
                    Err(error) => eprintln!("hubd: renewing a{}: {error:#}", live.id),
                }
            }
            let waiting = live.cli.look(&screen) == Look::PermissionPrompt;
            let mut prompts = self.agent_prompts.lock().unwrap();
            let changed = if waiting {
                // Keep the time it was first seen.
                !prompts.contains_key(&live.id) && prompts.insert(live.id, db::now()).is_none()
            } else {
                prompts.remove(&live.id).is_some()
            };
            drop(prompts);
            if changed {
                self.notify();
            }
        }
    }

    fn attach(self: &Arc<Self>, p: &Value, mut reader: BufReader<UnixStream>, mut stream: UnixStream) -> Result<()> {
        let live = match self.terminal(p) {
            Ok(live) => live,
            Err(error) => return proto::write_line(&mut stream, &proto::err(&error)),
        };
        if let (Some(rows), Some(cols)) = (
            p.get("rows").and_then(Value::as_u64),
            p.get("cols").and_then(Value::as_u64),
        ) {
            live.resize(rows as u16, cols as u16)?;
        }
        proto::write_line(&mut stream, &proto::ok(json!({})))?;
        let (snapshot, chunks) = live.subscribe();
        let mut out = stream.try_clone()?;
        out.write_all(b"\x1b[H\x1b[2J")?;
        out.write_all(&snapshot)?;
        out.flush()?;
        // Set once the client leaves, so the writer stops waiting on a quiet terminal's output.
        let detached = Arc::new(AtomicBool::new(false));
        let gone = Arc::clone(&detached);
        std::thread::spawn(move || {
            loop {
                match chunks.recv_timeout(Duration::from_secs(1)) {
                    Ok(chunk) => {
                        if out.write_all(&chunk).and_then(|_| out.flush()).is_err() {
                            break;
                        }
                    }
                    Err(RecvTimeoutError::Timeout) if !gone.load(Ordering::SeqCst) => {}
                    Err(_) => break,
                }
            }
            let _ = out.shutdown(std::net::Shutdown::Both);
        });
        // An unnamed agent takes its name from the first line the human types into it, not into
        // its shell.
        let mut naming = match p.get("agent").and_then(Value::as_i64) {
            Some(id) if self.agent_is_live(id) && db::agent(&self.db(), id).is_ok_and(|a| a.name.is_none()) => {
                Some((id, LineReader::default()))
            }
            _ => None,
        };
        let mut buf = [0u8; 4096];
        loop {
            match reader.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    live.write(&buf[..n])?;
                    if let Some((id, line)) = &mut naming {
                        let id = *id;
                        for typed in line.feed(&buf[..n]) {
                            if self.name_from_input(id, &typed).unwrap_or(true) {
                                naming = None;
                                break;
                            }
                        }
                    }
                }
            }
        }
        detached.store(true, Ordering::SeqCst);
        let _ = stream.shutdown(std::net::Shutdown::Both);
        Ok(())
    }
}

/// Session markers a Worker must not inherit from whatever agent started the daemon: Claude Code
/// reads `CLAUDE_CODE_CHILD_SESSION`, for one, as "do not save transcripts", which breaks resume.
/// Collects what the human types into a terminal, a line at a time, without escape sequences.
#[derive(Default)]
struct LineReader {
    line: Vec<u8>,
    escape: bool,
}

impl LineReader {
    /// Feeds typed bytes; returns every non-empty line Enter finished.
    fn feed(&mut self, bytes: &[u8]) -> Vec<String> {
        let mut done = Vec::new();
        for &b in bytes {
            if self.escape {
                // CSI and friends end on a letter or `~`.
                if b.is_ascii_alphabetic() || b == b'~' {
                    self.escape = false;
                }
                continue;
            }
            match b {
                0x1b => self.escape = true,
                b'\r' | b'\n' => {
                    let line = String::from_utf8_lossy(&self.line).trim().to_string();
                    self.line.clear();
                    if !line.is_empty() {
                        done.push(line);
                    }
                }
                0x7f | 0x08 => {
                    // Drop the last character, all of its UTF-8 bytes.
                    while let Some(last) = self.line.pop() {
                        if last & 0xC0 != 0x80 {
                            break;
                        }
                    }
                }
                0x15 => self.line.clear(),
                b if b >= 0x20 => self.line.push(b),
                _ => {}
            }
        }
        done
    }
}

/// A short name from the human's first request: its first words, without a slash command.
pub fn name_from_request(line: &str) -> Option<String> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('/') || line.starts_with('!') {
        return None;
    }
    let mut name = String::new();
    for word in line.split_whitespace().take(6) {
        if name.chars().count() + word.chars().count() + 1 > 48 {
            break;
        }
        if !name.is_empty() {
            name.push(' ');
        }
        name.push_str(word);
    }
    let name = name.trim_end_matches(|c: char| ",.;:!?".contains(c)).to_string();
    let mut chars = name.chars();
    let first = chars.next()?;
    Some(first.to_uppercase().chain(chars).collect())
}

/// The human's shell: `HUB_SHELL`, else `$SHELL`, else zsh.
pub fn user_shell() -> String {
    std::env::var("HUB_SHELL")
        .or_else(|_| std::env::var("SHELL"))
        .unwrap_or_else(|_| "/bin/zsh".into())
}

/// A multiplexer session name for a target, e.g. `echo-lanh-a3`: letters, digits, `-` and `_`
/// only, since tmux treats `.` and `:` as separators.
fn mux_session(repo_name: &str, label: &str) -> String {
    let clean: String = repo_name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '-'
            }
        })
        .collect();
    format!("echo-{}-{label}", clean.trim_matches('-'))
}

/// `word` as one POSIX shell word.
fn shell_quote(word: &str) -> String {
    if !word.is_empty()
        && word
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "-_./=:@%+,".contains(c))
    {
        return word.to_string();
    }
    format!("'{}'", word.replace('\'', "'\\''"))
}

/// The human's shell, as the daemon inherited it.
fn login_shell() -> String {
    std::env::var("SHELL")
        .ok()
        .filter(|shell| !shell.is_empty())
        .unwrap_or_else(|| "/bin/zsh".into())
}

/// The daemon's environment as a shell in Echo's terminal should get it: the human's own, since
/// the daemon starts from a login shell, less what names an agent or the terminal that started the
/// daemon. A multiplexer pane runs with it rather than starting a login shell (features/0047).
pub fn shell_env() -> std::collections::BTreeMap<String, String> {
    std::env::vars()
        .filter(|(key, _)| {
            !is_agent_var(key)
                && !matches!(
                    key.as_str(),
                    "TERM" | "COLORTERM" | "TERMINFO" | "TERM_PROGRAM" | "TERM_PROGRAM_VERSION" | "TERM_SESSION_ID"
                )
        })
        .collect()
}

pub fn inherited_agent_vars() -> Vec<String> {
    std::env::vars()
        .map(|(key, _)| key)
        .filter(|key| is_agent_var(key))
        .collect()
}

/// A Task that ends with another Worker's Final Report, verbatim.
fn spec_with_report(spec: &str, source: &Worker) -> Result<String> {
    let Some(report) = source.final_report.as_deref().filter(|r| !r.trim().is_empty()) else {
        bail!("w{} has no Final Report yet", source.id);
    };
    let head = if spec.trim().is_empty() {
        String::new()
    } else {
        format!("{}\n\n", spec.trim_end())
    };
    Ok(format!(
        "{head}Final Report of w{} ({}: {}), verbatim:\n\n{}",
        source.id,
        source.profile,
        source.title,
        report.trim_end()
    ))
}

/// A verifier's verdict from its report: its first `Verdict:` line, pass (true) or fail (false).
fn verdict(report: &str) -> Option<bool> {
    report.lines().find_map(|line| {
        let line = line.trim().trim_start_matches(['*', '#', '-', ' ']);
        line.get(..8).filter(|head| head.eq_ignore_ascii_case("verdict:"))?;
        let word = line[8..].trim().trim_matches(['*', '`', ' ']).to_ascii_lowercase();
        match word.split(|c: char| !c.is_alphabetic()).next() {
            Some("pass") => Some(true),
            Some("fail") => Some(false),
            _ => None,
        }
    })
}

/// What a blocker message says: for a permission prompt the prompt's own lines, which is all the
/// Orchestrator shows the human; else, or when the prompt could not be read, the screen's tail.
fn blocker_body(blocker_kind: &str, message: &str, prompt: &str, screen_tail: &str) -> String {
    if prompt.is_empty() {
        format!("Blocked: {blocker_kind}\n{message}\n\nWorker screen (last {SCREEN_LINES} lines):\n{screen_tail}")
    } else {
        format!("Blocked: {blocker_kind}\n{message}\n\nThe prompt:\n{prompt}")
    }
}

/// The variables a running agent CLI sets for its own session. Kiro sets about thirty `KIRO_*`;
/// only the ones that name its session, its terminal or its binaries are markers: a Kiro started
/// from inside another would read the first one's session, ready file and paths. The rest of
/// `KIRO_*` is the human's own configuration and stays: `KIRO_HOME` (where the daemon writes the
/// agent files and Kiro must read them), `KIRO_API_KEY`, `KIRO_LOG_LEVEL`, `KIRO_TELEMETRY_*`.
fn is_agent_var(key: &str) -> bool {
    key == "CLAUDECODE"
        || key == "AI_AGENT"
        || key.starts_with("CLAUDE_CODE_")
        || key.starts_with("ORCA_")
        || key == "CLAUDE_PID"
        || key == "CLAUDE_EFFORT"
        || key == "KIRO_SESSION_ID"
        || key == "KIRO_TURN_MARKER_DIR"
        || key.starts_with("KIRO_TUI_READY_")
        || key.starts_with("KIRO_CHAT_CLI_")
        || key.starts_with("KIRO_KAS_")
}

/// The CLI, model and effort an agent starts with. An Orchestrator's order, from the highest: what
/// was picked for the agent, its Team's `orchestrator` (features/0081), the human's
/// `orchestratorModel` and `orchestratorEffort`, then the repo's and the human's general settings
/// (features/0053 and 0036). A Normal session takes the settings and what was picked alone.
fn agent_pick(
    state: &Path,
    repo: &Path,
    agent: &db::Agent,
    team: Option<&team::Team>,
) -> Result<(cli::Cli, Option<String>, Option<String>)> {
    let orchestrator = agent.kind == db::agent_kind::ORCHESTRATOR;
    let human = settings::read(state).unwrap_or_default();
    let orchestrator_model = orchestrator.then(|| settings::orchestrator_model(&human)).flatten();
    let setup = team
        .filter(|_| orchestrator)
        .and_then(|team| team.orchestrator.as_ref());
    let (agent_cli, model) = cli::pick(
        state,
        Some(repo),
        None,
        &[
            &cli::Choice {
                cli: None,
                model: orchestrator_model.clone(),
            },
            &cli::Choice {
                cli: setup.and_then(|setup| setup.cli.clone()),
                model: setup.and_then(|setup| setup.model.clone()),
            },
            &cli::Choice {
                cli: agent.cli.clone(),
                model: agent.model.clone(),
            },
        ],
    )
    .map_err(|error| match orchestrator_model {
        // An Anthropic name set for Claude must not be passed to another cli unseen.
        Some(_) => anyhow::anyhow!("{error:#} (an Orchestrator takes `orchestratorModel` from settings.json unless the agent or its Team has a model of its own)"),
        None => error,
    })?;
    let model = model.or_else(|| default_orchestrator_model(orchestrator, agent_cli));
    let effort = orchestrator.then(|| {
        setup
            .and_then(|setup| setup.effort.clone())
            .unwrap_or_else(|| settings::orchestrator_effort(&human))
    });
    Ok((agent_cli, model, effort))
}

/// What an Orchestrator runs when nothing names a model: claude's built-in default. Another cli
/// has no Anthropic name to start from, so it runs its own default until `orchestratorModel` or
/// the agent names one of its models.
fn default_orchestrator_model(orchestrator: bool, cli: cli::Cli) -> Option<String> {
    (orchestrator && cli == cli::Cli::Claude).then(|| settings::ORCHESTRATOR_MODEL.to_string())
}

/// "in place" for the repo's own checkout, else the worktree's folder name.
fn place(repo: &Path, cwd: &Path) -> String {
    if cwd == repo {
        "in place".into()
    } else {
        cwd.file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default()
    }
}

/// Keys `echoctl worker key` understands, as terminal input.
pub fn key_bytes(key: &str) -> Result<Vec<u8>> {
    Ok(match key {
        "enter" => b"\r".to_vec(),
        "esc" => b"\x1b".to_vec(),
        "up" => b"\x1b[A".to_vec(),
        "down" => b"\x1b[B".to_vec(),
        "right" => b"\x1b[C".to_vec(),
        "left" => b"\x1b[D".to_vec(),
        "tab" => b"\t".to_vec(),
        "shift-tab" => b"\x1b[Z".to_vec(),
        "space" => b" ".to_vec(),
        "backspace" => b"\x7f".to_vec(),
        "ctrl-c" => b"\x03".to_vec(),
        single if single.chars().count() == 1 => single.as_bytes().to_vec(),
        other => bail!(
            "unknown key {other:?}; use enter, esc, up, down, left, right, tab, shift-tab, space, backspace, ctrl-c, or one character"
        ),
    })
}

/// Whether an agent's screen has sat unchanged at its input box long enough to renew its session.
#[derive(Default)]
struct Quiet {
    since: Option<(Instant, u64)>,
    checked: Option<Instant>,
}

impl Quiet {
    /// Fed once a second with what the screen looks like; true when it has been unchanged and at
    /// its input box (idle, or waiting on background work it started) for `RENEW_QUIET`, and its
    /// size was not measured in the last `RENEW_CHECK`.
    fn settled(&mut self, look: Look, screen: &str, now: Instant) -> bool {
        use std::hash::{Hash, Hasher};
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        screen.hash(&mut hasher);
        let hash = hasher.finish();
        if !matches!(look, Look::Idle | Look::Waiting) {
            self.since = None;
            return false;
        }
        let since = match self.since {
            Some((since, seen)) if seen == hash => since,
            _ => {
                self.since = Some((now, hash));
                return false;
            }
        };
        if now.duration_since(since) < RENEW_QUIET || self.checked.is_some_and(|c| now.duration_since(c) < RENEW_CHECK)
        {
            return false;
        }
        self.checked = Some(now);
        true
    }
}

/// The Task a resumed Worker is on now (a later one from `worker next` or a verifier's feedback
/// replaces its first, features/0079) and the first message its CLI's resume sends with it.
fn resume_message(conn: &Connection, id: i64, cli: cli::Cli) -> Result<(String, String)> {
    let task = db::current_task(conn, id)?;
    let message = profile::resumed(cli, &task);
    Ok((task, message))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("hub-daemon-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn agent_of(kind: &str, cli: Option<&str>, model: Option<&str>) -> db::Agent {
        db::Agent {
            id: 1,
            repo: "/r".into(),
            kind: kind.into(),
            name: None,
            model: model.map(String::from),
            cli: cli.map(String::from),
            session_id: "s".into(),
            created_at: 0,
            cwd: None,
            branch: None,
            team: None,
        }
    }

    fn team_of(text: &str) -> team::Team {
        team::parse(text).unwrap()
    }

    fn pick(state: &Path, agent: &db::Agent, team: Option<&team::Team>) -> (cli::Cli, Option<String>, Option<String>) {
        agent_pick(state, &state.join("repo"), agent, team).unwrap()
    }

    #[test]
    fn an_orchestrator_without_a_team_runs_as_before() {
        let state = scratch("noteam");
        let orchestrator = agent_of(db::agent_kind::ORCHESTRATOR, None, None);
        assert_eq!(
            pick(&state, &orchestrator, None),
            (
                cli::Cli::Claude,
                Some(settings::ORCHESTRATOR_MODEL.to_string()),
                Some("high".to_string())
            )
        );
        std::fs::write(
            state.join("settings.json"),
            r#"{"orchestratorModel": "anthropic/claude-sonnet-5-5", "orchestratorEffort": "low"}"#,
        )
        .unwrap();
        assert_eq!(
            pick(&state, &orchestrator, None),
            (
                cli::Cli::Claude,
                Some("anthropic/claude-sonnet-5-5".to_string()),
                Some("low".to_string())
            )
        );
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn a_teams_orchestrator_sits_over_the_settings_and_under_what_was_picked() {
        let state = scratch("team-order");
        std::fs::write(
            state.join("settings.json"),
            r#"{"model": "anthropic/claude-haiku-5-5", "orchestratorModel": "anthropic/claude-opus-5-5", "orchestratorEffort": "low"}"#,
        )
        .unwrap();
        let team = team_of(r#"{"orchestrator": {"cli": "kiro", "model": "claude-sonnet-5.5", "effort": "medium"}}"#);
        let plain = agent_of(db::agent_kind::ORCHESTRATOR, None, None);
        assert_eq!(
            pick(&state, &plain, Some(&team)),
            (
                cli::Cli::Kiro,
                Some("claude-sonnet-5.5".to_string()),
                Some("medium".to_string())
            ),
            "the Team beats orchestratorModel, orchestratorEffort and the general model"
        );
        let picked = agent_of(
            db::agent_kind::ORCHESTRATOR,
            Some("claude"),
            Some("anthropic/claude-haiku-5-5"),
        );
        assert_eq!(
            pick(&state, &picked, Some(&team)),
            (
                cli::Cli::Claude,
                Some("anthropic/claude-haiku-5-5".to_string()),
                Some("medium".to_string())
            ),
            "what was picked for the agent wins; the Team's effort still applies"
        );
        let only_effort = team_of(r#"{"orchestrator": {"effort": "max"}}"#);
        assert_eq!(
            pick(&state, &plain, Some(&only_effort)),
            (
                cli::Cli::Claude,
                Some("anthropic/claude-opus-5-5".to_string()),
                Some("max".to_string())
            ),
            "a field the Team leaves out falls to the level below"
        );
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn a_normal_session_ignores_a_team_it_somehow_holds() {
        let state = scratch("normal-team");
        let team = team_of(r#"{"orchestrator": {"model": "anthropic/claude-sonnet-5-5", "effort": "max"}}"#);
        let normal = agent_of(db::agent_kind::CLAUDE, None, None);
        assert_eq!(pick(&state, &normal, Some(&team)), (cli::Cli::Claude, None, None));
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn an_edited_team_changes_the_next_start() {
        let hub = scratch("edit-hub");
        let state = scratch("edit-state");
        let file = state.join("teams/mine.json");
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        let orchestrator = agent_of(db::agent_kind::ORCHESTRATOR, None, None);
        let start = || {
            let team = team::load(&hub, &state, None, "mine").unwrap();
            pick(&state, &orchestrator, Some(&team))
        };
        std::fs::write(
            &file,
            r#"{"orchestrator": {"model": "anthropic/claude-sonnet-5-5", "effort": "low"}}"#,
        )
        .unwrap();
        assert_eq!(start().1.as_deref(), Some("anthropic/claude-sonnet-5-5"));
        std::fs::write(
            &file,
            r#"{"orchestrator": {"model": "anthropic/claude-haiku-5-5", "effort": "high"}}"#,
        )
        .unwrap();
        let (_, model, effort) = start();
        assert_eq!(model.as_deref(), Some("anthropic/claude-haiku-5-5"));
        assert_eq!(effort.as_deref(), Some("high"));
        let _ = std::fs::remove_dir_all(&hub);
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn a_resumed_worker_is_sent_the_task_it_is_on_now() {
        let conn = db::open(Path::new(":memory:")).unwrap();
        let id = db::insert_worker(
            &conn,
            &db::NewWorker {
                repo: "/r",
                profile: "naruto",
                title: "t",
                spec: "Fix the login test.",
                cwd: "/r",
                branch: None,
                session_id: "sid",
                agent: None,
                fanout: None,
                cli: None,
                model: None,
            },
        )
        .unwrap();
        let sent = |cli| resume_message(&conn, id, cli).unwrap();

        // One Task, as before the change: its spec, with no Task input yet or with the first one.
        assert_eq!(sent(cli::Cli::Kiro).0, "Fix the login test.");
        assert!(sent(cli::Cli::Kiro).1.ends_with("Fix the login test."));
        db::insert_task(&conn, id, db::origin::ORCHESTRATOR, "Fix the login test.").unwrap();
        assert_eq!(
            sent(cli::Cli::Kiro).1,
            profile::resumed(cli::Cli::Kiro, "Fix the login test.")
        );

        // A next Task, then feedback, a chat line and an earlier resume: the latest Task wins.
        db::insert_task(&conn, id, db::origin::ORCHESTRATOR, "Now add the logout test.").unwrap();
        db::insert_input(&conn, id, db::origin::HUMAN, "how is it going?").unwrap();
        db::insert_input(&conn, id, db::origin::ECHO, &sent(cli::Cli::Kiro).1).unwrap();
        let (task, kiro) = sent(cli::Cli::Kiro);
        assert_eq!(task, "Now add the logout test.");
        assert!(
            kiro.starts_with(profile::RESUMED) && kiro.ends_with("Now add the logout test."),
            "{kiro}"
        );
        assert!(!kiro.contains("login"), "{kiro}");
        db::insert_task(&conn, id, db::origin::ECHO, "w2 verified your change and it failed.").unwrap();
        assert!(sent(cli::Cli::Kiro)
            .1
            .ends_with("w2 verified your change and it failed."));

        // The first Task still stands in the row, and the other CLIs send what they always did.
        assert_eq!(db::worker_spec(&conn, id).unwrap(), "Fix the login test.");
        assert_eq!(sent(cli::Cli::Claude).1, profile::RESUMED);
        assert_eq!(sent(cli::Cli::Codex).1, profile::RESUMED);
    }

    #[test]
    fn a_screen_is_settled_only_when_unchanged_at_its_input_box_for_two_minutes_and_checked_rarely() {
        let t0 = Instant::now();
        let at = |secs: u64| t0 + Duration::from_secs(secs);
        let mut quiet = Quiet::default();
        assert!(!quiet.settled(Look::Idle, "a", at(0)));
        assert!(!quiet.settled(Look::Idle, "a", at(119)), "not yet");
        assert!(
            !quiet.settled(Look::Idle, "b", at(121)),
            "the screen changed: the wait starts over"
        );
        assert!(
            !quiet.settled(Look::Working, "b", at(300)),
            "a turn running is not quiet"
        );
        assert!(!quiet.settled(Look::Idle, "b", at(301)));
        assert!(
            quiet.settled(Look::Waiting, "b", at(430)),
            "waiting on its own listener counts"
        );
        assert!(!quiet.settled(Look::Waiting, "b", at(431)), "measured just now");
        assert!(!quiet.settled(Look::Waiting, "b", at(1000)));
        assert!(quiet.settled(Look::Waiting, "b", at(1031)), "again after ten minutes");
    }

    #[test]
    fn mux_sessions_are_safe_names() {
        assert_eq!(mux_session("lanh", "a3"), "echo-lanh-a3");
        assert_eq!(mux_session("my.repo:v2", "w21"), "echo-my-repo-v2-w21");
    }

    #[test]
    fn shell_words_are_quoted_only_when_needed() {
        assert_eq!(shell_quote("/usr/local/bin/echoctl"), "/usr/local/bin/echoctl");
        assert_eq!(shell_quote("HUB_STATE=/tmp/x"), "HUB_STATE=/tmp/x");
        assert_eq!(shell_quote("a b"), "'a b'");
        assert_eq!(shell_quote("it's"), "'it'\\''s'");
        assert_eq!(shell_quote(""), "''");
    }

    #[test]
    fn usage_lines_become_named_limits() {
        let text = "You are currently using your subscription to power your Claude Code usage\n\n\
                    Current session: 48% used · resets Oct 17 at 4:50pm (Asia/Saigon)\n\
                    Current week (all models): 9% used · resets Oct 23 at 11pm (Asia/Saigon)\n\
                    Current week (Fable): 0% used\n\
                    Last 24h · 1962 requests · 64 sessions\n  74% of your usage was at >150k context";
        let limits = parse_usage(text);
        assert_eq!(limits.len(), 3);
        assert_eq!(
            limits[0],
            json!({ "name": "Session", "percent": 48, "resets": "Oct 17 at 4:50pm" })
        );
        assert_eq!(limits[1]["name"], "Week");
        assert_eq!(
            limits[2],
            json!({ "name": "Week (Fable)", "percent": 0, "resets": null })
        );
    }

    #[test]
    fn kiro_credits_follow_claudes_limits_and_a_failed_read_keeps_the_last_good_one() {
        use kiro_usage::Outcome;
        let entry = json!({ "name": "Kiro credits", "percent": 30, "resets": "Dec 1", "detail": "603.62 of 2000" });
        let session = json!({ "name": "Session", "percent": 48, "resets": "Oct 17 at 4:50pm" });
        let mut usage = Usage {
            limits: vec![session.clone()],
            kiro_refreshing: true,
            ..Usage::default()
        };
        assert_eq!(usage.view()["limits"], json!([session]), "none read yet");

        usage.finish_kiro(Outcome::Reading(entry.clone()));
        assert!(!usage.kiro_refreshing);
        assert_eq!(usage.view()["limits"], json!([session, entry]));

        usage.kiro_refreshed = Some(Instant::now());
        usage.finish_kiro(Outcome::Failed("no network".into()));
        let view = usage.view();
        assert_eq!(view["limits"], json!([session, entry]), "the last good reading stays");
        assert!(view["error"].is_null(), "Claude's error is not touched");
        assert!(
            usage
                .kiro_refreshed
                .is_none_or(|at| at.elapsed() >= USAGE_EVERY - USAGE_RETRY),
            "the next try comes sooner than usual"
        );

        let newer = json!({ "name": "Kiro credits", "percent": 31, "resets": "Dec 1", "detail": "620 of 2000" });
        usage.finish_kiro(Outcome::Reading(newer.clone()));
        assert_eq!(usage.view()["limits"], json!([session, newer]));

        usage.kiro_refreshed = Some(Instant::now());
        usage.finish_kiro(Outcome::Skipped("no scratch home".into()));
        assert_eq!(
            usage.view()["limits"],
            json!([session, newer]),
            "a skipped read keeps the last value"
        );
        assert!(usage.view()["error"].is_null());
        assert!(
            usage
                .kiro_refreshed
                .is_none_or(|at| at.elapsed() >= USAGE_EVERY - USAGE_RETRY),
            "and the next try comes sooner than usual"
        );

        usage.kiro_refreshed = Some(Instant::now());
        usage.finish_kiro(Outcome::Absent);
        assert_eq!(usage.view()["limits"], json!([session]), "signed out: nothing shown");
        assert!(
            usage.kiro_refreshed.is_some_and(|at| at.elapsed() < USAGE_RETRY),
            "being signed out is waited on for the whole cadence"
        );
    }

    #[test]
    fn a_test_daemon_reads_no_kiro_credits_unless_a_stand_in_is_named() {
        // HUB_TEST_KIRO is not set in this test process.
        assert_eq!(kiro_usage_program(None).as_deref(), Some("kiro-cli"));
        assert_eq!(kiro_usage_program(Some("tests/fake-agent.sh")), None);
    }

    #[test]
    fn a_first_request_names_an_agent() {
        assert_eq!(
            name_from_request("  run all the rerank follow-ups, verify each one, and keep the bench going").as_deref(),
            Some("Run all the rerank follow-ups, verify")
        );
        assert_eq!(name_from_request("fix it.").as_deref(), Some("Fix it"));
        assert_eq!(name_from_request("/model opus"), None);
        assert_eq!(name_from_request("   "), None);
    }

    #[test]
    fn typed_lines_skip_escapes_and_backspaces() {
        let mut reader = LineReader::default();
        assert!(reader.feed(b"fix th").is_empty());
        assert_eq!(reader.feed(b"\x1b[Ae\x7fe bug\r"), ["fix the bug"]);
        assert!(reader.feed(b"\r").is_empty(), "an empty Enter is not a line");
        assert_eq!(reader.feed("héllo\x7f\x7fo\r".as_bytes()), ["hélo"]);
        assert_eq!(reader.feed(b"/model opus\rfix it\r"), ["/model opus", "fix it"]);
    }

    #[test]
    fn titles_come_from_the_first_spec_line() {
        assert_eq!(title_from_spec("\n# Task: Add login\n\nmore"), "Add login");
        assert_eq!(title_from_spec("Fix the build"), "Fix the build");
        assert_eq!(title_from_spec(""), "Task");
    }

    #[test]
    fn keys_map_to_terminal_input() {
        assert_eq!(key_bytes("enter").unwrap(), b"\r");
        assert_eq!(key_bytes("down").unwrap(), b"\x1b[B");
        assert_eq!(key_bytes("2").unwrap(), b"2");
        assert!(key_bytes("hyper").is_err());
    }

    #[test]
    fn a_verdict_is_the_first_verdict_line_of_the_report() {
        assert_eq!(verdict("Verdict: pass\nfindings"), Some(true));
        assert_eq!(verdict("intro\n**Verdict: FAIL**\nP1 x"), Some(false));
        assert_eq!(verdict("## verdict: `pass`"), Some(true));
        assert_eq!(verdict("Verdict: fail\nVerdict: pass"), Some(false));
        assert_eq!(verdict("looks fine"), None);
        assert_eq!(verdict("Verdict: unsure"), None);
    }

    #[test]
    fn a_task_ends_with_the_report_it_carries_verbatim() {
        let source = |report: Option<&str>| Worker {
            id: 4,
            repo: "/r".into(),
            profile: "sasuke".into(),
            title: "verify w3".into(),
            cwd: "/r".into(),
            branch: None,
            session_id: "s".into(),
            state: "done".into(),
            final_report: report.map(String::from),
            created_at: 0,
            settled_at: None,
            closed_at: None,
            last_message_at: None,
            agent_id: None,
            dismissed_at: None,
            fanout: None,
            cli: None,
            model: None,
            keep: false,
            verify: false,
            verifies: None,
            retries: 0,
        };
        let task = spec_with_report("Fix these.\n", &source(Some("Verdict: fail\nP1 a.rs:1\n"))).unwrap();
        assert_eq!(
            task,
            "Fix these.\n\nFinal Report of w4 (sasuke: verify w3), verbatim:\n\nVerdict: fail\nP1 a.rs:1"
        );
        assert!(spec_with_report("", &source(Some("x")))
            .unwrap()
            .starts_with("Final Report of w4"));
        assert!(spec_with_report("Fix.", &source(None))
            .unwrap_err()
            .to_string()
            .contains("w4 has no Final Report"));
    }

    #[test]
    fn a_permission_prompts_blocker_carries_the_prompt_not_the_screen() {
        let prompt = "Bash command\nrm -rf junk\nDo you want to proceed?";
        let body = blocker_body(
            "permission_prompt",
            "A permission prompt is waiting.",
            prompt,
            "SCREEN TAIL",
        );
        assert!(
            body.contains(prompt) && !body.contains("SCREEN TAIL") && !body.contains("Worker screen"),
            "{body}"
        );
        // Without a readable prompt, and for an idle Worker, the screen's tail is all there is.
        for (kind, prompt) in [("permission_prompt", ""), ("idle_prompt", "")] {
            let body = blocker_body(kind, "m", prompt, "SCREEN TAIL");
            assert!(body.contains("Worker screen (last 25 lines):\nSCREEN TAIL"), "{body}");
        }
    }

    #[test]
    fn agent_session_markers_are_not_inherited() {
        assert!(is_agent_var("CLAUDE_CODE_CHILD_SESSION"));
        assert!(is_agent_var("CLAUDECODE"));
        assert!(is_agent_var("ORCA_TERMINAL_HANDLE"));
        assert!(!is_agent_var("CLAUDE_CONFIG_DIR"));
        assert!(!is_agent_var("PATH"));
    }

    #[test]
    fn a_kiro_sessions_markers_are_not_inherited_but_the_humans_kiro_settings_are() {
        for marker in [
            "KIRO_SESSION_ID",
            "KIRO_TURN_MARKER_DIR",
            "KIRO_TUI_READY_FILE",
            "KIRO_TUI_READY_TOKEN",
            "KIRO_CHAT_CLI_BIN",
            "KIRO_CHAT_CLI_BIN_IDENTITY",
            "KIRO_CHAT_CLI_FALLBACK_BIN",
            "KIRO_KAS_NODE_PATH",
            "KIRO_KAS_SERVER_PATH",
        ] {
            assert!(is_agent_var(marker), "{marker}");
        }
        // The agent files go under $KIRO_HOME/agents and Kiro must look there too.
        for kept in [
            "KIRO_HOME",
            "KIRO_API_KEY",
            "KIRO_LOG_LEVEL",
            "KIRO_CHAT_LOG_FILE",
            "KIRO_TELEMETRY_ENABLED",
            "KIRO_TUI_FORCE_COLOR",
        ] {
            assert!(!is_agent_var(kept), "{kept}");
        }
    }

    #[test]
    fn only_claude_orchestrators_get_a_built_in_model() {
        let default = Some(settings::ORCHESTRATOR_MODEL.to_string());
        assert_eq!(default_orchestrator_model(true, cli::Cli::Claude), default);
        assert_eq!(default_orchestrator_model(false, cli::Cli::Claude), None);
        assert_eq!(default_orchestrator_model(true, cli::Cli::Kiro), None);
        assert_eq!(default_orchestrator_model(true, cli::Cli::Codex), None);
    }

    #[test]
    fn the_hint_for_answering_a_prompt_has_no_esc_for_kiro() {
        for cli in [cli::Cli::Claude, cli::Cli::Codex] {
            assert_eq!(decide_hint(cli, 7), "`echoctl worker key w7 enter` or `esc`");
        }
        let kiro = decide_hint(cli::Cli::Kiro, 7);
        assert_eq!(kiro, "`echoctl worker key w7 enter` or `down enter`");
        assert!(!kiro.contains("esc"));
    }

    #[test]
    fn place_names_worktrees() {
        assert_eq!(place(Path::new("/r"), Path::new("/r")), "in place");
        assert_eq!(place(Path::new("/r"), Path::new("/w/r/feat-x")), "feat-x");
    }

    #[test]
    fn side_shells_are_named_by_the_hex_of_their_path() {
        assert_eq!(unhex(&hex("/tmp/a b")), Some("/tmp/a b".to_string()));
        assert_eq!(hex("/a"), "2f61");
        assert_eq!(unhex("zz"), None);
        assert_eq!(unhex(""), None);
        assert_eq!(unhex("abc"), None);
        assert!(side_dir("relative").is_err());
        assert!(side_dir("/definitely/not/here").is_err());
        assert!(side_dir("/tmp").is_ok());
    }
}

/// One of Echo's event streams on a repo, counted while it lasts.
struct Watching<'a> {
    hub: &'a Hub,
    repo: &'a str,
}

impl Drop for Watching<'_> {
    fn drop(&mut self) {
        if let Some(count) = self.hub.watchers.lock().unwrap().get_mut(self.repo) {
            *count = count.saturating_sub(1);
        }
    }
}

/// How long a Worker has to show a turn under way after text is typed into it.
const START_WAIT: Duration = Duration::from_secs(5);

/// Typing into a dialog would answer it: the first character picks a choice, Enter takes one.
/// What the chat's Working row shows: whether the terminal runs, what its screen looks like, and
/// while it works, its spinner and current step.
fn chat_state(live: Option<&Live>) -> Value {
    let Some(live) = live else {
        return json!({ "live": false, "look": "stopped" });
    };
    let screen = live.screen();
    let look = match live.cli.look(&screen) {
        Look::TrustPrompt => "trust",
        Look::PermissionPrompt => "prompt",
        Look::Working => "working",
        Look::Waiting => "waiting",
        Look::Idle => "idle",
    };
    let (spinner, step) = screen::activity(&screen);
    json!({ "live": true, "look": look, "spinner": spinner, "step": step })
}

/// How the human is told to answer a permission prompt before typing: Esc denies it for claude
/// and codex but cancels the whole turn on Kiro, which denies with Down and Enter.
fn decide_hint(cli: cli::Cli, id: i64) -> String {
    match cli {
        cli::Cli::Kiro => format!("`echoctl worker key w{id} enter` or `down enter`"),
        _ => format!("`echoctl worker key w{id} enter` or `esc`"),
    }
}

fn refuse_over_dialog(live: &Live) -> Result<()> {
    match live.cli.look(&live.screen()) {
        Look::PermissionPrompt => bail!(
            "w{} shows a permission prompt, and typing would answer it; decide it with {} first, or pass --force",
            live.id,
            decide_hint(live.cli, live.id)
        ),
        Look::TrustPrompt => bail!(
            "w{} still shows its folder-trust dialog; try again in a moment",
            live.id
        ),
        _ => Ok(()),
    }
}

/// Presses keys one after another, a moment apart so a dialog has moved before the next arrives.
fn press(live: &Live, keys: &[&[u8]]) -> Result<()> {
    for (n, key) in keys.iter().enumerate() {
        if n > 0 {
            std::thread::sleep(Duration::from_millis(300));
        }
        live.write(key)?;
    }
    Ok(())
}

/// Types text at the input box, then Enter on its own; several lines go as one paste, so the
/// first line break does not send the rest early.
fn type_in(live: &Live, text: &str) -> Result<()> {
    if text.contains('\n') && live.with_screen(|s| s.bracketed_paste()) {
        live.write(format!("\x1b[200~{text}\x1b[201~").as_bytes())?;
    } else {
        live.write(text.as_bytes())?;
    }
    std::thread::sleep(Duration::from_millis(150));
    live.write(b"\r")?;
    Ok(())
}

/// Whether a turn got under way (working, or stopped at a prompt) within `START_WAIT`.
fn started(live: &Live) -> bool {
    let deadline = Instant::now() + START_WAIT;
    loop {
        if matches!(live.cli.look(&live.screen()), Look::Working | Look::PermissionPrompt) {
            return true;
        }
        if Instant::now() >= deadline || !live.is_alive() {
            return false;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

enum LaunchKind {
    New,
    Resume,
}

/// Runs a new worktree's setup in the agent's own terminal, in the human's login shell so its
/// PATH has their tools, then the agent; when the setup fails the agent is not started, and the
/// terminal's last lines say why.
fn with_setup(mut spawn: Spawn, setup: &str) -> Spawn {
    const SCRIPT: &str = r#"printf 'Echo: setting up this worktree: %s\n\n' "$ECHO_SETUP"
"${SHELL:-/bin/sh}" -lc "$ECHO_SETUP" || { status=$?; printf '\nEcho: the setup failed (exit %s), so the agent was not started.\n' "$status"; exit "$status"; }
exec "$@""#;
    let mut args = vec!["-c".to_string(), SCRIPT.to_string(), "sh".to_string(), spawn.program];
    args.extend(spawn.args);
    spawn.program = "/bin/sh".into();
    spawn.args = args;
    spawn.env.push(("ECHO_SETUP".into(), setup.into()));
    spawn
}

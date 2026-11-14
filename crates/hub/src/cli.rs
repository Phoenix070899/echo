//! Agent CLIs: the one place that knows how each runs. The daemon says what an agent starts with
//! (a `Start`); a `Cli` turns that into its own program and flags, and says whether a session can
//! be resumed. Which CLI and model an agent gets is picked here too, from the levels in `pick`.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{bail, Context, Result};

use crate::{paths, screen};

/// An agent CLI Echo can run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cli {
    Claude,
    /// OpenAI's Codex CLI.
    Codex,
    /// AWS's Kiro CLI (`kiro-cli`), on its V3 harness.
    Kiro,
}

/// Names Echo knows but cannot run yet, so the error says so instead of "unknown".
const COMING: &[&str] = &["opencode", "gemini"];

impl Cli {
    pub fn parse(name: &str) -> Result<Cli> {
        match name {
            "claude" => Ok(Cli::Claude),
            "codex" => Ok(Cli::Codex),
            "kiro" => Ok(Cli::Kiro),
            other if COMING.contains(&other) => {
                bail!("cli {other:?} is not supported yet (only claude, codex and kiro)")
            }
            other => bail!("unknown cli {other:?}; Echo runs claude, codex and kiro"),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Cli::Claude => "claude",
            Cli::Codex => "codex",
            Cli::Kiro => "kiro",
        }
    }

    /// The binary that runs it; `name` is what Echo stores and shows.
    pub fn program(self) -> &'static str {
        match self {
            Cli::Kiro => "kiro-cli",
            other => other.name(),
        }
    }

    /// The CLI's own name for a `provider/model`; a bare name is passed as it is.
    pub fn model_arg(self, model: &str) -> Result<String> {
        match (self, model.split_once('/')) {
            (Cli::Claude, None) => Ok(model.to_string()),
            (Cli::Claude, Some(("anthropic", name))) => Ok(name.to_string()),
            (Cli::Claude, Some((provider, _))) => {
                bail!("claude runs only Anthropic models, not {provider}'s {model:?}; pick another cli for it")
            }
            (Cli::Codex, None) => Ok(model.to_string()),
            (Cli::Codex, Some(("openai", name))) => Ok(name.to_string()),
            (Cli::Codex, Some((provider, _))) => {
                bail!("codex runs OpenAI models here, not {provider}'s {model:?}; pick another cli for it")
            }
            (Cli::Kiro, None) => Ok(model.to_string()),
            (Cli::Kiro, Some(("kiro", name))) => Ok(name.to_string()),
            (Cli::Kiro, Some((provider, _))) => {
                bail!("kiro runs its own model ids here, not {provider}'s {model:?}; pick another cli for it")
            }
        }
    }

    /// Whether a session with this id has started, so it can be resumed instead of begun again.
    pub fn has_session(self, session_id: &str) -> bool {
        match self {
            Cli::Claude => paths::transcript_exists(session_id),
            Cli::Codex => codex_session_exists(session_id),
            Cli::Kiro => kiro_session_exists(&kiro_home(), session_id),
        }
    }

    /// What its screen shows now: a prompt, a turn under way, or its input box.
    pub fn look(self, screen: &str) -> screen::Look {
        match self {
            Cli::Claude => screen::look(screen),
            Cli::Codex => screen::codex_look(screen),
            Cli::Kiro => screen::kiro_look(screen),
        }
    }

    /// The lines of the permission prompt on screen, for the human to decide on.
    pub fn prompt_lines(self, screen: &str) -> String {
        match self {
            Cli::Claude => screen::prompt_lines(screen),
            Cli::Codex => screen::codex_prompt_lines(screen),
            Cli::Kiro => screen::kiro_prompt_lines(screen),
        }
    }

    /// Whether the screen shows a turn that finished at the input box.
    pub fn turn_ended(self, screen: &str) -> bool {
        match self {
            Cli::Claude => screen::turn_ended(screen),
            Cli::Codex => screen::codex_turn_ended(screen),
            Cli::Kiro => screen::kiro_turn_ended(screen),
        }
    }

    /// The keys that answer its folder-trust dialog with "trust".
    pub fn trust_keys(self) -> &'static [&'static [u8]] {
        match self {
            // Claude's dialog starts on "No, exit".
            Cli::Claude => &[b"\x1b[B", b"\r"],
            Cli::Codex => &[b"\r"],
            // Its dialog starts on "Trust, continue"; `--trust-workspace` normally skips it.
            Cli::Kiro => &[b"\r"],
        }
    }

    /// The keys that approve the permission prompt on screen, once.
    pub fn approve_keys(self) -> &'static [&'static [u8]] {
        // Every prompt starts its cursor on the approving row, Kiro's "Allow once" too.
        &[b"\r"]
    }

    /// The keys that deny the permission prompt on screen, once.
    pub fn deny_keys(self) -> &'static [&'static [u8]] {
        match self {
            Cli::Claude | Cli::Codex => &[b"\x1b"],
            // Esc would cancel the whole turn; "Deny once" is the second row.
            Cli::Kiro => &[b"\x1b[B", b"\r"],
        }
    }

    /// The arguments after `program()` for `start`.
    pub fn args(self, hub: &Path, start: &Start) -> Result<Vec<String>> {
        match self {
            Cli::Claude => claude(hub, start),
            Cli::Codex => codex(start),
            Cli::Kiro => kiro(&kiro_home(), &with_kiro_notes(hub, start)?),
        }
    }

    /// Fails when a Kiro Worker could not start for want of its notes (`hub/kiro-notes.md`), so
    /// that is known before a worktree or a row is made for it. The others need no notes.
    pub fn check_worker_notes(self, hub: &Path) -> Result<()> {
        if self != Cli::Kiro {
            return Ok(());
        }
        let worker = Start {
            worker: true,
            ..Start::default()
        };
        with_kiro_notes(hub, &worker).map(|_| ())
    }
}

/// What an agent starts with, whatever its CLI.
#[derive(Debug, Default, Clone)]
pub struct Start {
    /// The session's title in the CLI's own session list.
    pub title: String,
    /// Put after the CLI's own system prompt; empty adds nothing.
    pub prompt: String,
    /// Folders beyond its working directory that it may read and edit.
    pub dirs: Vec<PathBuf>,
    /// Plugin folders (skills, hooks, views) to load.
    pub plugins: Vec<PathBuf>,
    pub model: Option<String>,
    pub effort: Option<String>,
    /// Only these tools; empty means the CLI's own set.
    pub tools: Vec<String>,
    /// A Worker: nobody watches it, so it runs unprompted, reports prompts, and never asks the
    /// human directly.
    pub worker: bool,
    /// The folder the agent works in; Kiro's permission rules name it.
    pub cwd: Option<PathBuf>,
    pub session_id: String,
    pub resume: bool,
    /// The first message: a Task, a request, or what to do after a restart.
    pub first: Option<String>,
    /// The human's own extra arguments, passed through.
    pub extra: Vec<String>,
}

fn claude(hub: &Path, start: &Start) -> Result<Vec<String>> {
    let mut args = vec!["-n".to_string(), start.title.clone()];
    if let Some(model) = &start.model {
        if !start.extra.iter().any(|arg| arg == "--model") {
            args.extend(["--model".into(), Cli::Claude.model_arg(model)?]);
        }
    }
    if start.worker {
        args.extend([
            "--permission-mode".into(),
            "auto".into(),
            "--settings".into(),
            hub.join("settings").join("worker.json").display().to_string(),
            "--disallowedTools".into(),
            "AskUserQuestion".into(),
        ]);
    }
    for plugin in &start.plugins {
        args.extend(["--plugin-dir".into(), plugin.display().to_string()]);
    }
    for dir in &start.dirs {
        args.extend(["--add-dir".into(), dir.display().to_string()]);
    }
    if let Some(effort) = &start.effort {
        args.extend(["--effort".into(), effort.clone()]);
    }
    if !start.tools.is_empty() {
        // Without ToolSearch every MCP tool loads in full instead of on demand: about 85k tokens
        // of connectors no Worker uses, re-read on every turn.
        let mut tools = start.tools.clone();
        if !tools.iter().any(|tool| tool == "ToolSearch") {
            tools.push("ToolSearch".into());
        }
        args.extend(["--tools".into(), tools.join(",")]);
    }
    if !start.prompt.is_empty() {
        args.extend(["--append-system-prompt".into(), start.prompt.clone()]);
    }
    args.extend(start.extra.iter().cloned());
    args.extend([
        if start.resume { "--resume" } else { "--session-id" }.into(),
        start.session_id.clone(),
    ]);
    // After `--`, so a first message starting with `-` is not taken for an option.
    if let Some(first) = &start.first {
        args.extend(["--".into(), first.clone()]);
    }
    Ok(args)
}

/// Codex keeps each session as `~/.codex/sessions/<y>/<m>/<d>/rollout-<time>-<id>.jsonl`.
fn codex_session_exists(session_id: &str) -> bool {
    fn find(dir: &Path, end: &str, depth: u8) -> bool {
        let Ok(read) = std::fs::read_dir(dir) else { return false };
        read.flatten().any(|entry| {
            let path = entry.path();
            match depth {
                0 => path.file_name().is_some_and(|n| n.to_string_lossy().ends_with(end)),
                _ => path.is_dir() && find(&path, end, depth - 1),
            }
        })
    }
    !session_id.is_empty()
        && find(
            &paths::home().join(".codex").join("sessions"),
            &format!("-{session_id}.jsonl"),
            3,
        )
}

/// A TOML basic string, for a `-c key=value` whose value must not be read as anything else.
fn toml_string(text: &str) -> String {
    let mut out = String::from("\"");
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c if c.is_control() => out.push_str(&format!("\\u{:04X}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Codex has no session id to set up front and no per-run settings file: Echo passes its hooks
/// inline and learns the session id from the SessionStart hook (`echoctl notify`).
fn codex(start: &Start) -> Result<Vec<String>> {
    let mut args = Vec::new();
    if start.resume {
        args.extend(["resume".to_string(), start.session_id.clone()]);
    }
    if let Some(model) = &start.model {
        if !start.extra.iter().any(|arg| arg == "-m" || arg == "--model") {
            args.extend(["-m".into(), Cli::Codex.model_arg(model)?]);
        }
    }
    let hook =
        |event: &str| format!("hooks.{event}=[{{hooks=[{{type=\"command\",command=\"echoctl notify\",timeout=10}}]}}]");
    args.extend([
        "--dangerously-bypass-hook-trust".into(),
        "-c".into(),
        hook("SessionStart"),
    ]);
    if start.worker {
        // Unwatched: work in the checkout with the network, and ask (a blocker) only to leave it.
        args.extend([
            "-a".into(),
            "on-request".into(),
            "-s".into(),
            "workspace-write".into(),
            "-c".into(),
            "sandbox_workspace_write.network_access=true".into(),
            // Not PermissionRequest: it fires before Codex's own reviewer decides, so most never
            // reach the screen. Prompts are read from the screen, as for claude.
            "-c".into(),
            hook("Stop"),
        ]);
    }
    for dir in &start.dirs {
        args.extend(["--add-dir".into(), dir.display().to_string()]);
    }
    if let Some(effort) = &start.effort {
        args.extend(["-c".into(), format!("model_reasoning_effort={}", toml_string(effort))]);
    }
    if !start.prompt.is_empty() {
        args.extend([
            "-c".into(),
            format!("developer_instructions={}", toml_string(&start.prompt)),
        ]);
    }
    args.extend(start.extra.iter().cloned());
    if let Some(first) = &start.first {
        args.extend(["--".into(), first.clone()]);
    }
    Ok(args)
}

/// Kiro's own folder (sign-in, sessions, agents): `$KIRO_HOME`, else `~/.kiro`.
fn kiro_home() -> PathBuf {
    std::env::var_os("KIRO_HOME")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| paths::home().join(".kiro"))
}

/// Kiro keeps each session as `<home>/sessions/<workspace hash>/sess_<uuid>/`; a hook reports the
/// id with its `sess_` prefix and `--resume-id` takes it with or without, so either spelling counts.
fn kiro_session_exists(home: &Path, session_id: &str) -> bool {
    !kiro_session_dirs(home, session_id).is_empty()
}

/// Whether the session has held a turn: its `messages.jsonl` appears with the first one. A session
/// folder exists from the TUI's start, before any prompt, and holds no Task yet.
fn kiro_session_has_history(home: &Path, session_id: &str) -> bool {
    kiro_session_dirs(home, session_id)
        .iter()
        .any(|dir| dir.join("messages.jsonl").is_file())
}

/// The `messages.jsonl` of a Kiro session, wherever its workspace bucket is. When both spellings
/// of the id have a folder (docs/bugs/0070), the file written last is the live one.
pub fn kiro_transcript(session_id: &str) -> Option<PathBuf> {
    kiro_transcript_in(&kiro_home(), session_id)
}

fn kiro_transcript_in(home: &Path, session_id: &str) -> Option<PathBuf> {
    kiro_session_dirs(home, session_id)
        .into_iter()
        .map(|dir| dir.join("messages.jsonl"))
        .filter_map(|file| Some((file.metadata().ok()?.modified().ok()?, file)))
        .max_by_key(|(modified, _)| *modified)
        .map(|(_, file)| file)
}

/// The folders of a session across the workspace buckets, under either spelling of its id.
fn kiro_session_dirs(home: &Path, session_id: &str) -> Vec<PathBuf> {
    let plain_id = |c: char| c.is_ascii_alphanumeric() || c == '-' || c == '_';
    if session_id.is_empty() || !session_id.chars().all(plain_id) {
        return Vec::new();
    }
    let bare = session_id.strip_prefix("sess_").unwrap_or(session_id);
    let names = [bare.to_string(), format!("sess_{bare}")];
    let Ok(buckets) = std::fs::read_dir(home.join("sessions")) else {
        return Vec::new();
    };
    let mut dirs = Vec::new();
    for bucket in buckets.flatten() {
        dirs.extend(
            names
                .iter()
                .map(|name| bucket.path().join(name))
                .filter(|dir| dir.is_dir()),
        );
    }
    dirs
}

/// FNV-1a, 64 bit: the same text hashes the same on every run and build, which `DefaultHasher`
/// does not promise, and the agent file's name must not change between two starts.
fn fnv1a(text: &str) -> u64 {
    text.bytes().fold(0xcbf2_9ce4_8422_2325, |hash, byte| {
        (hash ^ u64::from(byte)).wrapping_mul(0x0100_0000_01b3)
    })
}

/// The part of `kiro-notes.md` under the `## <title>` heading, up to the next `## ` heading.
fn notes_section<'a>(notes: &'a str, title: &str) -> Option<&'a str> {
    let heading = format!("## {title}");
    let mut offset = 0;
    let mut start = None;
    for line in notes.split_inclusive('\n') {
        let text = line.trim_end();
        match start {
            None if text == heading => start = Some(offset + line.len()),
            Some(from) if text.starts_with("## ") => return Some(notes[from..offset].trim()),
            _ => {}
        }
        offset += line.len();
    }
    start.map(|from| notes[from..].trim())
}

/// `start` with the Kiro notes for its role added to its prompt. The prompt is the body of the
/// agent file, so the file's name (a hash of its content) covers the notes: a change to
/// `kiro-notes.md` starts the next agent on a new file and leaves the running ones' alone. A Normal
/// session has no prompt of Echo's, so it gets no notes.
fn with_kiro_notes(hub: &Path, start: &Start) -> Result<Start> {
    let title = match (start.worker, start.prompt.is_empty()) {
        (true, _) => "Worker",
        (false, false) => "Orchestrator",
        (false, true) => return Ok(start.clone()),
    };
    let path = hub.join("kiro-notes.md");
    let notes = std::fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
    let Some(section) = notes_section(&notes, title).filter(|section| !section.is_empty()) else {
        bail!("{} has no \"## {title}\" section", path.display());
    };
    Ok(Start {
        prompt: format!("{}\n\n# Running on Kiro\n\n{section}", start.prompt.trim_end()),
        ..start.clone()
    })
}

/// A string as a YAML double-quoted scalar (JSON strings are one).
fn yaml_string(text: &str) -> String {
    serde_json::Value::String(text.to_string()).to_string()
}

/// Kiro's tool names for Claude's (`Start::tools` is a list of Claude's); the others have no
/// Kiro counterpart and are left out. Nothing left means Kiro's whole set.
fn kiro_tools(tools: &[String]) -> Vec<&'static str> {
    let mut out: Vec<&'static str> = Vec::new();
    for tool in tools {
        let mapped = match tool.as_str() {
            "Bash" => "shell",
            "Read" => "read",
            "Edit" | "Write" | "NotebookEdit" => "write",
            "WebFetch" | "WebSearch" => "web",
            _ => continue,
        };
        if !out.contains(&mapped) {
            out.push(mapped);
        }
    }
    if out.is_empty() {
        out.push("*");
    }
    out
}

/// One permission rule of a Kiro agent file.
struct KiroRule {
    capability: &'static str,
    globs: Vec<String>,
    effect: &'static str,
}

impl KiroRule {
    fn allow(capability: &'static str, globs: Vec<String>) -> KiroRule {
        KiroRule {
            capability,
            globs,
            effect: "allow",
        }
    }
}

/// Commands a Worker may never run, the same ones `settings/worker.json` asks about for Claude.
const KIRO_DENIED_COMMANDS: &[&str] = &[
    "rm -rf *",
    "rm -fr *",
    "git reset --hard*",
    "sudo *",
    "curl * | sh",
    "curl * | bash",
    "wget * | sh",
    "wget * | bash",
];

/// The `echoctl` commands an Orchestrator runs (`orchestrator.md`, `kiro-notes.md`). `"cmd *"`
/// matches the command with or without arguments, so each is one glob. They are named one by one
/// and not as `echoctl *`: Kiro's spike did not show whether a glob also matches a chained
/// command, so a rule must not cover more `echoctl` than the Orchestrator needs.
const KIRO_ORCHESTRATOR_COMMANDS: &[&str] = &[
    "echoctl wait *",
    "echoctl worker *",
    "echoctl reply *",
    "echoctl brief *",
    "echoctl inbox *",
    "echoctl status *",
    "echoctl sessions *",
    "echoctl profile *",
    "echoctl ui *",
];

/// What the agent may do without asking. A Worker works unwatched: it reads anywhere, writes in
/// its checkout and the folders Echo gives it, and runs shell commands except the destructive
/// ones (a shell rule matches the command text, never a folder, so the deny list is its guard;
/// `fs_read` anywhere also stops the second prompt a shell command raises for its folder).
/// An Orchestrator is spared the prompts for its own `echoctl` calls, which it makes every few
/// minutes while it waits and which would otherwise hold up its Workers' messages: those commands
/// and their folder (its checkout, which is also the folder such a call runs in), under the same
/// deny list. Anything else it runs still reaches the human. A Normal session is only spared the
/// prompts for the folders Echo gave it.
fn kiro_rules(start: &Start) -> Vec<KiroRule> {
    let folders =
        |roots: &[&Path]| -> Vec<String> { roots.iter().map(|root| root.join("**").display().to_string()).collect() };
    let denied = || KiroRule {
        capability: "shell",
        globs: KIRO_DENIED_COMMANDS.iter().map(|c| c.to_string()).collect(),
        effect: "deny",
    };
    let mut roots: Vec<&Path> = start.cwd.iter().map(PathBuf::as_path).collect();
    roots.extend(start.dirs.iter().map(PathBuf::as_path));
    if !start.worker {
        let dirs: Vec<&Path> = start.dirs.iter().map(PathBuf::as_path).collect();
        let mut rules = Vec::new();
        let mut reads = dirs.clone();
        let orchestrator = !start.prompt.is_empty();
        if orchestrator {
            reads.extend(start.cwd.as_deref());
        }
        if !reads.is_empty() {
            rules.push(KiroRule::allow("fs_read", folders(&reads)));
        }
        if !dirs.is_empty() {
            rules.push(KiroRule::allow("fs_write", folders(&dirs)));
        }
        if orchestrator {
            let commands = KIRO_ORCHESTRATOR_COMMANDS.iter().map(|c| c.to_string()).collect();
            rules.push(KiroRule::allow("shell", commands));
            rules.push(denied());
        }
        return rules;
    }
    let mut rules = vec![KiroRule::allow("fs_read", vec!["**".into()])];
    if !roots.is_empty() {
        rules.push(KiroRule::allow("fs_write", folders(&roots)));
    }
    rules.push(KiroRule::allow("shell", vec!["*".into(), "**".into()]));
    rules.push(denied());
    rules
}

/// The agent file for `start` under `name`: Markdown, its front matter holding everything but the
/// prompt, which is the body.
fn kiro_agent_text(start: &Start, name: &str) -> Result<String> {
    let kind = match (start.worker, start.prompt.is_empty()) {
        (true, _) => "worker",
        (false, false) => "orchestrator",
        (false, true) => "session",
    };
    let list = |items: Vec<String>| format!("[{}]", items.join(", "));
    let mut text = format!("---\nname: {name}\ndescription: Echo {kind}\n");
    if let Some(model) = &start.model {
        text.push_str(&format!("model: {}\n", yaml_string(&Cli::Kiro.model_arg(model)?)));
    }
    text.push_str(&format!(
        "tools: {}\n",
        list(kiro_tools(&start.tools).iter().map(|t| yaml_string(t)).collect())
    ));
    let rules = kiro_rules(start);
    if !rules.is_empty() {
        text.push_str("permissions:\n  rules:\n");
        for rule in rules {
            text.push_str(&format!(
                "    - capability: {}\n      match: {}\n      effect: {}\n",
                rule.capability,
                list(rule.globs.iter().map(|g| yaml_string(g)).collect()),
                rule.effect
            ));
        }
    }
    // Both run `echoctl notify`, which finds the agent from the HUB_WORKER and HUB_AGENT that
    // Kiro's hooks inherit. SessionStart fires on the first prompt and carries the session id.
    let mut hooks = vec![("echo-session-start", "SessionStart")];
    if start.worker {
        hooks.push(("echo-stop", "Stop"));
    }
    text.push_str("hooks:\n");
    for (hook, trigger) in hooks {
        text.push_str(&format!(
            "  - name: {hook}\n    trigger: {trigger}\n    action:\n      type: command\n      command: \"echoctl notify\"\n"
        ));
    }
    text.push_str("---\n\n");
    text.push_str(&start.prompt);
    if !start.prompt.ends_with('\n') {
        text.push('\n');
    }
    Ok(text)
}

/// Writes the agent file for `start` into `<home>/agents/` unless it is there, and returns the
/// agent's name. The name is `echo-` and a hash of the file's content, so a file is never
/// rewritten with other content and two starts at once cannot read each other's prompt.
fn write_kiro_agent(home: &Path, start: &Start) -> Result<String> {
    static TEMPS: AtomicU64 = AtomicU64::new(0);
    let hash = fnv1a(&kiro_agent_text(start, "echo-0")?);
    let name = format!("echo-{hash:016x}");
    let dir = home.join("agents");
    let path = dir.join(format!("{name}.md"));
    if path.exists() {
        return Ok(name);
    }
    std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
    let temp = dir.join(format!(
        ".{name}.{}.{}.tmp",
        std::process::id(),
        TEMPS.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::write(&temp, kiro_agent_text(start, &name)?).with_context(|| format!("writing {}", temp.display()))?;
    std::fs::rename(&temp, &path).map_err(|e| {
        let _ = std::fs::remove_file(&temp);
        anyhow::anyhow!("writing {}: {e}", path.display())
    })?;
    Ok(name)
}

/// Kiro has no flag for a system prompt, folders or a session id: the prompt, tools, rules and
/// hooks go in an agent file (`write_kiro_agent`), and the session id comes from its SessionStart
/// hook (`echoctl notify`). `--trust-workspace` answers the folder-trust dialog.
fn kiro(home: &Path, start: &Start) -> Result<Vec<String>> {
    let agent = write_kiro_agent(home, start)?;
    let mut args: Vec<String> = ["chat", "--v3", "--agent"].map(String::from).into();
    args.push(agent);
    let given = |flag: &str| start.extra.iter().any(|arg| arg == flag);
    if let Some(model) = &start.model {
        if !given("--model") {
            args.extend(["--model".into(), Cli::Kiro.model_arg(model)?]);
        }
    }
    if let Some(effort) = &start.effort {
        if !given("--effort") {
            args.extend(["--effort".into(), effort.clone()]);
        }
    }
    args.push("--trust-workspace".into());
    // `--resume-id` with an id Kiro holds no history for does not fail: it opens a plain session
    // under that id, on Kiro's default agent and model, with none of the Task. So a session
    // without history starts afresh as this agent, with the same message.
    if start.resume && kiro_session_has_history(home, &start.session_id) {
        args.extend(["--resume-id".into(), start.session_id.clone()]);
    }
    args.extend(start.extra.iter().cloned());
    if let Some(first) = &start.first {
        // The message goes last as the positional INPUT. `--` cannot guard it: headless it works,
        // but in the interactive TUI the message is lost. Unguarded, a leading `-` is read as an
        // option (`-d <id>` deletes a session). The spike proved only that a non-dash start is
        // safe, so a message starting with `-` gets a plain-word prefix that survives trimming.
        args.push(if first.starts_with('-') {
            format!("Message: {first}")
        } else {
            first.clone()
        });
    }
    Ok(args)
}

/// A CLI and a model, as one level names them; either may be left to the level below.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Choice {
    pub cli: Option<String>,
    pub model: Option<String>,
}

impl Choice {
    /// `settings.json` in a folder: `{"cli": "claude", "model": "anthropic/claude-sonnet-5-5"}`.
    pub fn read(dir: &Path) -> Result<Choice> {
        Ok(Choice::from_settings(&crate::settings::read(dir)?))
    }

    fn from_settings(value: &serde_json::Map<String, serde_json::Value>) -> Choice {
        let field = |key: &str| {
            value
                .get(key)
                .and_then(|v| v.as_str())
                .map(String::from)
                .filter(|v| !v.is_empty())
        };
        Choice {
            cli: field("cli"),
            model: field("model"),
        }
    }
}

/// What the files name: the state's `settings.json`, then the repo's `.echo/settings.json` over
/// it. `force` is `forceCli`, the repo's over the state's.
struct Files {
    levels: Vec<Choice>,
    force: bool,
}

impl Files {
    fn read(state: &Path, repo: Option<&Path>) -> Result<Files> {
        let mut files = Files {
            levels: Vec::new(),
            force: false,
        };
        let repo_echo = repo.map(|repo| repo.join(".echo"));
        for dir in std::iter::once(state).chain(repo_echo.as_deref()) {
            let value = crate::settings::read(dir)?;
            files.levels.push(Choice::from_settings(&value));
            if let Some(force) = crate::settings::force_cli(&value, dir)? {
                files.force = force;
            }
        }
        Ok(files)
    }

    /// Whether a Profile's own cli and model are put aside: `forceCli` is on and a file names a cli.
    fn overrides_profile(&self) -> bool {
        self.force && self.levels.iter().any(|level| level.cli.is_some())
    }
}

/// The CLI an agent that is already running was started with, to read its screen after a daemon
/// restart. It looks at the same levels as `pick` but not at the model: a model that no longer
/// fits, or a `settings.json` that cannot be read, must not turn a Kiro agent into a Claude one,
/// whose reader would not know its prompts. Only a CLI no level names, or one Echo no longer
/// knows, is claude.
pub fn recovered(state: &Path, repo: Option<&Path>, profile: Option<&Choice>, picked: &[&Choice]) -> Cli {
    let read = |dir: &Path| {
        let value = crate::settings::read(dir).unwrap_or_default();
        let force = crate::settings::force_cli(&value, dir).ok().flatten();
        (Choice::from_settings(&value).cli, force)
    };
    let (state_cli, state_force) = read(state);
    let (repo_cli, repo_force) = repo.map(|repo| read(&repo.join(".echo"))).unwrap_or_default();
    let file_cli = repo_cli.or(state_cli);
    let forced = repo_force.or(state_force).unwrap_or(false) && file_cli.is_some();
    let profile_cli = profile.filter(|_| !forced).and_then(|choice| choice.cli.clone());
    let name = picked
        .iter()
        .rev()
        .find_map(|choice| choice.cli.clone())
        .or(profile_cli)
        .or(file_cli);
    name.and_then(|name| Cli::parse(&name).ok()).unwrap_or(Cli::Claude)
}

/// The CLI and model an agent runs with: the choice made at its start (`picked`, the last one
/// first), else its Profile's, else the repo's (`.echo/settings.json`), else the human's
/// (`settings.json` in the state), else claude with its own default model. With `forceCli` on and
/// a cli set in those files, the Profile's cli and model are left out (features/0075).
pub fn pick(
    state: &Path,
    repo: Option<&Path>,
    profile: Option<&Choice>,
    picked: &[&Choice],
) -> Result<(Cli, Option<String>)> {
    let files = Files::read(state, repo)?;
    let mut all = files.levels.clone();
    if let Some(profile) = profile.filter(|_| !files.overrides_profile()) {
        all.push(profile.clone());
    }
    all.extend(picked.iter().map(|c| (*c).clone()));
    let cli = all.iter().rev().find_map(|c| c.cli.clone());
    let model = all.iter().rev().find_map(|c| c.model.clone());
    let cli = Cli::parse(cli.as_deref().unwrap_or("claude"))?;
    if let Some(model) = &model {
        cli.model_arg(model)?;
    }
    Ok((cli, model))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("hub-cli-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn claude_takes_anthropic_models_by_either_name() {
        assert_eq!(
            Cli::Claude.model_arg("anthropic/claude-opus-5-5").unwrap(),
            "claude-opus-5-5"
        );
        assert_eq!(Cli::Claude.model_arg("claude-opus-5-5").unwrap(), "claude-opus-5-5");
        assert!(Cli::Claude
            .model_arg("openai/gpt-5")
            .unwrap_err()
            .to_string()
            .contains("only Anthropic"));
        assert!(Cli::parse("opencode")
            .unwrap_err()
            .to_string()
            .contains("not supported yet"));
        assert!(Cli::parse("vim").unwrap_err().to_string().contains("unknown cli"));
    }

    #[test]
    fn each_level_overrides_the_one_before() {
        let state = scratch("state");
        let repo = scratch("repo");
        assert_eq!(pick(&state, Some(&repo), None, &[]).unwrap(), (Cli::Claude, None));
        std::fs::write(
            state.join("settings.json"),
            r#"{"model": "anthropic/claude-haiku-5-5"}"#,
        )
        .unwrap();
        std::fs::create_dir_all(repo.join(".echo")).unwrap();
        std::fs::write(repo.join(".echo/settings.json"), r#"{"model": "claude-sonnet-5-5"}"#).unwrap();
        assert_eq!(
            pick(&state, None, None, &[]).unwrap().1.as_deref(),
            Some("anthropic/claude-haiku-5-5")
        );
        assert_eq!(
            pick(&state, Some(&repo), None, &[]).unwrap().1.as_deref(),
            Some("claude-sonnet-5-5")
        );
        let profile = Choice {
            cli: Some("claude".into()),
            model: Some("claude-opus-5-5".into()),
        };
        let start = Choice {
            cli: None,
            model: Some("anthropic/claude-fable-5-1".into()),
        };
        assert_eq!(
            pick(&state, Some(&repo), Some(&profile), &[]).unwrap().1.as_deref(),
            Some("claude-opus-5-5")
        );
        assert_eq!(
            pick(&state, Some(&repo), Some(&profile), &[&start])
                .unwrap()
                .1
                .as_deref(),
            Some("anthropic/claude-fable-5-1")
        );
        let wrong = Choice {
            cli: None,
            model: Some("openai/gpt-5".into()),
        };
        assert!(
            pick(&state, Some(&repo), None, &[&wrong]).is_err(),
            "a model the cli cannot run fails at start"
        );
    }

    fn choice(cli: Option<&str>, model: Option<&str>) -> Choice {
        Choice {
            cli: cli.map(String::from),
            model: model.map(String::from),
        }
    }

    fn write_settings(dir: &Path, text: &str) {
        std::fs::create_dir_all(dir).unwrap();
        std::fs::write(dir.join("settings.json"), text).unwrap();
    }

    #[test]
    fn a_profiles_own_cli_wins_unless_forcecli_is_on() {
        let state = scratch("force-off-state");
        write_settings(&state, r#"{"cli": "kiro", "model": "claude-haiku-5.5"}"#);
        let profile = choice(Some("claude"), Some("claude-opus-5-5"));
        assert_eq!(
            pick(&state, None, Some(&profile), &[]).unwrap(),
            (Cli::Claude, Some("claude-opus-5-5".into()))
        );
        write_settings(
            &state,
            r#"{"cli": "kiro", "model": "claude-haiku-5.5", "forceCli": false}"#,
        );
        assert_eq!(
            pick(&state, None, Some(&profile), &[]).unwrap().0,
            Cli::Claude,
            "forceCli false forces nothing"
        );
    }

    #[test]
    fn forcecli_puts_the_chosen_cli_and_model_over_a_profiles() {
        let state = scratch("force-on-state");
        write_settings(
            &state,
            r#"{"cli": "kiro", "model": "claude-haiku-5.5", "forceCli": true}"#,
        );
        let profile = choice(Some("claude"), Some("claude-opus-5-5"));
        assert_eq!(
            pick(&state, None, Some(&profile), &[]).unwrap(),
            (Cli::Kiro, Some("claude-haiku-5.5".into()))
        );
        // A Profile that names only a model is put aside too.
        let model_only = choice(None, Some("claude-opus-5-5"));
        assert_eq!(
            pick(&state, None, Some(&model_only), &[]).unwrap(),
            (Cli::Kiro, Some("claude-haiku-5.5".into()))
        );
    }

    #[test]
    fn forcecli_with_a_cli_but_no_model_runs_the_clis_own_default() {
        let state = scratch("force-cli-only");
        write_settings(&state, r#"{"cli": "kiro", "forceCli": true}"#);
        // Claude's model name would be refused by Kiro, so it must not come from the Profile.
        let profile = choice(Some("claude"), Some("anthropic/claude-opus-5-5"));
        assert_eq!(pick(&state, None, Some(&profile), &[]).unwrap(), (Cli::Kiro, None));
    }

    #[test]
    fn forcecli_without_a_cli_forces_nothing() {
        let state = scratch("force-no-cli");
        write_settings(&state, r#"{"model": "claude-haiku-5-5", "forceCli": true}"#);
        let profile = choice(Some("claude"), Some("claude-opus-5-5"));
        assert_eq!(
            pick(&state, None, Some(&profile), &[]).unwrap(),
            (Cli::Claude, Some("claude-opus-5-5".into()))
        );
    }

    #[test]
    fn what_is_picked_for_one_agent_beats_forcecli() {
        let state = scratch("force-picked");
        write_settings(
            &state,
            r#"{"cli": "kiro", "model": "claude-haiku-5.5", "forceCli": true}"#,
        );
        let profile = choice(Some("claude"), Some("claude-opus-5-5"));
        let picked = choice(Some("claude"), Some("claude-sonnet-5-5"));
        assert_eq!(
            pick(&state, None, Some(&profile), &[&picked]).unwrap(),
            (Cli::Claude, Some("claude-sonnet-5-5".into()))
        );
        // A bad pair fails here, before a worktree is made.
        let bad = choice(None, Some("anthropic/claude-opus-5-5"));
        assert!(pick(&state, None, Some(&profile), &[&bad]).is_err());
    }

    #[test]
    fn a_repos_forcecli_is_over_the_humans() {
        let state = scratch("force-repo-state");
        let repo = scratch("force-repo-repo");
        let profile = choice(Some("claude"), Some("claude-opus-5-5"));
        write_settings(&state, r#"{"cli": "kiro", "forceCli": true}"#);
        write_settings(&repo.join(".echo"), r#"{"forceCli": false}"#);
        assert_eq!(
            pick(&state, Some(&repo), Some(&profile), &[]).unwrap().0,
            Cli::Claude,
            "the repo turns the human's force off"
        );
        write_settings(&state, r#"{"cli": "kiro"}"#);
        write_settings(&repo.join(".echo"), r#"{"forceCli": true}"#);
        assert_eq!(
            pick(&state, Some(&repo), Some(&profile), &[]).unwrap(),
            (Cli::Kiro, None),
            "the repo turns it on over the human's cli"
        );
        write_settings(
            &repo.join(".echo"),
            r#"{"cli": "kiro", "model": "claude-sonnet-5.5", "forceCli": true}"#,
        );
        write_settings(
            &state,
            r#"{"cli": "claude", "model": "claude-haiku-5-5", "forceCli": true}"#,
        );
        assert_eq!(
            pick(&state, Some(&repo), Some(&profile), &[]).unwrap(),
            (Cli::Kiro, Some("claude-sonnet-5.5".into())),
            "the repo's cli and model are over the human's"
        );
    }

    #[test]
    fn orchestrator_model_still_applies_under_forcecli() {
        let state = scratch("force-orchestrator");
        write_settings(
            &state,
            r#"{"cli": "kiro", "model": "claude-haiku-5.5", "forceCli": true}"#,
        );
        let orchestrator = choice(None, Some("claude-opus-5.5"));
        let own = Choice::default();
        assert_eq!(
            pick(&state, None, None, &[&orchestrator, &own]).unwrap(),
            (Cli::Kiro, Some("claude-opus-5.5".into()))
        );
    }

    #[test]
    fn forcecli_must_be_true_or_false_in_a_file() {
        let state = scratch("force-not-bool");
        write_settings(&state, r#"{"cli": "kiro", "forceCli": "yes"}"#);
        let err = pick(&state, None, None, &[]).unwrap_err().to_string();
        assert!(err.contains("forceCli must be true or false"), "{err}");
    }

    #[test]
    fn a_recovered_agent_follows_forcecli_over_its_profile() {
        let state = scratch("force-recover");
        write_settings(&state, r#"{"cli": "kiro", "forceCli": true}"#);
        let profile = choice(Some("claude"), None);
        assert_eq!(recovered(&state, None, Some(&profile), &[]), Cli::Kiro);
        let picked = choice(Some("claude"), None);
        assert_eq!(recovered(&state, None, Some(&profile), &[&picked]), Cli::Claude);
        write_settings(&state, r#"{"cli": "kiro"}"#);
        assert_eq!(recovered(&state, None, Some(&profile), &[]), Cli::Claude);
    }

    #[test]
    fn an_orchestrator_starts_with_its_own_model_and_effort_and_keeps_them_on_resume() {
        let hub = Path::new("/echo");
        let start = Start {
            title: "echo: repo".into(),
            model: Some("anthropic/claude-opus-5-5".into()),
            effort: Some("high".into()),
            session_id: "s1".into(),
            ..Start::default()
        };
        let args = Cli::Claude.args(hub, &start).unwrap().join(" ");
        assert!(args.contains("--model claude-opus-5-5"), "{args}");
        assert!(args.contains("--effort high"), "{args}");
        let resumed = Cli::Claude
            .args(hub, &Start { resume: true, ..start })
            .unwrap()
            .join(" ");
        assert!(
            resumed.contains("--effort high") && resumed.contains("--model claude-opus-5-5"),
            "{resumed}"
        );
    }

    #[test]
    fn a_worker_runs_unprompted_with_its_hooks_and_resumes_by_id() {
        let hub = Path::new("/echo");
        let start = Start {
            title: "lee: run tests".into(),
            prompt: "contract".into(),
            dirs: vec![PathBuf::from("/echo"), PathBuf::from("/state/memory")],
            model: Some("anthropic/claude-haiku-5-5".into()),
            effort: Some("low".into()),
            tools: vec!["Bash".into(), "Read".into()],
            worker: true,
            session_id: "s1".into(),
            first: Some("-run the tests".into()),
            ..Start::default()
        };
        let args = Cli::Claude.args(hub, &start).unwrap().join(" ");
        assert_eq!(
            args,
            "-n lee: run tests --model claude-haiku-5-5 --permission-mode auto --settings /echo/settings/worker.json \
             --disallowedTools AskUserQuestion --add-dir /echo --add-dir /state/memory --effort low --tools Bash,Read,ToolSearch \
             --append-system-prompt contract --session-id s1 -- -run the tests"
        );
        let resumed = Start {
            resume: true,
            first: None,
            extra: vec!["--model".into(), "x".into()],
            ..start
        };
        let args = Cli::Claude.args(hub, &resumed).unwrap();
        assert_eq!(
            args.iter().filter(|a| *a == "--model").count(),
            1,
            "the human's --model wins"
        );
        assert!(args.ends_with(&["--resume".to_string(), "s1".to_string()]));
    }

    #[test]
    fn codex_gets_its_prompt_and_hooks_inline_and_resumes_by_its_own_id() {
        let start = Start {
            title: "lee: run tests".into(),
            prompt: "Say \"done\"\nthen stop".into(),
            dirs: vec![PathBuf::from("/echo")],
            model: Some("openai/gpt-5.6-terra".into()),
            effort: Some("low".into()),
            worker: true,
            session_id: "s1".into(),
            first: Some("run the tests".into()),
            ..Start::default()
        };
        let args = Cli::Codex.args(Path::new("/echo"), &start).unwrap();
        let has = |a: &str| args.iter().any(|arg| arg == a);
        assert_eq!(args[..2], ["-m", "gpt-5.6-terra"]);
        assert!(has("--dangerously-bypass-hook-trust") && has("workspace-write") && has("on-request"));
        assert!(has(
            r#"hooks.SessionStart=[{hooks=[{type="command",command="echoctl notify",timeout=10}]}]"#
        ));
        assert!(has(
            r#"hooks.Stop=[{hooks=[{type="command",command="echoctl notify",timeout=10}]}]"#
        ));
        assert!(
            !args.iter().any(|a| a.contains("PermissionRequest")),
            "prompts are read from the screen"
        );
        assert!(has(r#"developer_instructions="Say \"done\"\nthen stop""#));
        assert!(has(r#"model_reasoning_effort="low""#));
        assert!(args.ends_with(&["--".to_string(), "run the tests".to_string()]));
        let resumed = Cli::Codex
            .args(
                Path::new("/echo"),
                &Start {
                    resume: true,
                    first: None,
                    ..start
                },
            )
            .unwrap();
        assert_eq!(resumed[..2], ["resume", "s1"]);
    }

    fn kiro_worker() -> Start {
        Start {
            prompt: "Contract: report with \"echoctl done\"\nthen stop".into(),
            dirs: vec![PathBuf::from("/echo"), PathBuf::from("/state/memory/")],
            cwd: Some(PathBuf::from("/work/checkout")),
            model: Some("kiro/claude-haiku-5.5".into()),
            effort: Some("low".into()),
            tools: vec![
                "Bash".into(),
                "Read".into(),
                "Edit".into(),
                "Write".into(),
                "ToolSearch".into(),
                "Task".into(),
            ],
            worker: true,
            session_id: "sess_1".into(),
            first: Some("run the tests".into()),
            ..Start::default()
        }
    }

    fn agent_file(home: &Path, args: &[String]) -> String {
        let at = args.iter().position(|a| a == "--agent").unwrap();
        std::fs::read_to_string(home.join("agents").join(format!("{}.md", args[at + 1]))).unwrap()
    }

    /// A Worker's Start as the Member `fields` of naruto's Profile gives it, on a Claude-style
    /// tool list; the prompt is the Profile's role alone, so no state or Lessons are read.
    fn member_worker(fields: &str) -> Start {
        let team = format!(r#"{{"members": [{{"id": "build", "action": "execute", "profile": "naruto"{fields}}}]}}"#);
        let team = crate::team::parse(&team).unwrap();
        let profile = crate::profile::Profile {
            name: "naruto".into(),
            cli: None,
            model: None,
            effort: None,
            tools: vec!["Bash".into(), "Read".into(), "Edit".into()],
            skills: Vec::new(),
            context: Vec::new(),
            role: "You implement.".into(),
            description: String::new(),
            writes: true,
            lessons: true,
        }
        .with_member(&team.members[0]);
        Start {
            prompt: format!("# Your role: naruto\n\n{}", profile.role),
            tools: profile.tools,
            model: None,
            ..kiro_worker()
        }
    }

    #[test]
    fn a_members_tools_reach_claudes_flag_and_kiros_agent_file_and_codex_ignores_them() {
        let overlay = r#", "tools": ["Read", "Grep", "WebFetch"], "instructions": "Only touch src/api.""#;
        let (plain, laid) = (member_worker(""), member_worker(overlay));

        let claude_args = |start: &Start| Cli::Claude.args(Path::new("/echo"), start).unwrap();
        let at = |args: &[String], flag: &str| args.iter().position(|a| a == flag).unwrap();
        let args = claude_args(&laid);
        assert_eq!(args[at(&args, "--tools") + 1], "Read,Grep,WebFetch,ToolSearch");
        let args = claude_args(&plain);
        assert_eq!(args[at(&args, "--tools") + 1], "Bash,Read,Edit,ToolSearch");

        let home = scratch("member-kiro");
        let (plain_args, laid_args) = (kiro(&home, &plain).unwrap(), kiro(&home, &laid).unwrap());
        let file = agent_file(&home, &laid_args);
        assert!(
            file.contains("tools: [\"read\", \"web\"]\n"),
            "Grep has no Kiro tool: {file}"
        );
        assert!(
            file.ends_with("You implement.\n\n# This Team's instructions for you\n\nOnly touch src/api.\n"),
            "{file}"
        );
        assert!(agent_file(&home, &plain_args).contains("tools: [\"shell\", \"read\", \"write\"]\n"));
        assert_ne!(plain_args[3], laid_args[3], "another overlay is another agent file");
        let only_tools = member_worker(r#", "tools": ["Read", "Grep", "WebFetch"]"#);
        assert_ne!(kiro(&home, &only_tools).unwrap()[3], laid_args[3]);
        assert_eq!(
            kiro(&home, &laid).unwrap()[3],
            laid_args[3],
            "the same overlay is the same file"
        );

        let codex = Cli::Codex.args(Path::new("/echo"), &laid).unwrap();
        assert!(!codex.iter().any(|a| a.contains("--tools") || a == "Grep"), "{codex:?}");
    }

    #[test]
    fn kiro_is_named_kiro_and_run_as_kiro_cli() {
        assert_eq!(Cli::parse("kiro").unwrap(), Cli::Kiro);
        assert_eq!(Cli::Kiro.name(), "kiro");
        assert_eq!(Cli::Kiro.program(), "kiro-cli");
        assert_eq!(Cli::Codex.program(), "codex");
        let err = Cli::parse("vim").unwrap_err().to_string();
        assert!(err.contains("claude, codex and kiro"), "{err}");
        let err = Cli::parse("gemini").unwrap_err().to_string();
        assert!(err.contains("claude, codex and kiro"), "{err}");
    }

    #[test]
    fn kiro_takes_its_own_model_ids_bare_or_prefixed_and_refuses_other_providers() {
        assert_eq!(Cli::Kiro.model_arg("claude-sonnet-5.5").unwrap(), "claude-sonnet-5.5");
        assert_eq!(
            Cli::Kiro.model_arg("kiro/claude-sonnet-5.5").unwrap(),
            "claude-sonnet-5.5"
        );
        let err = Cli::Kiro.model_arg("openai/gpt-5").unwrap_err().to_string();
        assert!(
            err.contains("openai") && err.contains("\"openai/gpt-5\"") && err.contains("pick another cli"),
            "{err}"
        );
    }

    #[test]
    fn a_kiro_session_exists_under_either_spelling_of_its_id() {
        let home = scratch("kiro-sessions");
        let bucket = home.join("sessions").join("a44897a43362370a");
        std::fs::create_dir_all(bucket.join("sess_6a2fda8e-84a4")).unwrap();
        std::fs::create_dir_all(home.join("sessions").join("cli")).unwrap();
        std::fs::write(home.join("sessions/cli/sess_old.history"), "").unwrap();
        assert!(kiro_session_exists(&home, "sess_6a2fda8e-84a4"));
        assert!(kiro_session_exists(&home, "6a2fda8e-84a4"));
        assert!(!kiro_session_exists(&home, "sess_other"));
        assert!(!kiro_session_exists(&home, "sess_old.history"));
        assert!(!kiro_session_exists(&home, ""));
        assert!(!kiro_session_exists(&home, "../sessions"));
        assert!(!kiro_session_exists(&scratch("kiro-none"), "sess_6a2fda8e-84a4"));
    }

    #[test]
    fn a_kiro_transcript_is_found_under_either_spelling_and_a_folder_without_one_is_not() {
        let home = scratch("kiro-transcripts");
        let bucket = home.join("sessions").join("a44897a43362370a");
        std::fs::create_dir_all(bucket.join("sess_aaaa-1")).unwrap();
        std::fs::create_dir_all(bucket.join("sess_bbbb-2")).unwrap();
        std::fs::write(bucket.join("sess_bbbb-2/messages.jsonl"), "{}\n").unwrap();
        assert_eq!(
            kiro_transcript_in(&home, "sess_aaaa-1"),
            None,
            "a folder holds a turn only once it has the file"
        );
        let found = Some(bucket.join("sess_bbbb-2/messages.jsonl"));
        assert_eq!(kiro_transcript_in(&home, "sess_bbbb-2"), found);
        assert_eq!(kiro_transcript_in(&home, "bbbb-2"), found);
        assert_eq!(kiro_transcript_in(&home, "../sessions"), None);
        assert_eq!(kiro_transcript_in(&scratch("kiro-no-transcripts"), "sess_bbbb-2"), None);
    }

    #[test]
    fn a_new_kiro_orchestrator_gets_an_agent_file_with_its_folders_its_echoctl_rules_and_the_session_hook() {
        let home = scratch("kiro-orchestrator");
        let start = Start {
            prompt: "You are the Orchestrator.".into(),
            dirs: vec![PathBuf::from("/echo"), PathBuf::from("/state/memory")],
            cwd: Some(PathBuf::from("/work/repo")),
            model: Some("claude-opus-5.5".into()),
            effort: Some("high".into()),
            plugins: vec![PathBuf::from("/echo/mod")],
            title: "echo: repo".into(),
            first: Some("plan the work".into()),
            ..Start::default()
        };
        let args = kiro(&home, &start).unwrap();
        assert_eq!(args[..4], ["chat", "--v3", "--agent", args[3].as_str()]);
        assert!(
            args[3].starts_with("echo-") && args[3].len() == "echo-".len() + 16,
            "{args:?}"
        );
        assert_eq!(
            args[4..],
            [
                "--model",
                "claude-opus-5.5",
                "--effort",
                "high",
                "--trust-workspace",
                "plan the work"
            ]
        );
        let file = agent_file(&home, &args);
        assert!(
            file.starts_with(&format!("---\nname: {}\ndescription: Echo orchestrator\n", args[3])),
            "{file}"
        );
        assert!(
            file.contains("model: \"claude-opus-5.5\"\n") && file.contains("tools: [\"*\"]\n"),
            "{file}"
        );
        assert!(file.contains(
            "    - capability: fs_read\n      match: [\"/echo/**\", \"/state/memory/**\", \"/work/repo/**\"]\n      effect: allow\n"
        ));
        assert!(file.contains("    - capability: fs_write\n      match: [\"/echo/**\", \"/state/memory/**\"]\n"));
        assert!(
            file.contains("    - capability: shell\n      match: [\"echoctl wait *\"")
                && file.contains("effect: deny\n"),
            "{file}"
        );
        assert!(!file.contains("trigger: Stop"), "{file}");
        assert!(file
            .contains("trigger: SessionStart\n    action:\n      type: command\n      command: \"echoctl notify\"\n"));
        assert!(file.ends_with("---\n\nYou are the Orchestrator.\n"), "{file}");
        assert!(
            !file.contains("/echo/mod") && !file.contains("echo: repo"),
            "plugins and title are ignored"
        );
    }

    #[test]
    fn a_kiro_worker_works_in_its_checkout_and_may_not_do_the_destructive_things() {
        let home = scratch("kiro-worker");
        let args = kiro(&home, &kiro_worker()).unwrap();
        let file = agent_file(&home, &args);
        assert!(
            file.contains("description: Echo worker\n") && file.contains("model: \"claude-haiku-5.5\"\n"),
            "{file}"
        );
        assert!(
            file.contains("tools: [\"shell\", \"read\", \"write\"]\n"),
            "ToolSearch and Task have no Kiro tool: {file}"
        );
        assert!(file.contains("    - capability: fs_read\n      match: [\"**\"]\n      effect: allow\n"));
        assert!(file.contains(
            "    - capability: fs_write\n      match: [\"/work/checkout/**\", \"/echo/**\", \"/state/memory/**\"]\n      effect: allow\n"
        ));
        assert!(file.contains("    - capability: shell\n      match: [\"*\", \"**\"]\n      effect: allow\n"));
        for denied in [
            "rm -rf *",
            "rm -fr *",
            "git reset --hard*",
            "sudo *",
            "curl * | sh",
            "curl * | bash",
            "wget * | sh",
            "wget * | bash",
        ] {
            assert!(file.contains(&format!("\"{denied}\"")), "{denied}: {file}");
        }
        assert!(file.contains("effect: deny\n"));
        for trigger in ["SessionStart", "Stop"] {
            assert!(
                file.contains(&format!(
                    "trigger: {trigger}\n    action:\n      type: command\n      command: \"echoctl notify\""
                )),
                "{trigger}: {file}"
            );
        }
        assert!(
            !file.contains("HUB_WORKER"),
            "Kiro's hooks inherit HUB_WORKER and HUB_AGENT"
        );
        assert!(
            file.ends_with("---\n\nContract: report with \"echoctl done\"\nthen stop\n"),
            "{file}"
        );
        assert_eq!(
            args[4..],
            [
                "--model",
                "claude-haiku-5.5",
                "--effort",
                "low",
                "--trust-workspace",
                "run the tests"
            ]
        );
    }

    #[test]
    fn a_kiro_session_without_a_prompt_or_folders_gets_no_rules() {
        let home = scratch("kiro-plain");
        let args = kiro(&home, &Start::default()).unwrap();
        let file = agent_file(&home, &args);
        assert!(
            file.contains("description: Echo session\n") && !file.contains("permissions") && !file.contains("model:"),
            "{file}"
        );
        assert_eq!(args[4..], ["--trust-workspace"]);
    }

    fn kiro_orchestrator() -> Start {
        Start {
            prompt: "You are the Orchestrator.\n".into(),
            dirs: vec![PathBuf::from("/echo"), PathBuf::from("/state/memory/")],
            cwd: Some(PathBuf::from("/work/checkout")),
            ..Start::default()
        }
    }

    fn rule_lines(rules: &[KiroRule]) -> Vec<String> {
        rules
            .iter()
            .map(|rule| format!("{} {} {}", rule.effect, rule.capability, rule.globs.join(" | ")))
            .collect()
    }

    #[test]
    fn a_kiro_orchestrator_runs_echoctl_and_reads_its_checkout_without_a_prompt() {
        let rules = rule_lines(&kiro_rules(&kiro_orchestrator()));
        assert_eq!(rules.len(), 4, "{rules:?}");
        assert_eq!(
            rules[0], "allow fs_read /echo/** | /state/memory/** | /work/checkout/**",
            "the checkout is where its shell calls run: without it each call prompts a second time"
        );
        assert_eq!(rules[1], "allow fs_write /echo/** | /state/memory/**");
        let shell = &rules[2];
        for command in [
            "wait", "worker", "reply", "brief", "inbox", "status", "sessions", "profile", "ui",
        ] {
            assert!(shell.contains(&format!("echoctl {command} *")), "{command}: {shell}");
        }
        assert!(shell.starts_with("allow shell "), "{shell}");
        assert!(
            !shell
                .split(" | ")
                .any(|glob| glob.starts_with('*') || glob == "echoctl *"),
            "no bare glob: it may also match a chained command: {shell}"
        );
        assert!(
            !shell.contains("echoctl notify") && !shell.contains("echoctl done") && !shell.contains("echoctl ask"),
            "the Worker's commands are not the Orchestrator's: {shell}"
        );
        assert!(rules[3].starts_with("deny shell rm -rf * | rm -fr * | git reset --hard* | sudo * |"));
        let worker = rule_lines(&kiro_rules(&kiro_worker()));
        assert_eq!(rules[3], *worker.last().unwrap(), "the Worker's deny list, unchanged");
    }

    #[test]
    fn a_kiro_orchestrator_without_a_checkout_or_folders_still_runs_echoctl() {
        let bare = Start {
            cwd: None,
            dirs: Vec::new(),
            ..kiro_orchestrator()
        };
        let rules = rule_lines(&kiro_rules(&bare));
        assert_eq!(rules.len(), 2, "no fs_read or fs_write for no folder: {rules:?}");
        assert!(rules[0].starts_with("allow shell echoctl wait *"), "{rules:?}");
        assert!(rules[1].starts_with("deny shell "), "{rules:?}");
        let no_dirs = Start {
            dirs: Vec::new(),
            ..kiro_orchestrator()
        };
        let rules = rule_lines(&kiro_rules(&no_dirs));
        assert_eq!(rules[0], "allow fs_read /work/checkout/**");
        assert!(rules.iter().all(|rule| !rule.contains("fs_write")), "{rules:?}");
    }

    #[test]
    fn a_normal_kiro_session_and_a_worker_keep_the_rules_they_had() {
        let normal = Start {
            cwd: Some(PathBuf::from("/work/checkout")),
            dirs: vec![PathBuf::from("/echo"), PathBuf::from("/state/memory/")],
            ..Start::default()
        };
        assert_eq!(
            rule_lines(&kiro_rules(&normal)),
            [
                "allow fs_read /echo/** | /state/memory/**",
                "allow fs_write /echo/** | /state/memory/**"
            ],
            "no checkout read, no shell rule"
        );
        assert!(kiro_rules(&Start::default()).is_empty());
        assert_eq!(
            rule_lines(&kiro_rules(&kiro_worker())),
            [
                "allow fs_read **",
                "allow fs_write /work/checkout/** | /echo/** | /state/memory/**",
                "allow shell * | **",
                "deny shell rm -rf * | rm -fr * | git reset --hard* | sudo * | curl * | sh | curl * | bash | wget * | sh | wget * | bash"
            ]
        );
    }

    #[test]
    fn a_kiro_orchestrator_file_carries_the_echoctl_rules() {
        let home = scratch("kiro-orch-rules");
        let args = kiro(&home, &kiro_orchestrator()).unwrap();
        let file = agent_file(&home, &args);
        assert!(file.contains("description: Echo orchestrator\n"), "{file}");
        assert!(file.contains(
            "    - capability: shell\n      match: [\"echoctl wait *\", \"echoctl worker *\", \"echoctl reply *\""
        ));
        assert!(file.contains("    - capability: shell\n      match: [\"rm -rf *\""));
        assert!(file.contains("effect: deny\n"));
    }

    #[test]
    fn only_a_kiro_worker_needs_its_notes_before_it_is_made() {
        let missing = scratch("notes-check-missing");
        let err = Cli::Kiro.check_worker_notes(&missing).unwrap_err().to_string();
        assert!(err.contains("kiro-notes.md"), "{err}");
        assert!(Cli::Claude.check_worker_notes(&missing).is_ok());
        assert!(Cli::Codex.check_worker_notes(&missing).is_ok());
        let hub = hub_with_notes("notes-check-ok", NOTES);
        assert!(Cli::Kiro.check_worker_notes(&hub).is_ok());
        let orchestrator_only = hub_with_notes("notes-check-no-worker", "## Orchestrator\nx\n");
        let err = Cli::Kiro
            .check_worker_notes(&orchestrator_only)
            .unwrap_err()
            .to_string();
        assert!(err.contains("## Worker"), "{err}");
    }

    #[test]
    fn a_kiro_resume_names_the_session_and_puts_the_humans_arguments_before_the_message() {
        let home = scratch("kiro-resume");
        plant_kiro_session(&home, "sess_1", true);
        let start = Start {
            resume: true,
            first: Some("carry on".into()),
            extra: vec!["--model".into(), "auto".into()],
            ..kiro_worker()
        };
        let args = kiro(&home, &start).unwrap();
        assert_eq!(
            args[4..],
            [
                "--effort",
                "low",
                "--trust-workspace",
                "--resume-id",
                "sess_1",
                "--model",
                "auto",
                "carry on"
            ],
            "the human's --model wins"
        );
    }

    fn plant_kiro_session(home: &Path, dir: &str, with_history: bool) {
        let session = home.join("sessions").join("a44897a43362370a").join(dir);
        std::fs::create_dir_all(&session).unwrap();
        if with_history {
            std::fs::write(session.join("messages.jsonl"), "{}\n").unwrap();
        }
    }

    #[test]
    fn a_kiro_session_with_no_history_is_started_afresh_not_resumed() {
        // `--resume-id` on an id Kiro holds nothing for opens a plain session on Kiro's default
        // agent and model, with none of the Task (docs/bugs/0070).
        let resumes = |home: &Path| {
            let start = Start {
                resume: true,
                first: Some("carry on".into()),
                ..kiro_worker()
            };
            let args = kiro(home, &start).unwrap();
            assert_eq!(args.last().unwrap(), "carry on", "the message is sent either way");
            assert!(args.contains(&"--agent".to_string()), "still this agent: {args:?}");
            args.contains(&"--resume-id".to_string())
        };
        assert!(!resumes(&scratch("kiro-no-session")), "nothing on disk");
        let folder_only = scratch("kiro-folder-only");
        plant_kiro_session(&folder_only, "sess_1", false);
        assert!(
            !resumes(&folder_only),
            "the folder exists from the TUI's start, before any turn"
        );
        let held = scratch("kiro-held");
        plant_kiro_session(&held, "sess_1", true);
        assert!(resumes(&held));
        let bare = scratch("kiro-held-bare");
        plant_kiro_session(&bare, "1", true);
        assert!(resumes(&bare), "either spelling of the id");
    }

    #[test]
    fn a_first_message_starting_with_a_dash_is_not_left_to_be_read_as_an_option() {
        let home = scratch("kiro-dash");
        let start = Start {
            first: Some("-d sess_1: delete it".into()),
            ..Start::default()
        };
        let args = kiro(&home, &start).unwrap();
        assert_eq!(args.last().unwrap(), "Message: -d sess_1: delete it");
        assert!(
            !args.contains(&"--".to_string()),
            "-- loses the message in the interactive TUI"
        );
        let plain = kiro(
            &home,
            &Start {
                first: Some("go -fast".into()),
                ..Start::default()
            },
        )
        .unwrap();
        assert_eq!(plain.last().unwrap(), "go -fast");
    }

    #[test]
    fn the_same_kiro_start_names_and_keeps_one_agent_file_and_another_prompt_gets_another() {
        let home = scratch("kiro-names");
        let first = kiro(&home, &kiro_worker()).unwrap();
        let path = home.join("agents").join(format!("{}.md", first[3]));
        let marker = "kept as it was\n";
        std::fs::write(&path, marker).unwrap();
        let again = kiro(&home, &kiro_worker()).unwrap();
        assert_eq!(first[3], again[3]);
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            marker,
            "an existing file is not rewritten"
        );
        let other = kiro(
            &home,
            &Start {
                prompt: "another contract".into(),
                ..kiro_worker()
            },
        )
        .unwrap();
        assert_ne!(first[3], other[3]);
        let mut names: Vec<_> = std::fs::read_dir(home.join("agents"))
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        assert_eq!(names.len(), 2, "no temp file is left: {names:?}");
        assert!(
            names.iter().all(|n| n.starts_with("echo-") && n.ends_with(".md")),
            "{names:?}"
        );
        assert_eq!(
            fnv1a("hello"),
            0xa430_d846_80aa_bd0b,
            "the hash is FNV-1a, stable across builds"
        );
    }

    #[test]
    fn a_kiro_model_of_another_provider_fails_the_start_and_writes_nothing() {
        let home = scratch("kiro-badmodel");
        let start = Start {
            model: Some("openai/gpt-5".into()),
            ..Start::default()
        };
        assert!(kiro(&home, &start)
            .unwrap_err()
            .to_string()
            .contains("pick another cli"));
        assert!(!home.join("agents").exists());
    }

    #[test]
    fn each_cli_approves_and_denies_with_its_own_keys() {
        for cli in [Cli::Claude, Cli::Codex, Cli::Kiro] {
            assert_eq!(cli.approve_keys(), &[b"\r".as_slice()], "{cli:?}");
        }
        // Claude and Codex deny with Esc; for Kiro Esc cancels the whole turn, so it moves to "Deny once".
        assert_eq!(Cli::Claude.deny_keys(), &[b"\x1b".as_slice()]);
        assert_eq!(Cli::Codex.deny_keys(), &[b"\x1b".as_slice()]);
        assert_eq!(Cli::Kiro.deny_keys(), &[b"\x1b[B".as_slice(), b"\r".as_slice()]);
    }

    #[test]
    fn kiro_reads_its_own_screens() {
        let permission = include_str!("../tests/fixtures/kiro/permission.txt");
        let done = include_str!("../tests/fixtures/kiro/done.txt");
        let trust = include_str!("../tests/fixtures/kiro/trust.txt");
        assert_eq!(Cli::Kiro.look(permission), screen::Look::PermissionPrompt);
        assert_eq!(Cli::Kiro.look(trust), screen::Look::TrustPrompt);
        assert_eq!(Cli::Kiro.look(done), screen::Look::Idle);
        assert_eq!(
            Cli::Claude.look(permission),
            screen::Look::Idle,
            "Claude's reader ignores Kiro's prompt"
        );
        assert!(Cli::Kiro.prompt_lines(permission).contains("shell → touch y"));
        assert!(Cli::Kiro.turn_ended(done));
        assert_eq!(Cli::Kiro.trust_keys(), &[b"\r".as_slice()]);
    }

    fn hub_with_notes(name: &str, notes: &str) -> PathBuf {
        let hub = scratch(name);
        std::fs::write(hub.join("kiro-notes.md"), notes).unwrap();
        hub
    }

    const NOTES: &str = "# Notes\n\nintro\n\n## Orchestrator\nwait in the foreground\n\n### Keys\ndown enter\n\n## Worker\nset the timeout\n";

    #[test]
    fn a_notes_section_runs_to_the_next_top_heading() {
        assert_eq!(
            notes_section(NOTES, "Orchestrator"),
            Some("wait in the foreground\n\n### Keys\ndown enter")
        );
        assert_eq!(notes_section(NOTES, "Worker"), Some("set the timeout"));
        assert_eq!(notes_section(NOTES, "Normal"), None);
        assert_eq!(notes_section("## Worker \nx", "Worker"), Some("x"));
    }

    #[test]
    fn a_kiro_worker_prompt_ends_with_the_worker_notes_and_an_orchestrator_prompt_with_its_own() {
        let hub = hub_with_notes("notes-roles", NOTES);
        let worker = with_kiro_notes(&hub, &kiro_worker()).unwrap();
        assert_eq!(
            worker.prompt,
            "Contract: report with \"echoctl done\"\nthen stop\n\n# Running on Kiro\n\nset the timeout"
        );
        let orchestrator = Start {
            prompt: "You are the Orchestrator.\n".into(),
            ..Start::default()
        };
        let orchestrator = with_kiro_notes(&hub, &orchestrator).unwrap();
        assert_eq!(
            orchestrator.prompt,
            "You are the Orchestrator.\n\n# Running on Kiro\n\nwait in the foreground\n\n### Keys\ndown enter"
        );
        assert!(!orchestrator.prompt.contains("set the timeout") && !worker.prompt.contains("foreground"));
        let session = with_kiro_notes(&hub, &Start::default()).unwrap();
        assert!(session.prompt.is_empty(), "a Normal session gets no notes");
    }

    #[test]
    fn the_notes_are_in_the_agent_file_and_its_name() {
        let hub = hub_with_notes("notes-file", NOTES);
        let home = scratch("notes-home");
        let args = kiro(&home, &with_kiro_notes(&hub, &kiro_worker()).unwrap()).unwrap();
        assert!(
            agent_file(&home, &args).ends_with("then stop\n\n# Running on Kiro\n\nset the timeout\n"),
            "{}",
            agent_file(&home, &args)
        );
        let plain = kiro(&home, &kiro_worker()).unwrap();
        assert_ne!(args[3], plain[3], "the notes are part of what the name hashes");
        std::fs::write(
            hub.join("kiro-notes.md"),
            NOTES.replace("set the timeout", "set it higher"),
        )
        .unwrap();
        let changed = kiro(&home, &with_kiro_notes(&hub, &kiro_worker()).unwrap()).unwrap();
        assert_ne!(args[3], changed[3]);
    }

    #[test]
    fn claude_and_codex_prompts_do_not_carry_the_kiro_notes() {
        let hub = hub_with_notes("notes-others", NOTES);
        let worker = Start {
            model: None,
            ..kiro_worker()
        };
        let claude = Cli::Claude.args(&hub, &worker).unwrap();
        assert!(claude.contains(&"Contract: report with \"echoctl done\"\nthen stop".to_string()));
        let codex = Cli::Codex.args(&hub, &worker).unwrap().join(" ");
        assert!(!codex.contains("Running on Kiro") && !claude.join(" ").contains("Running on Kiro"));
    }

    #[test]
    fn a_kiro_start_without_its_notes_fails_before_anything_is_written() {
        let missing = scratch("notes-missing");
        let err = with_kiro_notes(&missing, &kiro_worker()).unwrap_err().to_string();
        assert!(err.contains("kiro-notes.md"), "{err}");
        let hub = hub_with_notes("notes-no-worker", "## Orchestrator\nx\n");
        let err = with_kiro_notes(&hub, &kiro_worker()).unwrap_err().to_string();
        assert!(err.contains("## Worker"), "{err}");
        assert!(
            with_kiro_notes(&hub, &Start::default()).is_ok(),
            "a Normal session needs no notes"
        );
    }

    #[test]
    fn the_shipped_notes_tell_each_role_how_to_wait_and_to_deny() {
        let notes = std::fs::read_to_string(paths::hub_dir().join("kiro-notes.md")).unwrap();
        let orchestrator = notes_section(&notes, "Orchestrator").unwrap();
        let worker = notes_section(&notes, "Worker").unwrap();
        assert!(orchestrator.contains("command: echoctl wait --timeout 170\n  timeout: 200000"));
        assert!(orchestrator.contains("echoctl worker key <w> down enter"));
        assert!(worker.contains("command: echoctl ask \"<question>\"\ntimeout: 600000"));
        assert!(!worker.contains("echoctl wait"), "Workers do not wait");
    }

    #[test]
    fn a_recovered_agent_comes_back_as_the_cli_it_was_stored_with() {
        let state = scratch("recover-state");
        let repo = scratch("recover-repo");
        let stored = |name: &str| Choice {
            cli: Some(name.into()),
            model: None,
        };
        assert_eq!(recovered(&state, Some(&repo), None, &[&stored("kiro")]), Cli::Kiro);
        assert_eq!(recovered(&state, Some(&repo), None, &[&stored("codex")]), Cli::Codex);
        // A model that Kiro refuses made `pick` fail, and the agent read as claude.
        let odd = Choice {
            cli: Some("kiro".into()),
            model: Some("anthropic/claude-opus-5-5".into()),
        };
        assert!(pick(&state, Some(&repo), None, &[&odd]).is_err());
        assert_eq!(recovered(&state, Some(&repo), None, &[&odd]), Cli::Kiro);
        // The stored level wins over the files, and an unreadable file does not hide it.
        std::fs::write(state.join("settings.json"), r#"{"cli": "codex"}"#).unwrap();
        assert_eq!(recovered(&state, Some(&repo), None, &[&stored("kiro")]), Cli::Kiro);
        assert_eq!(recovered(&state, Some(&repo), None, &[&Choice::default()]), Cli::Codex);
        std::fs::create_dir_all(repo.join(".echo")).unwrap();
        std::fs::write(repo.join(".echo/settings.json"), r#"{"cli": "kiro"}"#).unwrap();
        assert_eq!(
            recovered(&state, Some(&repo), None, &[]),
            Cli::Kiro,
            "the repo's level is over the human's"
        );
        std::fs::write(state.join("settings.json"), "not json").unwrap();
        assert_eq!(recovered(&state, None, None, &[&stored("kiro")]), Cli::Kiro);
        // Nothing names a cli, or one Echo does not run: claude, as before.
        assert_eq!(recovered(&state, None, None, &[&Choice::default()]), Cli::Claude);
        assert_eq!(recovered(&state, None, None, &[&stored("vim")]), Cli::Claude);
    }

    #[test]
    fn a_kiro_orchestrator_is_refused_an_anthropic_model_and_takes_its_own() {
        let state = scratch("kiro-orchestrator-model");
        std::fs::write(state.join("settings.json"), r#"{"cli": "kiro"}"#).unwrap();
        let level = |model: &str| Choice {
            cli: None,
            model: Some(model.into()),
        };
        let err = pick(&state, None, None, &[&level("anthropic/claude-opus-5-5")])
            .unwrap_err()
            .to_string();
        assert!(err.contains("anthropic") && err.contains("pick another cli"), "{err}");
        assert_eq!(
            pick(&state, None, None, &[&level("claude-opus-5.5")]).unwrap(),
            (Cli::Kiro, Some("claude-opus-5.5".into()))
        );
        assert_eq!(
            pick(&state, None, None, &[]).unwrap(),
            (Cli::Kiro, None),
            "Kiro's own default model"
        );
    }

    #[test]
    fn every_kiro_screen_at_the_input_box_reads_as_idle() {
        // `watch` raises an idle blocker for a Worker that reads Idle and stays unchanged for 60 s.
        for screen in [
            include_str!("../tests/fixtures/kiro/idle.txt"),
            include_str!("../tests/fixtures/kiro/done.txt"),
            include_str!("../tests/fixtures/kiro/waiting.txt"),
            include_str!("../tests/fixtures/kiro/allowed-once.txt"),
        ] {
            assert_eq!(Cli::Kiro.look(screen), screen::Look::Idle, "{screen}");
        }
        assert_eq!(
            Cli::Kiro.look(include_str!("../tests/fixtures/kiro/working.txt")),
            screen::Look::Working
        );
    }
}

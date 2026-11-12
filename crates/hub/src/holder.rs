//! The terminal holder: a small process that owns every agent, Worker, and shell PTY, so they
//! outlive the Hub Daemon. It spawns, drains, resizes, and kills, and keeps the last MiB of each
//! terminal's output for a daemon that comes back; it parses nothing.
//!
//! The daemon opens one connection per terminal and sends one JSON line (`spawn`, `adopt`, `list`,
//! or `quit`); the holder answers with one JSON line, after `adopt` the tail's bytes, and then
//! both sides speak frames: `[kind u8][len u32 big-endian][payload]`.

use std::collections::{HashMap, VecDeque};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use portable_pty::{native_pty_system, ChildKiller, CommandBuilder, MasterPty, PtySize};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::paths;

/// Bumped when the requests or frames change; a holder of another version is replaced only
/// once it holds no terminals.
pub const VERSION: u64 = 1;
/// Output kept per terminal for a daemon that adopts it.
const TAIL: usize = 1024 * 1024;
/// A holder with no terminals for this long exits; the daemon starts another when it needs one.
const IDLE_EXIT: Duration = Duration::from_secs(30);

/// Holder to daemon: output bytes, then one exit.
pub const OUTPUT: u8 = 0;
pub const EXIT: u8 = 1;
/// Daemon to holder: input bytes, a resize (rows, cols as u16 big-endian), a kill.
pub const INPUT: u8 = 0;
pub const RESIZE: u8 = 1;
pub const KILL: u8 = 2;

#[derive(Serialize, Deserialize)]
pub struct SpawnRequest {
    pub key: String,
    pub program: String,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    pub env: Vec<(String, String)>,
    pub env_remove: Vec<String>,
    pub rows: u16,
    pub cols: u16,
}

/// What `adopt` says about a held terminal before its tail.
#[derive(Serialize, Deserialize)]
pub struct Adopted {
    pub rows: u16,
    pub cols: u16,
    pub age_ms: u64,
    pub tail: usize,
}

pub fn write_frame(out: &mut impl Write, kind: u8, payload: &[u8]) -> std::io::Result<()> {
    let mut frame = Vec::with_capacity(5 + payload.len());
    frame.push(kind);
    frame.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    frame.extend_from_slice(payload);
    out.write_all(&frame)?;
    out.flush()
}

/// The next frame, or None at the end of the stream.
pub fn read_frame(input: &mut impl Read) -> std::io::Result<Option<(u8, Vec<u8>)>> {
    let mut head = [0u8; 5];
    match input.read_exact(&mut head) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e),
    }
    let len = u32::from_be_bytes([head[1], head[2], head[3], head[4]]) as usize;
    let mut payload = vec![0u8; len];
    input.read_exact(&mut payload)?;
    Ok(Some((head[0], payload)))
}

pub fn socket() -> PathBuf {
    paths::state_dir().join("holder.sock")
}

// ---- The daemon's side ----

/// A connection to this state folder's holder, starting one when none answers.
pub fn connect() -> Result<UnixStream> {
    if let Ok(stream) = UnixStream::connect(socket()) {
        return Ok(stream);
    }
    start()?;
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match UnixStream::connect(socket()) {
            Ok(stream) => return Ok(stream),
            Err(_) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(50)),
            Err(e) => return Err(e).context("reaching the terminal holder"),
        }
    }
}

/// Starts `echoctl holder` in its own session, so it outlives the daemon and its terminal.
fn start() -> Result<()> {
    let log = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(paths::state_dir().join("holder.log"))?;
    let mut command = std::process::Command::new(std::env::current_exe()?);
    command
        .arg("holder")
        .current_dir(paths::state_dir())
        .stdin(std::process::Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log);
    unsafe {
        command.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    command.spawn().context("starting the terminal holder")?;
    Ok(())
}

/// Sends one request line and reads the holder's one-line answer.
pub fn request(stream: &UnixStream, mut request: Value) -> Result<(Value, BufReader<UnixStream>)> {
    request["v"] = json!(VERSION);
    let mut out = stream.try_clone()?;
    out.write_all(format!("{request}\n").as_bytes())?;
    out.flush()?;
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut line = String::new();
    reader.read_line(&mut line)?;
    if line.is_empty() {
        bail!("the terminal holder closed the connection");
    }
    let answer: Value = serde_json::from_str(&line).context("bad answer from the terminal holder")?;
    if let Some(error) = answer.get("error").and_then(Value::as_str) {
        bail!("terminal holder: {error}");
    }
    Ok((answer, reader))
}

/// The keys of every terminal the holder keeps; none when no holder runs.
pub fn list() -> Vec<String> {
    let Ok(stream) = UnixStream::connect(socket()) else {
        return Vec::new();
    };
    request(&stream, json!({ "op": "list" }))
        .ok()
        .and_then(|(answer, _)| serde_json::from_value(answer["keys"].clone()).ok())
        .unwrap_or_default()
}

/// Kills every held terminal and stops the holder.
pub fn quit() {
    if let Ok(stream) = UnixStream::connect(socket()) {
        let _ = request(&stream, json!({ "op": "quit" }));
    }
}

// ---- The holder itself ----

struct Held {
    master: Mutex<Box<dyn MasterPty + Send>>,
    writer: Mutex<Box<dyn Write + Send>>,
    killer: Mutex<Box<dyn ChildKiller + Send + Sync>>,
    /// The tail and the daemon's connection under one lock, so an adopting daemon gets the tail
    /// and then every later byte, with no gap and no repeat.
    out: Mutex<Out>,
    size: Mutex<(u16, u16)>,
    started: Instant,
}

struct Out {
    tail: VecDeque<u8>,
    conn: Option<UnixStream>,
    /// Set once the program exited and its output ended.
    exited: bool,
}

#[derive(Default)]
struct Holder {
    held: Mutex<HashMap<String, Arc<Held>>>,
    quitting: AtomicBool,
}

/// `echoctl holder`: serves this state folder until it holds nothing for a while.
pub fn run() -> Result<()> {
    std::fs::create_dir_all(paths::state_dir())?;
    let lock = std::fs::File::create(paths::state_dir().join("holder.lock"))?;
    if unsafe { libc::flock(std::os::fd::AsRawFd::as_raw_fd(&lock), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        bail!("a terminal holder already runs for {}", paths::state_dir().display());
    }
    std::mem::forget(lock);
    let _ = std::fs::remove_file(socket());
    let listener = UnixListener::bind(socket()).with_context(|| format!("binding {}", socket().display()))?;
    std::fs::set_permissions(socket(), std::os::unix::fs::PermissionsExt::from_mode(0o600))?;
    eprintln!("holder {}: listening on {}", std::process::id(), socket().display());
    let holder = Arc::new(Holder::default());

    let idle = Arc::clone(&holder);
    std::thread::spawn(move || {
        let mut empty_since = Instant::now();
        loop {
            std::thread::sleep(Duration::from_secs(1));
            if !idle.held.lock().unwrap().is_empty() {
                empty_since = Instant::now();
            } else if empty_since.elapsed() >= IDLE_EXIT {
                let _ = std::fs::remove_file(socket());
                std::process::exit(0);
            }
        }
    });

    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        let holder = Arc::clone(&holder);
        std::thread::spawn(move || {
            if let Err(error) = holder.serve(stream) {
                eprintln!("holder: {error:#}");
            }
        });
    }
    Ok(())
}

fn answer(stream: &mut UnixStream, value: Value) -> Result<()> {
    stream.write_all(format!("{value}\n").as_bytes())?;
    Ok(stream.flush()?)
}

impl Holder {
    fn serve(self: &Arc<Self>, mut stream: UnixStream) -> Result<()> {
        let mut reader = BufReader::new(stream.try_clone()?);
        let mut line = String::new();
        if reader.read_line(&mut line)? == 0 {
            return Ok(());
        }
        let request: Value = serde_json::from_str(&line).context("bad request line")?;
        let op = request["op"].as_str().unwrap_or_default();
        if op == "list" {
            let keys: Vec<String> = self.held.lock().unwrap().keys().cloned().collect();
            return answer(&mut stream, json!({ "keys": keys, "v": VERSION }));
        }
        if request["v"].as_u64() != Some(VERSION) {
            return answer(
                &mut stream,
                json!({ "error": format!("this holder speaks version {VERSION}") }),
            );
        }
        match op {
            "spawn" => {
                let spawn: SpawnRequest = serde_json::from_value(request)?;
                let key = spawn.key.clone();
                let held = match self.spawn(spawn) {
                    Ok(held) => held,
                    Err(error) => return answer(&mut stream, json!({ "error": format!("{error:#}") })),
                };
                answer(&mut stream, json!({}))?;
                self.attach(&key, &held, stream, reader, None)
            }
            "adopt" => {
                let key = request["key"].as_str().unwrap_or_default().to_string();
                let Some(held) = self.held.lock().unwrap().get(&key).cloned() else {
                    return answer(&mut stream, json!({ "error": format!("no terminal {key}") }));
                };
                let size = *held.size.lock().unwrap();
                let adopted = |tail: usize| Adopted {
                    rows: size.0,
                    cols: size.1,
                    age_ms: held.started.elapsed().as_millis() as u64,
                    tail,
                };
                self.attach(&key, &held, stream, reader, Some(&adopted))
            }
            "quit" => {
                self.quitting.store(true, Ordering::SeqCst);
                for held in self.held.lock().unwrap().values() {
                    let _ = held.killer.lock().unwrap().kill();
                }
                answer(&mut stream, json!({}))?;
                let _ = std::fs::remove_file(socket());
                std::thread::sleep(Duration::from_millis(100));
                std::process::exit(0);
            }
            other => answer(&mut stream, json!({ "error": format!("unknown op {other}") })),
        }
    }

    fn spawn(self: &Arc<Self>, spawn: SpawnRequest) -> Result<Arc<Held>> {
        if self.held.lock().unwrap().contains_key(&spawn.key) {
            bail!("{} is already held", spawn.key);
        }
        let size = PtySize {
            rows: spawn.rows,
            cols: spawn.cols,
            pixel_width: 0,
            pixel_height: 0,
        };
        let pair = native_pty_system().openpty(size).context("opening a PTY")?;
        let mut command = CommandBuilder::new(&spawn.program);
        command.args(&spawn.args);
        command.cwd(&spawn.cwd);
        for key in &spawn.env_remove {
            command.env_remove(key);
        }
        for (key, value) in &spawn.env {
            command.env(key, value);
        }
        let mut child = pair
            .slave
            .spawn_command(command)
            .with_context(|| format!("starting {}", spawn.program))?;
        drop(pair.slave);
        let mut reader = pair.master.try_clone_reader()?;
        let held = Arc::new(Held {
            writer: Mutex::new(pair.master.take_writer()?),
            master: Mutex::new(pair.master),
            killer: Mutex::new(child.clone_killer()),
            out: Mutex::new(Out {
                tail: VecDeque::new(),
                conn: None,
                exited: false,
            }),
            size: Mutex::new((spawn.rows, spawn.cols)),
            started: Instant::now(),
        });
        self.held.lock().unwrap().insert(spawn.key.clone(), Arc::clone(&held));
        let draining = Arc::clone(&held);
        let holder = Arc::clone(self);
        let key = spawn.key;
        std::thread::spawn(move || {
            let mut buf = [0u8; 16 * 1024];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        let mut out = draining.out.lock().unwrap();
                        out.tail.extend(&buf[..n]);
                        let over = out.tail.len().saturating_sub(TAIL);
                        out.tail.drain(..over);
                        if let Some(conn) = out.conn.as_mut() {
                            if write_frame(conn, OUTPUT, &buf[..n]).is_err() {
                                out.conn = None;
                            }
                        }
                    }
                }
            }
            let _ = child.wait();
            let mut out = draining.out.lock().unwrap();
            out.exited = true;
            // A daemon that hears the exit is done with it; otherwise it waits to be adopted.
            if let Some(conn) = out.conn.as_mut() {
                if write_frame(conn, EXIT, &[]).is_ok() {
                    holder.forget(&key, &draining);
                }
            } else if holder.quitting.load(Ordering::SeqCst) {
                holder.forget(&key, &draining);
            }
        });
        Ok(held)
    }

    fn forget(&self, key: &str, held: &Arc<Held>) {
        let mut all = self.held.lock().unwrap();
        if all.get(key).is_some_and(|h| Arc::ptr_eq(h, held)) {
            all.remove(key);
        }
    }

    /// Makes `stream` the terminal's one daemon connection, after the adopt answer and tail when
    /// adopting, and serves its input frames until it closes.
    fn attach(
        &self,
        key: &str,
        held: &Arc<Held>,
        mut stream: UnixStream,
        mut reader: BufReader<UnixStream>,
        adopted: Option<&dyn Fn(usize) -> Adopted>,
    ) -> Result<()> {
        {
            let mut out = held.out.lock().unwrap();
            if let Some(adopted) = adopted {
                let tail: Vec<u8> = out.tail.iter().copied().collect();
                answer(&mut stream, serde_json::to_value(adopted(tail.len()))?)?;
                stream.write_all(&tail)?;
            }
            if out.exited {
                write_frame(&mut stream, EXIT, &[])?;
                drop(out);
                self.forget(key, held);
                return Ok(());
            }
            // A newer daemon's connection replaces an older one's.
            if let Some(old) = out.conn.replace(stream.try_clone()?) {
                let _ = old.shutdown(std::net::Shutdown::Both);
            }
        }
        while let Some((kind, payload)) = read_frame(&mut reader).unwrap_or(None) {
            match kind {
                INPUT => {
                    let mut writer = held.writer.lock().unwrap();
                    let _ = writer.write_all(&payload).and_then(|_| writer.flush());
                }
                RESIZE if payload.len() == 4 => {
                    let rows = u16::from_be_bytes([payload[0], payload[1]]);
                    let cols = u16::from_be_bytes([payload[2], payload[3]]);
                    let _ = held.master.lock().unwrap().resize(PtySize {
                        rows,
                        cols,
                        pixel_width: 0,
                        pixel_height: 0,
                    });
                    *held.size.lock().unwrap() = (rows, cols);
                }
                KILL => {
                    let _ = held.killer.lock().unwrap().kill();
                }
                _ => {}
            }
        }
        // The daemon went away: the terminal keeps running and its output goes to the tail.
        let mut out = held.out.lock().unwrap();
        if let Some(conn) = &out.conn {
            if same_socket(conn, &stream) {
                out.conn = None;
            }
        }
        Ok(())
    }
}

fn same_socket(a: &UnixStream, b: &UnixStream) -> bool {
    use std::os::fd::AsRawFd;
    let ino = |s: &UnixStream| {
        let mut stat: libc::stat = unsafe { std::mem::zeroed() };
        unsafe { libc::fstat(s.as_raw_fd(), &mut stat) };
        stat.st_ino
    };
    ino(a) == ino(b)
}

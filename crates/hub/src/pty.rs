//! One terminal (an agent's, a Worker's, or a shell): its process on a PTY the terminal holder
//! keeps (holder.rs), so it outlives the daemon; its parsed screen; and the clients attached to it.

use std::io::{BufReader, Read};
use std::os::unix::net::UnixStream;
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::Result;
use serde_json::json;

use crate::cli::Cli;
use crate::holder;

pub const ROWS: u16 = 45;
pub const COLS: u16 = 160;
/// Only the visible screen is ever read or redrawn; the attached terminal keeps its own history.
const SCROLLBACK: usize = 0;
/// Output chunks (16 KiB at most) queued for one attached client. A client that falls this far
/// behind, like a stopped `echoctl attach`, is let go rather than held in memory without limit; it
/// attaches again to a fresh screen.
const BACKLOG: usize = 1024;
/// vt100 0.16 panics when a one-row screen wraps a line, so the parsed screen keeps two rows at
/// least even when the terminal itself is one row tall.
const MIN_ROWS: u16 = 2;

pub struct Spawn {
    /// Whose screen it is, so the watcher reads it right.
    pub cli: Cli,
    pub program: String,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    pub env: Vec<(String, String)>,
    /// Inherited variables to drop, e.g. another agent's session markers.
    pub env_remove: Vec<String>,
}

pub struct Live {
    pub id: i64,
    pub cli: Cli,
    /// The holder's connection for this terminal: input, resize, and kill frames go out on it.
    conn: Mutex<UnixStream>,
    parser: Mutex<vt100::Parser>,
    subscribers: Mutex<Vec<SyncSender<Arc<Vec<u8>>>>>,
    /// The blocker kind already reported for the current stretch, cleared when work resumes.
    pub blocker: Mutex<Option<String>>,
    /// Set by `echoctl worker close`, so the exit is not reported as a failure.
    pub closing: AtomicBool,
    /// At its input box while background work it started runs (`Look::Waiting`), as the screen
    /// watcher last saw it.
    pub waiting: AtomicBool,
    /// When work was last typed in for it, so the quiet before that is not read as idling on it.
    pub handed: Mutex<Option<Instant>>,
    alive: AtomicBool,
    started: Instant,
}

impl Live {
    /// Starts the process in the holder under `key` (`w12`, `a3`, `s3`); `on_exit` runs on the
    /// reader thread once its output ends.
    pub fn spawn(key: &str, id: i64, spawn: Spawn, on_exit: impl FnOnce(i64) + Send + 'static) -> Result<Arc<Live>> {
        let request = holder::SpawnRequest {
            key: key.to_string(),
            program: spawn.program,
            args: spawn.args,
            cwd: spawn.cwd,
            env: spawn.env,
            env_remove: spawn.env_remove,
            rows: ROWS,
            cols: COLS,
        };
        let stream = holder::connect()?;
        let mut request = serde_json::to_value(request)?;
        request["op"] = json!("spawn");
        let (_, reader) = holder::request(&stream, request)?;
        let parser = parser(ROWS, COLS);
        Ok(Live::start(
            id,
            spawn.cli,
            stream,
            reader,
            parser,
            Instant::now(),
            on_exit,
        ))
    }

    /// Takes over a terminal the holder kept while no daemon ran, its screen rebuilt from the
    /// holder's tail; None when the holder has no `key`.
    pub fn adopt(
        key: &str,
        id: i64,
        cli: Cli,
        on_exit: impl FnOnce(i64) + Send + 'static,
    ) -> Result<Option<Arc<Live>>> {
        if !holder::list().iter().any(|k| k == key) {
            return Ok(None);
        }
        let stream = holder::connect()?;
        let (answer, mut reader) = holder::request(&stream, json!({ "op": "adopt", "key": key }))?;
        let adopted: holder::Adopted = serde_json::from_value(answer)?;
        let mut tail = vec![0u8; adopted.tail];
        reader.read_exact(&mut tail)?;
        let mut parser = parser(adopted.rows, adopted.cols);
        feed(&mut parser, &tail);
        let started = Instant::now()
            .checked_sub(Duration::from_millis(adopted.age_ms))
            .unwrap_or_else(Instant::now);
        let live = Live::start(id, cli, stream, reader, parser, started, on_exit);
        // The tail may begin mid-screen: one row less and back makes a full-screen program redraw.
        let (rows, cols) = (adopted.rows, adopted.cols);
        if rows > 1 {
            live.resize(rows - 1, cols)?;
            let redraw = Arc::clone(&live);
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_millis(50));
                let _ = redraw.resize(rows, cols);
            });
        }
        Ok(Some(live))
    }

    fn start(
        id: i64,
        cli: Cli,
        stream: UnixStream,
        mut reader: BufReader<UnixStream>,
        parser: vt100::Parser,
        started: Instant,
        on_exit: impl FnOnce(i64) + Send + 'static,
    ) -> Arc<Live> {
        let live = Arc::new(Live {
            id,
            cli,
            conn: Mutex::new(stream),
            parser: Mutex::new(parser),
            subscribers: Mutex::new(Vec::new()),
            blocker: Mutex::new(None),
            closing: AtomicBool::new(false),
            waiting: AtomicBool::new(false),
            handed: Mutex::new(None),
            alive: AtomicBool::new(true),
            started,
        });
        let reading = Arc::clone(&live);
        std::thread::spawn(move || {
            // Output until the exit frame; a holder that went away ends the terminal too.
            while let Ok(Some((kind, bytes))) = holder::read_frame(&mut reader) {
                match kind {
                    holder::OUTPUT => reading.output(&bytes),
                    holder::EXIT => break,
                    _ => {}
                }
            }
            reading.alive.store(false, Ordering::SeqCst);
            reading.subscribers.lock().unwrap().clear();
            on_exit(reading.id);
        });
        live
    }

    /// Hands the bytes to every attached client before parsing them, so they never wait on the
    /// parser; the parser lock is held throughout, so a new subscriber's snapshot and its first
    /// chunk still line up.
    fn output(&self, bytes: &[u8]) {
        let mut parser = self.parser.lock().unwrap();
        let chunk = Arc::new(bytes.to_vec());
        self.subscribers
            .lock()
            .unwrap()
            .retain(|subscriber| subscriber.try_send(Arc::clone(&chunk)).is_ok());
        feed(&mut parser, bytes);
    }

    pub fn is_alive(&self) -> bool {
        self.alive.load(Ordering::SeqCst)
    }

    pub fn age(&self) -> std::time::Duration {
        self.started.elapsed()
    }

    /// The visible screen as plain text.
    pub fn screen(&self) -> String {
        self.parser.lock().unwrap().screen().contents()
    }

    /// Reads the parsed screen itself: its cells, colours, and modes.
    pub fn with_screen<T>(&self, read: impl FnOnce(&vt100::Screen) -> T) -> T {
        read(self.parser.lock().unwrap().screen())
    }

    pub fn write(&self, bytes: &[u8]) -> Result<()> {
        Ok(holder::write_frame(
            &mut *self.conn.lock().unwrap(),
            holder::INPUT,
            bytes,
        )?)
    }

    pub fn resize(&self, rows: u16, cols: u16) -> Result<()> {
        if rows == 0 || cols == 0 {
            return Ok(());
        }
        let mut parser = self.parser.lock().unwrap();
        let mut size = rows.to_be_bytes().to_vec();
        size.extend_from_slice(&cols.to_be_bytes());
        holder::write_frame(&mut *self.conn.lock().unwrap(), holder::RESIZE, &size)?;
        parser.screen_mut().set_size(rows.max(MIN_ROWS), cols);
        Ok(())
    }

    /// The screen as escape codes that redraw it, and every byte of output after it.
    pub fn subscribe(&self) -> (Vec<u8>, Receiver<Arc<Vec<u8>>>) {
        let parser = self.parser.lock().unwrap();
        let (sender, receiver) = mpsc::sync_channel(BACKLOG);
        self.subscribers.lock().unwrap().push(sender);
        (parser.screen().state_formatted(), receiver)
    }

    pub fn kill(&self) {
        let _ = holder::write_frame(&mut *self.conn.lock().unwrap(), holder::KILL, &[]);
    }
}

fn parser(rows: u16, cols: u16) -> vt100::Parser {
    vt100::Parser::new(rows.max(MIN_ROWS), cols, SCROLLBACK)
}

/// Parses `bytes` into the screen. A vt100 panic would poison the parser's lock and stop this
/// terminal's output for good, freezing its program once the holder's buffers fill; the screen
/// starts over blank instead, and the program's next redraw fills it again.
fn feed(parser: &mut vt100::Parser, bytes: &[u8]) {
    if std::panic::catch_unwind(AssertUnwindSafe(|| parser.process(bytes))).is_err() {
        let (rows, cols) = parser.screen().size();
        *parser = vt100::Parser::new(rows, cols, SCROLLBACK);
        eprintln!("hubd: the screen parser failed; the screen starts over");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_parser_panic_starts_the_screen_over() {
        let mut parser = vt100::Parser::new(1, 10, SCROLLBACK);
        feed(&mut parser, b"0123456789abc");
        feed(&mut parser, b"still here");
        assert!(parser.screen().contents().contains("still here"));
    }

    #[test]
    fn a_one_row_terminal_wraps_lines() {
        let mut parser = parser(1, 10);
        parser.process(b"0123456789abc");
        assert!(parser.screen().contents().contains("abc"));
    }
}

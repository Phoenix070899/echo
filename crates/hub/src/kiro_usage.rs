//! Kiro's credits for the usage bar (decisions/features/0078): a short-lived `kiro-cli acp` child
//! is asked `_kiro/account/getUsage`, which needs no chat session and spends no credits.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

/// The name of the limit entry in the `usage` reply.
pub const NAME: &str = "Kiro credits";

/// The whole `acp` conversation, from spawn to the reply, gives up after this long.
const CALL_LIMIT: Duration = Duration::from_secs(60);
/// `kiro-cli whoami` only reads the local login; this is generous.
const WHOAMI_LIMIT: Duration = Duration::from_secs(15);
/// After its stdin closes the child exits by itself in about 0.1 s; this long before it is killed.
const EXIT_GRACE: Duration = Duration::from_secs(2);

/// What one attempt to read the credits came to.
#[derive(Debug, PartialEq)]
pub enum Outcome {
    /// The limit entry for the `usage` reply.
    Reading(Value),
    /// `kiro-cli` is not installed or not signed in: nothing to show, and nothing went wrong.
    Absent,
    /// Anything else: the last good reading stands. The text says why, for a person debugging.
    Failed(String),
    /// The scratch `KIRO_HOME` could not be made, so no child was run: the last good reading stands.
    /// It never falls back to the human's own Kiro home (decisions/features/0078).
    Skipped(String),
}

/// A folder for the child's `KIRO_HOME`, so its log folders do not push the human's own out of
/// `~/.kiro/logs` (Kiro keeps about the newest eleven). The login does not live there.
pub fn scratch_home(parent: &Path) -> std::io::Result<PathBuf> {
    let home = parent.join("kiro-home");
    std::fs::create_dir_all(&home).map(|_| home)
}

/// Reads the credits with `program` (`kiro-cli`), if it is installed and signed in, in a scratch
/// `KIRO_HOME` under `parent`. When that folder cannot be made, nothing is run: one line goes to
/// stderr and the outcome is `Skipped`.
pub fn read(program: &str, parent: &Path) -> Outcome {
    match scratch_home(parent) {
        Ok(home) => read_in(program, &home),
        Err(error) => {
            let why = format!("no scratch KIRO_HOME under {}: {error}", parent.display());
            eprintln!("echo: Kiro credits not read, {why}");
            Outcome::Skipped(why)
        }
    }
}

fn read_in(program: &str, home: &Path) -> Outcome {
    read_within(program, home, CALL_LIMIT)
}

fn read_within(program: &str, home: &Path, limit: Duration) -> Outcome {
    match signed_in(program, home) {
        Ok(true) => {}
        Ok(false) => return Outcome::Absent,
        Err(error) => return Outcome::Failed(format!("{error:#}")),
    }
    match ask(program, home, limit) {
        Ok(entry) => Outcome::Reading(entry),
        Err(error) => Outcome::Failed(format!("{error:#}")),
    }
}

fn kiro_command(program: &str, home: &Path) -> Command {
    let mut command = Command::new(program);
    command.env("KIRO_HOME", home);
    command
}

/// `kiro-cli whoami` exits 0 when signed in and 1 when not; a program that is not there is
/// "not signed in". Only the exit status is read: the output holds an email.
fn signed_in(program: &str, home: &Path) -> Result<bool> {
    let mut command = kiro_command(program, home);
    command
        .arg("whoami")
        .current_dir(std::env::temp_dir())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error).with_context(|| format!("running {program} whoami")),
    };
    let deadline = Instant::now() + WHOAMI_LIMIT;
    loop {
        if let Some(status) = child.try_wait()? {
            return Ok(status.success());
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            bail!("`kiro-cli whoami` took over {} seconds", WHOAMI_LIMIT.as_secs());
        }
        std::thread::sleep(Duration::from_millis(25));
    }
}

/// Spawns `kiro-cli acp`, asks for the usage, and never leaves the child running.
fn ask(program: &str, home: &Path, limit: Duration) -> Result<Value> {
    let mut command = kiro_command(program, home);
    command
        .args(["acp", "--agent-engine", "v3", "--auth-method", "cli"])
        .current_dir(std::env::temp_dir())
        .process_group(0)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let mut child = command.spawn().with_context(|| format!("running {program} acp"))?;
    let stdin = child.stdin.take().context("no stdin")?;
    let stdout = child.stdout.take().context("no stdout")?;
    // The conversation owns the pipes, so stdin is closed when it returns, and the child ends.
    let answer = converse(stdin, stdout, limit);
    end(&mut child);
    answer
}

/// `initialize`, then `_kiro/account/getUsage`, each sent after the previous reply. Notifications
/// and any other line without the request's id are skipped.
fn converse(mut stdin: ChildStdin, stdout: impl std::io::Read + Send + 'static, limit: Duration) -> Result<Value> {
    let (sender, lines) = mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(|line| line.ok()) {
            if sender.send(line).is_err() {
                break;
            }
        }
    });
    let deadline = Instant::now() + limit;
    let initialize = json!({
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {
            "protocolVersion": 1,
            "clientCapabilities": {},
            "clientInfo": { "name": "echo", "version": "0" },
        },
    });
    send(&mut stdin, &initialize)?;
    reply(&lines, 1, deadline)?;
    let usage = json!({ "jsonrpc": "2.0", "id": 2, "method": "_kiro/account/getUsage", "params": {} });
    send(&mut stdin, &usage)?;
    credits(&reply(&lines, 2, deadline)?)
}

fn send(stdin: &mut ChildStdin, message: &Value) -> Result<()> {
    writeln!(stdin, "{message}")
        .and_then(|_| stdin.flush())
        .context("writing to kiro-cli acp")
}

fn reply(lines: &Receiver<String>, id: i64, deadline: Instant) -> Result<Value> {
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        let line = match lines.recv_timeout(left) {
            Ok(line) => line,
            Err(RecvTimeoutError::Timeout) => bail!("`kiro-cli acp` gave no reply {id} in time"),
            Err(RecvTimeoutError::Disconnected) => bail!("`kiro-cli acp` ended before reply {id}"),
        };
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        if message["id"] == id {
            if message.get("error").is_some() {
                bail!(
                    "`kiro-cli acp` answered request {id} with an error: {}",
                    message["error"]
                );
            }
            return Ok(message);
        }
    }
}

/// Lets the child exit by itself, then stops its whole process group: it must not outlive the call.
fn end(child: &mut Child) {
    let group = child.id() as libc::pid_t;
    if exited_within(child, EXIT_GRACE) {
        return;
    }
    unsafe { libc::killpg(group, libc::SIGTERM) };
    if !exited_within(child, Duration::from_secs(1)) {
        unsafe { libc::killpg(group, libc::SIGKILL) };
        let _ = child.wait();
    }
}

fn exited_within(child: &mut Child, grace: Duration) -> bool {
    let deadline = Instant::now() + grace;
    loop {
        match child.try_wait() {
            Ok(Some(_)) | Err(_) => return true,
            Ok(None) if Instant::now() >= deadline => return false,
            Ok(None) => std::thread::sleep(Duration::from_millis(25)),
        }
    }
}

/// The limit entry from the reply to `_kiro/account/getUsage`, or why there is none: a failed
/// call (`success: false`), a plan "managed by admin" (success without `data`), no CREDIT
/// breakdown or no real cap.
fn credits(message: &Value) -> Result<Value> {
    let result = message.get("result").context("the reply has no result")?;
    if result["success"] != true {
        bail!("Kiro could not tell the usage: {}", result["message"]);
    }
    let data = result
        .get("data")
        .filter(|data| data.is_object())
        .with_context(|| format!("the reply has no usage data: {}", result["message"]))?;
    let breakdown = data["usageBreakdowns"]
        .as_array()
        .and_then(|all| all.iter().find(|entry| entry["resourceType"] == "CREDIT"))
        .context("the reply has no CREDIT breakdown")?;
    let (used, cap) = match (breakdown["used"].as_f64(), breakdown["limit"].as_f64()) {
        (Some(used), Some(cap)) if used >= 0.0 && cap > 0.0 && breakdown["hasLimit"] != false => (used, cap),
        _ => bail!("the CREDIT breakdown has no usable used and limit"),
    };
    Ok(json!({
        "name": NAME,
        "percent": (used * 100.0 / cap).round() as i64,
        "resets": data["billingCycleReset"].as_str().and_then(reset_text),
        "detail": format!("{} of {}", number(used), number(cap)),
    }))
}

/// Credits as Kiro's TUI prints them: two decimals at most, none when whole ("603.62", "2000").
fn number(value: f64) -> String {
    let text = format!("{value:.2}");
    text.trim_end_matches('0').trim_end_matches('.').to_string()
}

/// "2026-12-01" as "Dec 1"; "Unknown" and anything else that is no date as nothing.
fn reset_text(date: &str) -> Option<String> {
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    let mut parts = date.splitn(3, '-');
    let _year: u32 = parts.next()?.parse().ok()?;
    let month: usize = parts.next()?.parse().ok()?;
    let day: u32 = parts.next()?.parse().ok()?;
    let month = MONTHS.get(month.checked_sub(1)?)?;
    (1..=31).contains(&day).then(|| format!("{month} {day}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    // The three replies to `_kiro/account/getUsage` recorded in docs/research/kiro-cli-usage-spike.md.
    const SUCCESS: &str = r#"{"jsonrpc":"2.0","id":2,"result":{"success":true,"message":"Plan: KIRO PRO+ | 1 usage breakdowns","data":{"planName":"KIRO PRO+","billingCycleReset":"2026-12-01","overagesEnabled":false,"isEnterprise":true,"usageBreakdowns":[{"resourceType":"CREDIT","displayName":"Credits","used":603.62,"limit":2000,"percentage":30,"currentOverages":0,"overageRate":0.04,"overageCharges":0,"currency":"USD","hasLimit":true}],"bonusCredits":[],"addOnCredits":[],"overageCapable":true}}}"#;
    const FAILURE: &str = r#"{"jsonrpc":"2.0","id":2,"result":{"success":false,"message":"Failed to retrieve usage information: connect ECONNREFUSED 127.0.0.1:9"}}"#;
    const ADMIN: &str =
        r#"{"jsonrpc":"2.0","id":2,"result":{"success":true,"message":"Your plan is managed by admin"}}"#;

    fn parsed(line: &str) -> Result<Value> {
        credits(&serde_json::from_str(line).unwrap())
    }

    #[test]
    fn the_recorded_success_becomes_a_limit_entry() {
        assert_eq!(
            parsed(SUCCESS).unwrap(),
            json!({ "name": "Kiro credits", "percent": 30, "resets": "Dec 1", "detail": "603.62 of 2000" })
        );
    }

    #[test]
    fn a_failed_call_and_a_plan_managed_by_admin_give_no_reading() {
        assert!(parsed(FAILURE).is_err());
        assert!(parsed(ADMIN).is_err());
    }

    #[test]
    fn a_reply_that_is_not_what_was_recorded_gives_no_reading_and_no_panic() {
        let with = |breakdowns: &str, reset: &str| {
            format!(
                r#"{{"result":{{"success":true,"data":{{"billingCycleReset":{reset},"usageBreakdowns":{breakdowns}}}}}}}"#
            )
        };
        for breakdowns in [
            "[]",
            "null",
            r#"[{"resourceType":"OTHER","used":1,"limit":2}]"#,
            r#"[{"resourceType":"CREDIT","used":1,"limit":0}]"#,
            r#"[{"resourceType":"CREDIT","used":1,"limit":2,"hasLimit":false}]"#,
            r#"[{"resourceType":"CREDIT","used":"1","limit":2}]"#,
            r#"[{"resourceType":"CREDIT","limit":2}]"#,
        ] {
            assert!(parsed(&with(breakdowns, r#""2026-12-01""#)).is_err(), "{breakdowns}");
        }
        assert!(credits(&json!({ "id": 2 })).is_err());
        assert!(credits(&json!({ "result": { "success": true, "data": "x" } })).is_err());
    }

    #[test]
    fn an_unknown_reset_leaves_the_entry_without_reset_text() {
        let line = r#"{"result":{"success":true,"data":{"billingCycleReset":"Unknown","extra":1,"usageBreakdowns":[{"resourceType":"CREDIT","used":340.98,"limit":2000,"new":true}]}}}"#;
        assert_eq!(
            parsed(line).unwrap(),
            json!({ "name": "Kiro credits", "percent": 17, "resets": null, "detail": "340.98 of 2000" })
        );
        let missing = r#"{"result":{"success":true,"data":{"usageBreakdowns":[{"resourceType":"CREDIT","used":341,"limit":2000}]}}}"#;
        assert_eq!(parsed(missing).unwrap()["resets"], Value::Null);
        assert_eq!(parsed(missing).unwrap()["detail"], "341 of 2000");
    }

    #[test]
    fn dates_and_numbers_read_as_kiro_prints_them() {
        assert_eq!(reset_text("2026-12-01").as_deref(), Some("Dec 1"));
        assert_eq!(reset_text("2027-01-31").as_deref(), Some("Jan 31"));
        for bad in [
            "Unknown",
            "",
            "2026-13-01",
            "2026-00-01",
            "2026-12-32",
            "2026-12",
            "x-y-z",
        ] {
            assert_eq!(reset_text(bad), None, "{bad}");
        }
        assert_eq!(number(603.62), "603.62");
        assert_eq!(number(2000.0), "2000");
        assert_eq!(number(0.5), "0.5");
        assert_eq!(number(0.0), "0");
    }

    #[test]
    fn the_percent_is_rounded_to_the_nearest_whole_number() {
        let reading = |used: f64| {
            let line = format!(
                r#"{{"result":{{"success":true,"data":{{"usageBreakdowns":[{{"resourceType":"CREDIT","used":{used},"limit":2000}}]}}}}}}"#
            );
            parsed(&line).unwrap()["percent"].as_i64().unwrap()
        };
        for (used, percent) in [
            (0.0, 0),
            (9.0, 0),
            (10.0, 1),
            (580.0, 29),
            (603.62, 30),
            (340.98, 17),
            (1989.0, 99),
            (1990.0, 100),
            (1999.0, 100),
            (2000.0, 100),
        ] {
            assert_eq!(reading(used), percent, "{used} of 2000");
        }
    }

    // The tests below run tests/fake-kiro-cli.sh, whose mode is the first line of `<home>/mode`.

    fn fake() -> String {
        format!("{}/tests/fake-kiro-cli.sh", env!("CARGO_MANIFEST_DIR"))
    }

    fn home(name: &str, mode: &str) -> PathBuf {
        let home = PathBuf::from(format!("/tmp/hubku-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&home);
        std::fs::create_dir_all(&home).unwrap();
        std::fs::write(home.join("mode"), mode).unwrap();
        home
    }

    fn alive(pid_file: &Path) -> bool {
        let pid: libc::pid_t = std::fs::read_to_string(pid_file).unwrap().trim().parse().unwrap();
        unsafe { libc::kill(pid, 0) == 0 }
    }

    #[test]
    fn a_scratch_home_that_cannot_be_made_runs_no_child_and_is_not_the_humans_home() {
        // The parent is a file, so `<parent>/kiro-home` cannot be created.
        let parent = home("blocked", "ok").join("file");
        std::fs::write(&parent, "x").unwrap();
        // Without a KIRO_HOME the fake would answer `ok` (the child would run in the human's home).
        let outcome = read(&fake(), &parent);
        assert!(matches!(outcome, Outcome::Skipped(_)), "{outcome:?}");
        let _ = std::fs::remove_dir_all(parent.parent().unwrap());
    }

    #[test]
    fn the_scratch_home_is_made_under_the_parent() {
        let parent = home("scratch", "ok");
        assert_eq!(scratch_home(&parent).unwrap(), parent.join("kiro-home"));
        assert!(parent.join("kiro-home").is_dir());
        let _ = std::fs::remove_dir_all(&parent);
    }

    #[test]
    fn the_fake_kiro_cli_gives_the_recorded_reading_and_leaves_nothing_running() {
        let home = home("ok", "ok");
        // The fake answers with a notification and another id first; both are skipped.
        assert_eq!(
            read_in(&fake(), &home),
            Outcome::Reading(
                json!({ "name": "Kiro credits", "percent": 30, "resets": "Dec 1", "detail": "603.62 of 2000" })
            )
        );
        assert!(!alive(&home.join("pid")), "the child is gone");
        let _ = std::fs::remove_dir_all(&home);
    }

    #[test]
    fn a_signed_out_or_missing_kiro_cli_is_absent_not_failed() {
        let home = home("out", "signedout");
        assert_eq!(read_in(&fake(), &home), Outcome::Absent);
        assert!(!home.join("pid").exists(), "acp was never started");
        assert_eq!(read_in("/tmp/hubku-no-such-kiro-cli", &home), Outcome::Absent);
        let _ = std::fs::remove_dir_all(&home);
    }

    #[test]
    fn a_failed_reply_and_an_admin_plan_are_failures() {
        for mode in ["fail", "admin"] {
            let home = home(mode, mode);
            assert!(matches!(read_in(&fake(), &home), Outcome::Failed(_)), "{mode}");
            assert!(!alive(&home.join("pid")), "{mode}: the child is gone");
            let _ = std::fs::remove_dir_all(&home);
        }
    }

    #[test]
    fn a_child_that_never_answers_is_killed_with_its_group_at_the_limit() {
        let home = home("hang", "hang");
        let started = Instant::now();
        let outcome = read_within(&fake(), &home, Duration::from_secs(1));
        assert!(matches!(outcome, Outcome::Failed(_)), "{outcome:?}");
        assert!(started.elapsed() < Duration::from_secs(10));
        let deadline = Instant::now() + Duration::from_secs(5);
        while (alive(&home.join("pid")) || alive(&home.join("sleeper"))) && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(50));
        }
        assert!(!alive(&home.join("pid")), "the script is gone");
        assert!(!alive(&home.join("sleeper")), "what it started is gone");
        let _ = std::fs::remove_dir_all(&home);
    }
}

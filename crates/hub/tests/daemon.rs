//! End-to-end tests of the Hub Daemon through the `echoctl` binary, with a fake agent for `claude`.

use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::time::{Duration, Instant};

struct Hub {
    state: PathBuf,
    repo: PathBuf,
}

fn git(dir: &Path, args: &[&str]) -> String {
    let out = Command::new("git").arg("-C").arg(dir).args(args).output().unwrap();
    assert!(
        out.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).into_owned()
}

impl Hub {
    /// A fresh daemon state and repo. Short /tmp paths: macOS caps socket paths at 104 bytes.
    fn new(name: &str) -> Hub {
        let state = PathBuf::from(format!("/tmp/hubt-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&state);
        let repo = state.join("repo");
        std::fs::create_dir_all(&repo).unwrap();
        git(&repo, &["init", "-q", "-b", "main"]);
        std::fs::write(repo.join("README.md"), "# test\n").unwrap();
        git(&repo, &["add", "."]);
        git(
            &repo,
            &["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init"],
        );
        Hub { state, repo }
    }

    fn run(&self, args: &[&str]) -> Output {
        self.run_with(args, &[])
    }

    fn run_with(&self, args: &[&str], env: &[(&str, &str)]) -> Output {
        let bin = Path::new(env!("CARGO_BIN_EXE_echoctl"));
        let fake = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fake-agent.sh");
        Command::new(bin)
            .args(args)
            .current_dir(&self.repo)
            .env("HUB_STATE", &self.state)
            .env("HUB_TEST_AGENT", fake)
            .env("HUB_COALESCE_MS", "200")
            .env(
                "PATH",
                format!("{}:{}", bin.parent().unwrap().display(), std::env::var("PATH").unwrap()),
            )
            .env_remove("HUB_WORKER")
            .envs(env.iter().copied())
            .output()
            .unwrap()
    }

    fn ok(&self, args: &[&str]) -> String {
        let out = self.run(args);
        assert!(
            out.status.success(),
            "echoctl {args:?} failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        String::from_utf8_lossy(&out.stdout).into_owned()
    }

    fn fails(&self, args: &[&str]) -> String {
        let out = self.run(args);
        assert!(!out.status.success(), "echoctl {args:?} should fail");
        String::from_utf8_lossy(&out.stderr).into_owned()
    }

    /// One request on the daemon socket, as the Hub App sends it.
    fn call(&self, method: &str, params: serde_json::Value) -> serde_json::Value {
        let mut stream = UnixStream::connect(self.state.join("hubd.sock")).unwrap();
        let request = serde_json::json!({ "method": method, "params": params });
        stream.write_all(format!("{request}\n").as_bytes()).unwrap();
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap()
    }

    fn repo_key(&self) -> String {
        self.repo.canonicalize().unwrap().display().to_string()
    }

    fn wait(&self) -> String {
        self.ok(&["wait", "--timeout", "15"])
    }

    fn status(&self) -> serde_json::Value {
        serde_json::from_str(&self.ok(&["status", "--json"])).unwrap()
    }

    fn eventually(&self, what: &str, mut check: impl FnMut() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(15);
        while !check() {
            assert!(Instant::now() < deadline, "timed out waiting for {what}");
            std::thread::sleep(Duration::from_millis(200));
        }
    }
}

impl Drop for Hub {
    fn drop(&mut self) {
        let _ = self.run(&["shutdown", "--force"]);
        std::thread::sleep(Duration::from_millis(300));
        let _ = std::fs::remove_dir_all(&self.state);
    }
}

#[test]
fn question_reply_and_final_report() {
    let hub = Hub::new("ask");
    assert!(hub
        .ok(&["worker", "start", "lee", "--spec", "ask about color"])
        .starts_with("Started w1"));

    let question = hub.wait();
    assert!(
        question.contains("#1 question from w1 (lee: ask about color)"),
        "{question}"
    );
    assert!(question.contains("Which color?"));
    assert!(question.contains("echoctl reply 1"));
    assert_eq!(hub.status()[0]["state"], "needs you");
    assert!(hub.ok(&["inbox"]).contains("#1 from w1"));

    hub.ok(&["reply", "1", "blue"]);
    let done = hub.wait();
    assert!(done.contains("done (done) from w1"), "{done}");
    assert!(done.contains("answer was blue"));
    assert!(!done.contains("->"), "only a question ends with a next step: {done}");
    assert_eq!(hub.status()[0]["state"], "done");
    assert!(hub.fails(&["reply", "1", "again"]).contains("already answered"));

    hub.ok(&["worker", "close", "w1"]);
    hub.eventually("w1 to close", || {
        hub.ok(&["worker", "list"]).contains("No open Workers.")
    });
    assert_eq!(
        hub.status()[0]["state"],
        "done",
        "settled Workers stay on the Dashboard a while"
    );
}

#[test]
fn an_exit_without_a_final_report_is_reported() {
    let hub = Hub::new("exit");
    hub.ok(&["worker", "start", "lee", "--spec", "exit early"]);
    let exited = hub.wait();
    assert!(exited.contains("exited from w1"), "{exited}");
    assert!(exited.contains("fake agent giving up"));
    assert_eq!(hub.status()[0]["state"], "failed");
}

#[test]
fn a_worker_closed_at_its_input_box_without_a_report_ended() {
    let hub = Hub::new("finish");
    hub.ok(&["worker", "start", "lee", "--spec", "finish quietly"]);
    hub.eventually("the turn to end on screen", || {
        hub.ok(&["worker", "read", "w1"]).contains("Brewed for 18s")
    });
    hub.ok(&["worker", "close", "w1"]);
    hub.eventually("w1 to settle", || hub.status()[0]["state"] != "running");
    let row = &hub.status()[0];
    assert_eq!(row["state"], "ended", "{row}");
    let report = row["finalReport"].as_str().unwrap_or("");
    assert!(report.contains("Both databases are dropped."), "{report}");
}

#[test]
fn a_worker_waiting_on_a_monitor_is_waiting_not_needs_you() {
    let hub = Hub::new("monitor");
    hub.ok(&["worker", "start", "lee", "--spec", "monitor the server"]);
    hub.eventually("w1 to show waiting", || hub.status()[0]["state"] == "waiting");
}

#[test]
fn new_worktrees_get_a_typed_branch() {
    let hub = Hub::new("wt");
    let started = hub.ok(&[
        "worker",
        "start",
        "lee",
        "--spec",
        "sleep",
        "--worktree",
        "new:feat/thing",
    ]);
    assert!(started.contains("on feat/thing"), "{started}");
    assert!(git(&hub.repo, &["branch", "--list", "feat/thing"]).contains("feat/thing"));
    assert_eq!(hub.status()[0]["place"], "feat-thing");
    assert!(hub.ok(&["worker", "list"]).contains("feat/thing"));
    let refused = hub.fails(&[
        "worker",
        "start",
        "lee",
        "--spec",
        "sleep",
        "--worktree",
        "new:feature/x",
    ]);
    assert!(refused.contains("type one of"), "{refused}");
}

#[test]
fn a_worker_starts_where_another_worker_works() {
    let hub = Hub::new("workertree");
    hub.ok(&["status"]); // starts the daemon
    let start = |worktree: &str| {
        hub.call(
            "worker.start",
            serde_json::json!({ "repo": hub.repo_key(), "profile": "lee", "spec": "sleep", "worktree": worktree }),
        )
    };
    let first = start("new:feat/thing");
    let tree = first["result"]["cwd"]
        .as_str()
        .unwrap_or_else(|| panic!("{first}"))
        .to_string();
    let second = start("worker:w1");
    assert_eq!(second["result"]["cwd"], tree.as_str(), "{second}");
    assert_eq!(hub.status()[1]["place"], "feat-thing");
    let missing = hub.fails(&["worker", "start", "lee", "--spec", "sleep", "--worktree", "worker:w9"]);
    assert!(
        missing.contains("worker:w9") && missing.contains("no Worker w9"),
        "{missing}"
    );
    let malformed = hub.fails(&["worker", "start", "lee", "--spec", "sleep", "--worktree", "worker:feat"]);
    assert!(malformed.contains("needs a Worker id like w12"), "{malformed}");
}

#[test]
fn attach_streams_the_screen_and_types_input() {
    let hub = Hub::new("attach");
    hub.ok(&["worker", "start", "lee", "--spec", "echo back"]);
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    stream
        .write_all(b"{\"method\":\"attach\",\"params\":{\"id\":1,\"rows\":30,\"cols\":100}}\n")
        .unwrap();
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    let mut line = String::new();
    reader.read_line(&mut line).unwrap();
    assert!(line.contains("\"ok\":true"), "{line}");
    stream.write_all(b"hello\r").unwrap();

    stream.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
    let mut seen = Vec::new();
    let mut buf = [0u8; 4096];
    while !String::from_utf8_lossy(&seen).contains("got: hello") {
        let n = reader.read(&mut buf).expect("attached output");
        assert!(n > 0, "stream ended early: {}", String::from_utf8_lossy(&seen));
        seen.extend_from_slice(&buf[..n]);
    }
    assert!(
        String::from_utf8_lossy(&seen).contains("Working"),
        "the snapshot redraws the screen first"
    );
    assert!(hub.ok(&["worker", "read", "w1", "--lines", "3"]).contains("got: hello"));
}

/// Kills whatever process listens on `socket` in the test's state folder.
fn kill_listener(socket: &Path) {
    let pid = Command::new("lsof").arg("-t").arg(socket).output().unwrap();
    for pid in String::from_utf8_lossy(&pid.stdout).split_whitespace() {
        Command::new("kill").args(["-9", pid]).status().unwrap();
    }
    std::thread::sleep(Duration::from_millis(500));
}

#[test]
fn a_daemon_crash_leaves_workers_running_and_the_next_daemon_takes_them_over() {
    let hub = Hub::new("crash");
    hub.ok(&["worker", "start", "lee", "--spec", "echo"]);
    hub.ok(&["worker", "send", "w1", "before"]);
    hub.eventually("w1 to echo", || {
        hub.ok(&["worker", "read", "w1"]).contains("got: before")
    });
    kill_listener(&hub.state.join("hubd.sock"));

    // The next command starts a new daemon, which adopts w1 with its screen.
    assert_eq!(hub.status()[0]["state"], "running");
    assert!(hub.ok(&["worker", "read", "w1"]).contains("got: before"));
    hub.ok(&["worker", "send", "w1", "after"]);
    hub.eventually("w1 to echo again", || {
        hub.ok(&["worker", "read", "w1"]).contains("got: after")
    });
}

#[test]
fn an_agent_survives_a_daemon_crash_with_its_prompt_still_under_needs_you() {
    let hub = Hub::new("agentcrash");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "prompt me" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    let has_need = || {
        snapshot(&hub)["needs"]
            .as_array()
            .is_some_and(|needs| !needs.is_empty())
    };
    hub.eventually("the prompt to reach Needs you", has_need);
    kill_listener(&hub.state.join("hubd.sock"));

    hub.ok(&["status"]);
    hub.eventually("the adopted agent's prompt under Needs you", has_need);
    let decided = hub.call("decide", serde_json::json!({ "agent": agent, "approve": true }));
    assert_eq!(decided["ok"], true, "{decided}");
    hub.eventually("the prompt to clear", || {
        snapshot(&hub)["needs"].as_array().is_some_and(|needs| needs.is_empty())
    });
}

#[test]
fn a_shutdown_without_force_leaves_terminals_running() {
    let hub = Hub::new("planned");
    hub.ok(&["worker", "start", "lee", "--spec", "echo"]);
    hub.ok(&["shutdown"]);
    std::thread::sleep(Duration::from_millis(500));
    assert_eq!(hub.status()[0]["state"], "running");
    hub.ok(&["worker", "send", "w1", "still here"]);
    hub.eventually("w1 to echo", || {
        hub.ok(&["worker", "read", "w1"]).contains("got: still here")
    });
}

#[test]
fn a_worker_whose_terminal_is_gone_is_lost_and_resumes() {
    let hub = Hub::new("lost");
    hub.ok(&["worker", "start", "lee", "--spec", "sleep"]);
    kill_listener(&hub.state.join("hubd.sock"));
    kill_listener(&hub.state.join("holder.sock"));

    let lost = hub.wait();
    assert!(lost.contains("lost from w1"), "{lost}");
    assert!(lost.contains("echoctl worker resume w1"));
    assert_eq!(hub.status()[0]["state"], "needs you");

    assert!(hub.ok(&["worker", "resume", "w1"]).contains("Resumed w1"));
    hub.eventually("w1 to run again", || hub.status()[0]["state"] == "running");
}

#[test]
fn a_settled_worker_takes_its_next_task_in_the_same_session() {
    let hub = Hub::new("nexttask");
    hub.ok(&["worker", "start", "lee", "--spec", "next please", "--keep"]);
    assert!(hub.wait().contains("first Task done"));
    assert!(hub
        .ok(&["worker", "task", "w1", "--spec", "fix the review comments"])
        .contains("Gave w1 its next Task"));
    let done = hub.wait();
    assert!(done.contains("next: fix the review comments"), "{done}");
    assert_eq!(hub.status()[0]["state"], "done");

    hub.ok(&["worker", "close", "w1"]);
    hub.eventually("w1 to close", || {
        hub.ok(&["worker", "list"]).contains("No open Workers.")
    });
    // Its terminal is gone, so its session resumes on the Task.
    hub.ok(&["worker", "task", "w1", "--spec", "done with the CI fix"]);
    assert!(hub.wait().contains("done (done) from w1"));
    assert!(hub.ok(&["worker", "list"]).contains("w1"));
}

#[test]
fn a_send_says_whether_the_worker_started() {
    let hub = Hub::new("started");
    hub.ok(&["worker", "start", "lee", "--spec", "turns"]);
    hub.eventually("w1 at its input box", || {
        hub.ok(&["worker", "read", "w1"]).contains("Ready.")
    });
    assert!(hub.ok(&["worker", "send", "w1", "go"]).contains("w1 started working."));

    hub.ok(&["worker", "start", "lee", "--spec", "idle"]);
    hub.eventually("w2 at its input box", || {
        hub.ok(&["worker", "read", "w2"]).contains("Ready.")
    });
    assert!(hub
        .ok(&["worker", "send", "w2", "go"])
        .contains("w2 has not started working after 5 s"));
}

#[test]
fn a_send_does_not_type_over_a_permission_prompt() {
    let hub = Hub::new("overprompt");
    hub.ok(&["worker", "start", "lee", "--spec", "prompt"]);
    hub.eventually("the prompt", || {
        hub.ok(&["worker", "read", "w1"]).contains("Do you want to proceed?")
    });
    assert!(hub.fails(&["worker", "send", "w1", "hi"]).contains("permission prompt"));
    hub.ok(&["worker", "send", "w1", "denied it", "--force"]);
    hub.eventually("the forced text to answer it", || {
        hub.ok(&["worker", "read", "w1"]).contains("denied: denied it")
    });
}

#[test]
fn stats_count_workers_and_say_when_none_has_a_transcript() {
    let hub = Hub::new("stats");
    hub.ok(&["worker", "start", "lee", "--spec", "done"]);
    assert!(hub
        .ok(&["stats", "--days", "1"])
        .starts_with("Last 1 days: 1 Workers, 0 with transcripts, 0 turns"));
}

#[test]
fn stats_json_reports_orchestrators_beside_workers() {
    let hub = Hub::new("statsorch");
    hub.ok(&["status"]);
    hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "name": "Rerank" }),
    );
    hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "plain" }),
    );
    let stats: serde_json::Value = serde_json::from_str(&hub.ok(&["stats", "--days", "1", "--json"])).unwrap();
    // The Worker numbers keep their place; Orchestrators are an object beside them.
    assert_eq!(stats["workers"], 0);
    assert!(stats["profiles"].is_array());
    let orchestrators = &stats["orchestrators"];
    assert_eq!(
        orchestrators["agents"], 1,
        "a Normal session is not an Orchestrator: {stats}"
    );
    assert_eq!(
        orchestrators["withTranscript"], 0,
        "the fake agent writes no transcript"
    );
    assert_eq!(orchestrators["cold"]["requests"], 0);
    assert!(orchestrators["toolResults"].is_array() && orchestrators["sessions"].is_array());
    assert!(hub.ok(&["stats", "--days", "1"]).starts_with("Last 1 days: 0 Workers"));
}

#[test]
fn only_a_question_ends_with_a_next_step() {
    let hub = Hub::new("nextstep");
    hub.ok(&["worker", "start", "lee", "--spec", "done"]);
    let done = hub.wait();
    assert!(done.contains("done (done) from w1") && !done.contains("->"), "{done}");
    assert!(
        done.contains("(w1 is closed)"),
        "a branchless Worker closes when its report is delivered: {done}"
    );
    hub.ok(&["worker", "close", "w1"]);
    hub.ok(&["worker", "start", "lee", "--spec", "ask"]);
    let question = hub.wait();
    assert!(question.contains("question from w2"), "{question}");
    assert!(question.contains("-> echoctl reply "), "{question}");
}

#[test]
fn a_failed_verification_sends_the_writer_back_once_and_the_orchestrator_hears_only_the_pass() {
    let hub = Hub::new("verify");
    let started = hub.ok(&["worker", "start", "lee", "--spec", "next FAILME", "--verify"]);
    assert!(started.starts_with("Started w1"), "{started}");
    // One message, after w2 failed it, w1 took the retry, and w3 passed it.
    let told = hub.wait();
    assert!(told.contains("done (done) from w1"), "{told}");
    assert!(told.contains("Verified by w3: pass."), "{told}");
    assert!(!told.contains("from w2") && !told.contains("from w3"), "{told}");
    assert!(
        told.contains("next: w2 (sasuke) verified your change and it failed"),
        "{told}"
    );
    hub.eventually("the verifiers to close", || {
        let open = hub.ok(&["worker", "list"]);
        !open.contains("w2") && !open.contains("w3")
    });
}

#[test]
fn a_writer_that_fails_verification_again_goes_to_the_orchestrator_with_the_findings() {
    let hub = Hub::new("verifyfail");
    hub.ok(&[
        "worker",
        "start",
        "lee",
        "--spec",
        "next ALWAYSFAIL",
        "--verify",
        "--keep",
    ]);
    let told = hub.wait();
    assert!(told.contains("done (done) from w1"), "{told}");
    assert!(told.contains("failed again after 1 retry"), "{told}");
    assert!(
        told.contains("Verifier's report:\nVerdict: fail\nP1 foo.rs:1 broken"),
        "{told}"
    );
}

#[test]
fn a_verifier_without_a_verdict_leaves_the_judging_to_the_orchestrator() {
    let hub = Hub::new("noverdict");
    hub.ok(&["worker", "start", "lee", "--spec", "done NOVERDICT", "--verify"]);
    let told = hub.wait();
    assert!(told.contains("without a `Verdict:` line"), "{told}");
    assert!(told.contains("looks fine to me"), "{told}");
}

#[test]
fn verifying_is_left_out_when_the_humans_settings_skip_the_review() {
    let hub = Hub::new("noreview");
    hub.ok(&["status"]);
    hub.call("settings.set", serde_json::json!({ "settings": { "review": false } }));
    hub.ok(&["worker", "start", "lee", "--spec", "done", "--verify"]);
    let told = hub.wait();
    assert!(
        told.contains("done (done) from w1") && !told.contains("Verified"),
        "{told}"
    );
    assert!(
        hub.fails(&["worker", "read", "w2"]).contains("w2"),
        "no verifier was started"
    );
}

#[test]
fn a_worker_without_a_branch_closes_when_its_report_arrives_unless_kept() {
    let hub = Hub::new("closeondone");
    hub.ok(&["worker", "start", "lee", "--spec", "done"]);
    hub.ok(&["worker", "start", "lee", "--spec", "done", "--keep"]);
    hub.ok(&["worker", "start", "lee", "--spec", "done", "--worktree", "new:feat/own"]);
    let told = hub.wait();
    assert_eq!(told.matches("done (done) from").count(), 3, "{told}");
    hub.eventually("w1 to close", || !hub.ok(&["worker", "list"]).contains("w1"));
    let open = hub.ok(&["worker", "list"]);
    assert!(
        open.contains("w2") && open.contains("w3"),
        "kept, and on its own branch: {open}"
    );
}

#[test]
fn a_status_never_wakes_the_orchestrator_but_comes_with_the_next_message() {
    let hub = Hub::new("quietstatus");
    hub.ok(&["worker", "start", "lee", "--spec", "status"]);
    let quiet = hub.ok(&["wait", "--timeout", "2"]);
    assert!(quiet.contains("No messages in 2s"), "{quiet}");
    hub.ok(&["worker", "start", "lee", "--spec", "done"]);
    let told = hub.wait();
    assert!(told.contains("done (done) from w2"), "{told}");
    assert!(
        told.contains("status from w1") && told.contains("41 of 44 tests passing"),
        "{told}"
    );
}

#[test]
fn a_task_can_carry_another_workers_final_report() {
    let hub = Hub::new("fromreport");
    hub.ok(&["worker", "start", "lee", "--spec", "done", "--keep"]);
    hub.ok(&["worker", "start", "lee", "--spec", "next please", "--keep"]);
    hub.wait();
    let given = hub.ok(&["worker", "task", "w2", "--from-report", "w1"]);
    assert!(given.contains("Gave w2 its next Task"), "{given}");
    assert!(hub
        .fails(&["worker", "task", "w2", "--from-report", "w9"])
        .contains("no Worker w9"));
    hub.ok(&["worker", "start", "lee", "--spec", "wait forever"]);
    assert!(hub
        .fails(&["worker", "task", "w2", "--from-report", "w3"])
        .contains("w3 has no Final Report yet"));
    assert!(hub.fails(&["worker", "task", "w2"]).contains("give --spec"));
}

#[test]
fn a_renewed_orchestrator_starts_a_new_session_on_a_message_to_read_its_brief() {
    let hub = Hub::new("renew");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    let session = || hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["session_id"].clone();
    let before = session();
    let renewed = hub.call("agent.renew", serde_json::json!({ "agent": agent }));
    assert_eq!(renewed["result"]["started"], true, "{renewed}");
    assert_ne!(session(), before, "a new Claude session");
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let attach = serde_json::json!({ "method": "attach", "params": { "agent": agent, "rows": 30, "cols": 100 } });
    stream.write_all(format!("{attach}\n").as_bytes()).unwrap();
    stream.set_read_timeout(Some(Duration::from_secs(15))).unwrap();
    read_until(&mut stream, &mut Vec::new(), "renewed with: Your session was renewed");
    let worker = hub.call("agent.renew", serde_json::json!({ "agent": 999 }));
    assert!(worker["error"].is_string(), "{worker}");
    let setting = hub.call(
        "settings.set",
        serde_json::json!({ "settings": { "orchestratorRotateAt": 150000 } }),
    );
    assert_eq!(setting["result"]["orchestratorRotateAt"], 150000, "{setting}");
}

#[test]
fn a_brief_tells_a_fresh_session_what_is_open() {
    let hub = Hub::new("brief");
    hub.ok(&["worker", "start", "lee", "--spec", "wait forever"]);
    hub.ok(&["worker", "start", "lee", "--spec", "done", "--keep"]);
    hub.wait();
    let brief = hub.ok(&["brief"]);
    assert!(
        brief.contains("Running (or waiting):\n  w1 lee running in place"),
        "{brief}"
    );
    assert!(
        brief.contains("w2 lee done in place") && brief.contains("report: finished"),
        "{brief}"
    );
    assert!(brief.contains("Open questions:\n  none"), "{brief}");
}

#[test]
fn a_running_worker_takes_no_next_task() {
    let hub = Hub::new("busytask");
    hub.ok(&["worker", "start", "lee", "--spec", "wait forever"]);
    assert!(hub
        .fails(&["worker", "task", "w1", "--spec", "more"])
        .contains("still on its Task"));
}

#[test]
fn a_review_sent_to_a_settled_worker_lets_it_report_again() {
    let hub = Hub::new("reviewdone");
    hub.ok(&["worker", "start", "lee", "--spec", "next please", "--keep"]);
    assert!(hub.wait().contains("first Task done"));
    hub.call(
        "worker.review",
        serde_json::json!({ "id": 1, "to": "worker", "body": "README.md:2 say why" }),
    );
    let messages = hub.wait();
    assert!(messages.contains("done (done) from w1"), "{messages}");
    assert!(messages.contains("next: "), "{messages}");
}

#[test]
fn worker_commands_need_a_worker() {
    let hub = Hub::new("env");
    assert!(hub.fails(&["done", "--state", "done", "x"]).contains("HUB_WORKER"));
    assert!(hub.fails(&["worker", "key", "w1", "hyper"]).contains("unknown key"));
}

#[test]
fn a_forced_shutdown_closes_workers_instead_of_losing_them() {
    let hub = Hub::new("shut");
    hub.ok(&["worker", "start", "lee", "--spec", "sleep"]);
    hub.ok(&["shutdown", "--force"]);
    std::thread::sleep(Duration::from_millis(500));
    assert!(hub.ok(&["worker", "list"]).contains("No open Workers."));
    assert!(hub.ok(&["wait", "--timeout", "1"]).contains("No messages"));
    assert_eq!(hub.status()[0]["state"], "failed");
}

#[test]
fn the_daemon_owns_one_orchestrator_per_repo() {
    let hub = Hub::new("orch");
    hub.ok(&["status"]); // starts the daemon
    let repo = hub.repo_key();
    let first = hub.call("session.open", serde_json::json!({ "repo": repo }));
    assert_eq!(first["result"]["started"], true, "{first}");
    let again = hub.call("session.open", serde_json::json!({ "repo": repo }));
    assert_eq!(again["result"]["started"], false, "{again}");
    let sessions = hub.call("sessions.list", serde_json::json!({}));
    assert_eq!(sessions["result"]["sessions"][0]["repo"], repo);
    assert_eq!(sessions["result"]["sessions"][0]["live"], true);

    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request =
        serde_json::json!({ "method": "attach", "params": { "orchestrator": repo, "rows": 30, "cols": 100 } });
    stream.write_all(format!("{request}\n").as_bytes()).unwrap();
    stream.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
    let mut seen = Vec::new();
    let mut buf = [0u8; 4096];
    while !String::from_utf8_lossy(&seen).contains("Working") {
        let n = stream.read(&mut buf).expect("orchestrator output");
        assert!(n > 0);
        seen.extend_from_slice(&buf[..n]);
    }

    hub.call("session.close", serde_json::json!({ "repo": repo }));
    hub.eventually("the Orchestrator to stop", || {
        hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["live"] == false
    });
}

#[test]
fn a_picked_orchestrator_model_is_kept_for_the_session() {
    let hub = Hub::new("model");
    hub.ok(&["status"]);
    let repo = hub.repo_key();
    let opened = hub.call(
        "session.open",
        serde_json::json!({ "repo": repo, "model": "claude-opus-5-5" }),
    );
    assert_eq!(opened["result"]["model"], "claude-opus-5-5", "{opened}");
    let sessions = hub.call("sessions.list", serde_json::json!({}));
    assert_eq!(sessions["result"]["sessions"][0]["model"], "claude-opus-5-5");
    hub.call("session.close", serde_json::json!({ "repo": repo }));
    hub.eventually("the Orchestrator to stop", || {
        hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["live"] == false
    });
    let reopened = hub.call("session.open", serde_json::json!({ "repo": repo }));
    assert_eq!(
        reopened["result"]["model"], "claude-opus-5-5",
        "a start without a model keeps the saved one"
    );
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request = serde_json::json!({ "method": "events", "params": { "repo": repo } });
    stream.write_all(format!("{request}\n").as_bytes()).unwrap();
    stream.set_read_timeout(Some(Duration::from_secs(15))).unwrap();
    let mut lines = BufReader::new(stream).lines();
    lines.next();
    let snapshot: serde_json::Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
    assert_eq!(snapshot["orchestrator"]["model"], "claude-opus-5-5");
}

#[test]
fn worker_rows_carry_model_effort_and_progress() {
    let hub = Hub::new("progress");
    hub.ok(&["status"]);
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request = serde_json::json!({ "method": "events", "params": { "repo": hub.repo_key() } });
    stream.write_all(format!("{request}\n").as_bytes()).unwrap();
    stream.set_read_timeout(Some(Duration::from_secs(15))).unwrap();
    let mut lines = BufReader::new(stream).lines();
    lines.next();
    hub.ok(&["worker", "start", "lee", "--spec", "status then wait"]);
    loop {
        let snapshot: serde_json::Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
        let Some(row) = snapshot["workers"].as_array().and_then(|rows| rows.first()) else {
            continue;
        };
        assert_eq!(row["model"], "claude-haiku-5-5");
        assert_eq!(row["effort"], "low");
        assert_eq!(snapshot["orchestrator"]["model"], serde_json::Value::Null);
        if row["progress"] == "41 of 44 tests passing" {
            break;
        }
    }
}

/// The repo's first snapshot from the events stream.
fn snapshot(hub: &Hub) -> serde_json::Value {
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request = serde_json::json!({ "method": "events", "params": { "repo": hub.repo_key() } });
    stream.write_all(format!("{request}\n").as_bytes()).unwrap();
    stream.set_read_timeout(Some(Duration::from_secs(15))).unwrap();
    let mut lines = BufReader::new(stream).lines();
    lines.next();
    serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap()
}

#[test]
fn a_done_worker_leaves_echo_after_five_minutes() {
    let hub = Hub::new("expire");
    hub.ok(&["worker", "start", "lee", "--spec", "done quickly"]);
    hub.eventually("w1 to finish", || snapshot(&hub)["workers"][0]["phase"] == "done");
    let db = rusqlite::Connection::open(hub.state.join("hub.db")).unwrap();
    db.execute("update workers set settled_at = settled_at - 4 * 60 where id = 1", [])
        .unwrap();
    assert_eq!(
        snapshot(&hub)["workers"].as_array().unwrap().len(),
        1,
        "kept within five minutes"
    );
    db.execute("update workers set settled_at = settled_at - 2 * 60 where id = 1", [])
        .unwrap();
    assert!(
        snapshot(&hub)["workers"].as_array().unwrap().is_empty(),
        "gone after five minutes, read or not"
    );
    db.execute("update workers set state = 'blocked' where id = 1", [])
        .unwrap();
    assert_eq!(
        snapshot(&hub)["workers"].as_array().unwrap().len(),
        1,
        "a blocked Worker still needs the human"
    );
}

#[test]
fn profiles_copied_into_yours_or_the_repo_replace_echos_own() {
    let hub = Hub::new("profiles");
    let listed = hub.ok(&["profile", "list"]);
    assert!(
        listed.lines().any(|l| l.starts_with("lee ") && l.contains("built-in")),
        "{listed}"
    );
    let copied = hub.ok(&["profile", "copy", "lee"]);
    let mine = hub.state.join("profiles/lee.md");
    assert!(copied.contains(&mine.display().to_string()), "{copied}");
    assert!(hub.fails(&["profile", "copy", "lee"]).contains("already yours"));
    hub.ok(&["profile", "copy", "lee", "--repo"]);
    let theirs = hub.repo.join(".echo/profiles/lee.md");
    let text = std::fs::read_to_string(&theirs).unwrap();
    std::fs::write(
        &theirs,
        text.replace("description: Command runner.", "description: The team's runner."),
    )
    .unwrap();
    let listed = hub.ok(&["profile", "list"]);
    let lee = listed.lines().find(|l| l.starts_with("lee ")).unwrap();
    assert!(
        lee.contains("repo (replaces yours)") && lee.contains("The team's runner."),
        "{listed}"
    );

    // A Profile only this repo has starts Workers like any other.
    hub.ok(&["profile", "new", "scout", "--repo"]);
    assert!(hub.fails(&["profile", "new", "scout"]).contains("already exists"));
    assert!(hub.fails(&["profile", "new", "Bad Name"]).contains("lowercase"));
    hub.ok(&["worker", "start", "scout", "--spec", "done quickly"]);
    assert!(hub.wait().contains("done (done) from w1 (scout"));
}

#[test]
fn a_cli_or_model_that_cannot_run_stops_a_worker_before_it_starts() {
    let hub = Hub::new("pickcli");
    let err = hub.fails(&[
        "worker",
        "start",
        "lee",
        "--spec",
        "done quickly",
        "--model",
        "openai/gpt-5",
    ]);
    assert!(err.contains("only Anthropic"), "{err}");
    let err = hub.fails(&["worker", "start", "lee", "--spec", "done quickly", "--cli", "opencode"]);
    assert!(err.contains("not supported yet"), "{err}");
    assert!(!hub.ok(&["worker", "list"]).contains("w1"), "nothing was started");
    std::fs::create_dir_all(hub.repo.join(".echo")).unwrap();
    std::fs::write(
        hub.repo.join(".echo/settings.json"),
        r#"{"model": "anthropic/claude-fable-5-1"}"#,
    )
    .unwrap();
    let listed = hub.ok(&["profile", "list"]);
    let lee = listed.lines().find(|l| l.starts_with("lee ")).unwrap();
    assert!(
        lee.contains("claude anthropic/claude-haiku-5-5"),
        "a Profile's model beats the repo's: {lee}"
    );
    hub.ok(&[
        "worker",
        "start",
        "lee",
        "--spec",
        "done quickly",
        "--model",
        "anthropic/claude-opus-5-5",
    ]);
    assert!(hub.wait().contains("done (done) from w1"));
}

#[test]
fn the_orchestrators_own_model_and_effort_are_settings() {
    let hub = Hub::new("orchsettings");
    hub.ok(&["sessions"]);
    let set = hub.call(
        "settings.set",
        serde_json::json!({ "settings": { "orchestratorModel": "anthropic/claude-sonnet-5-5", "orchestratorEffort": "medium" } }),
    );
    assert_eq!(set["result"]["orchestratorEffort"], "medium", "{set}");
    let got = hub.call("settings.get", serde_json::json!({}));
    assert_eq!(
        got["result"]["orchestratorModel"], "anthropic/claude-sonnet-5-5",
        "{got}"
    );
    let refused = hub.call(
        "settings.set",
        serde_json::json!({ "settings": { "orchestratorEffort": "extreme" } }),
    );
    assert!(
        refused["error"].as_str().unwrap().contains("one of low, medium, high"),
        "{refused}"
    );
    // An empty string puts the built-in default back.
    let cleared = hub.call(
        "settings.set",
        serde_json::json!({ "settings": { "orchestratorModel": "", "orchestratorEffort": "" } }),
    );
    assert!(cleared["result"]["orchestratorModel"].is_null(), "{cleared}");
    assert!(cleared["result"]["orchestratorEffort"].is_null(), "{cleared}");
}

#[test]
fn settings_and_profile_edits_from_echo_land_in_the_humans_files() {
    let hub = Hub::new("settings");
    hub.ok(&["sessions"]);
    let set = hub.call(
        "settings.set",
        serde_json::json!({ "settings": { "maxWorkers": 6, "review": false } }),
    );
    assert_eq!(set["result"]["orchestrator"]["maxWorkers"], 6, "{set}");
    assert!(
        hub.call("settings.set", serde_json::json!({ "settings": { "theme": "x" } }))["error"]
            .as_str()
            .unwrap()
            .contains("unknown setting")
    );
    let edited = hub.call(
        "profile.set",
        serde_json::json!({ "name": "lee", "fields": { "model": "anthropic/claude-opus-5-5", "effort": "" } }),
    );
    assert_eq!(
        edited["result"]["path"],
        hub.state.join("profiles/lee.md").display().to_string(),
        "{edited}"
    );
    let listed = hub.call("profiles.list", serde_json::json!({ "repo": hub.repo }));
    let lee = listed["result"]["profiles"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["name"] == "lee")
        .unwrap()
        .clone();
    assert_eq!(
        (lee["level"].as_str(), lee["model"].as_str()),
        (Some("yours"), Some("anthropic/claude-opus-5-5"))
    );
    assert!(lee["effort"].is_null());
    hub.call("profile.reset", serde_json::json!({ "name": "lee" }));
    assert!(!hub.state.join("profiles/lee.md").exists());
}

#[test]
fn the_human_adds_and_removes_preferences_and_lessons_from_echo() {
    let hub = Hub::new("memory");
    hub.ok(&["sessions"]);
    let add = |file: &str, text: &str, section: &str| {
        hub.call(
            "memory.add",
            serde_json::json!({ "file": file, "text": text, "section": section, "repo": hub.repo }),
        )
    };
    assert_eq!(add("preferences", "Never push to main", "Never do")["ok"], true);
    assert_eq!(add("lessons", "Run make db first", "")["ok"], true);
    let got = hub.call("memory.get", serde_json::json!({ "repo": hub.repo }))["result"].clone();
    let pref = &got["preferences"]["bullets"][0];
    assert_eq!(pref["section"], "Never do");
    assert!(pref["text"].as_str().unwrap().starts_with("Never push to main ("));
    let lesson = got["lessons"]["bullets"][0]["text"].as_str().unwrap().to_string();
    assert!(lesson.ends_with(", you)"), "{lesson}");
    let removed = hub.call(
        "memory.remove",
        serde_json::json!({ "file": "lessons", "text": lesson, "repo": hub.repo }),
    );
    assert_eq!(removed["ok"], true, "{removed}");
    let got = hub.call("memory.get", serde_json::json!({ "repo": hub.repo }))["result"].clone();
    assert_eq!(got["lessons"]["bullets"], serde_json::json!([]));
}

#[test]
fn a_new_worktree_gets_its_files_and_setup_before_its_worker_starts() {
    let hub = Hub::new("prep");
    std::fs::write(hub.repo.join(".env"), "KEY=1\n").unwrap();
    std::fs::create_dir_all(hub.repo.join(".echo")).unwrap();
    std::fs::write(
        hub.repo.join(".echo/settings.json"),
        r#"{"copy": [".env"], "setup": "test -f .env && echo installed > setup-ran"}"#,
    )
    .unwrap();
    let started = hub.ok(&[
        "worker",
        "start",
        "lee",
        "--spec",
        "done quickly",
        "--worktree",
        "new:chore/prep",
    ]);
    assert!(started.contains("Started w1"), "{started}");
    let tree = hub.state.join("worktrees/repo/chore-prep");
    assert_eq!(std::fs::read_to_string(tree.join(".env")).unwrap(), "KEY=1\n");
    assert_eq!(std::fs::read_to_string(tree.join("setup-ran")).unwrap(), "installed\n");
    assert!(hub.wait().contains("done (done) from w1"));

    // A setup that fails starts no agent, and the start says why.
    std::fs::write(
        hub.repo.join(".echo/settings.json"),
        r#"{"setup": "echo no network; exit 3"}"#,
    )
    .unwrap();
    let err = hub.fails(&[
        "worker",
        "start",
        "lee",
        "--spec",
        "done quickly",
        "--worktree",
        "new:chore/broken",
    ]);
    assert!(
        err.contains("the setup failed (exit 3)") && err.contains("no network"),
        "{err}"
    );
    // Working in place runs no setup.
    hub.ok(&["worker", "start", "lee", "--spec", "done quickly"]);
}

#[test]
fn a_repos_worktree_settings_are_set_from_echo_and_checked_first() {
    let hub = Hub::new("reposet");
    hub.ok(&["sessions"]);
    let set = hub.call(
        "repo.settings.set",
        serde_json::json!({ "repo": hub.repo, "settings": { "setup": "pnpm install", "copy": [".env"] } }),
    );
    assert_eq!(set["result"]["setup"], "pnpm install", "{set}");
    let bad = hub.call(
        "repo.settings.set",
        serde_json::json!({ "repo": hub.repo, "settings": { "copy": ["../secrets"] } }),
    );
    assert!(bad["error"].as_str().unwrap().contains("inside the repo"), "{bad}");
    let got = hub.call("repo.settings.get", serde_json::json!({ "repo": hub.repo }));
    assert_eq!(
        got["result"]["copy"],
        serde_json::json!([".env"]),
        "a refused change leaves the file as it was"
    );
    hub.call(
        "repo.settings.set",
        serde_json::json!({ "repo": hub.repo, "settings": { "setup": "" } }),
    );
    let got = hub.call("repo.settings.get", serde_json::json!({ "repo": hub.repo }));
    assert!(got["result"]["setup"].is_null());
}

#[test]
fn a_lesson_from_a_final_report_reaches_the_repos_lessons() {
    let hub = Hub::new("lesson");
    hub.ok(&["worker", "start", "lee", "--spec", "lesson"]);
    let heard = hub.ok(&["wait", "--timeout", "15"]);
    assert!(
        heard.contains("Lessons added:\n- Run make db before the tests"),
        "{heard}"
    );
    let repos: Vec<_> = std::fs::read_dir(hub.state.join("memory/repos"))
        .unwrap()
        .flatten()
        .collect();
    assert_eq!(repos.len(), 1);
    assert!(repos[0].file_name().to_string_lossy().starts_with("repo-"));
    let lessons = std::fs::read_to_string(repos[0].path().join("lessons.md")).unwrap();
    assert!(lessons.contains("- Run make db before the tests ("), "{lessons}");
    assert!(lessons.trim_end().ends_with(", w1)"), "{lessons}");
}

#[test]
fn a_final_report_stays_in_echo_until_dismissed() {
    let hub = Hub::new("dismiss");
    hub.ok(&["worker", "start", "lee", "--spec", "done quickly"]);
    hub.eventually("w1 to finish", || snapshot(&hub)["workers"][0]["phase"] == "done");
    let row = snapshot(&hub)["workers"][0].clone();
    assert!(row["settledAt"].is_i64(), "{row}");
    // The Orchestrator tidying up does not take the report off Echo's Done list.
    hub.ok(&["worker", "close", "w1"]);
    assert_eq!(snapshot(&hub)["workers"][0]["id"], "w1");
    hub.call("worker.dismiss", serde_json::json!({ "id": 1 }));
    assert_eq!(snapshot(&hub)["workers"], serde_json::json!([]));
}

#[test]
fn a_repo_runs_several_orchestrators_and_each_hears_only_its_workers() {
    let hub = Hub::new("agents");
    hub.ok(&["status"]);
    let repo = hub.repo_key();
    let a = hub.call(
        "agent.open",
        serde_json::json!({ "repo": repo, "kind": "orchestrator", "name": "Rerank" }),
    );
    let b = hub.call(
        "agent.open",
        serde_json::json!({ "repo": repo, "kind": "orchestrator" }),
    );
    let (a, b) = (
        a["result"]["agent"].as_i64().unwrap(),
        b["result"]["agent"].as_i64().unwrap(),
    );
    assert_ne!(a, b);
    let sessions = hub.call("sessions.list", serde_json::json!({}));
    let agents = sessions["result"]["sessions"][0]["agents"].as_array().unwrap().clone();
    assert_eq!(agents.len(), 2);
    assert_eq!(agents[0]["name"], "Rerank");
    assert!(agents.iter().all(|agent| agent["live"] == true));

    // `echoctl worker start` in b's terminal carries HUB_AGENT=b.
    let started = hub.run_with(
        &["worker", "start", "lee", "--spec", "done quickly"],
        &[("HUB_AGENT", &b.to_string())],
    );
    assert!(started.status.success(), "{}", String::from_utf8_lossy(&started.stderr));
    hub.eventually("w1 to finish", || snapshot(&hub)["workers"][0]["phase"] == "done");
    assert_eq!(snapshot(&hub)["workers"][0]["agent"], b);
    let listed = |agent: i64| {
        let out = hub.run_with(&["worker", "list", "--json"], &[("HUB_AGENT", &agent.to_string())]);
        serde_json::from_slice::<serde_json::Value>(&out.stdout).unwrap()["workers"]
            .as_array()
            .unwrap()
            .len()
    };
    assert_eq!(
        (listed(a), listed(b)),
        (0, 1),
        "each Orchestrator lists only its own Workers"
    );
    let for_a = hub.call(
        "wait",
        serde_json::json!({ "repo": repo, "agent": a, "timeout_ms": 500 }),
    );
    assert_eq!(for_a["result"]["messages"].as_array().map(Vec::len), Some(0), "{for_a}");
    let for_b = hub.call(
        "wait",
        serde_json::json!({ "repo": repo, "agent": b, "timeout_ms": 5000 }),
    );
    assert_eq!(for_b["result"]["messages"][0]["kind"], "done", "{for_b}");

    hub.call("agent.forget", serde_json::json!({ "agent": a }));
    let sessions = hub.call("sessions.list", serde_json::json!({}));
    assert_eq!(sessions["result"]["sessions"][0]["agents"].as_array().unwrap().len(), 1);
}

#[test]
fn a_normal_session_puts_its_permission_prompt_under_needs_you() {
    let hub = Hub::new("normal");
    hub.ok(&["status"]);
    let repo = hub.repo_key();
    // The fake agent runs the script its Normal session is named after.
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": repo, "kind": "claude", "name": "prompt me" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    assert_eq!(opened["result"]["kind"], "claude");
    hub.eventually("the prompt to reach Needs you", || {
        snapshot(&hub)["needs"]
            .as_array()
            .is_some_and(|needs| !needs.is_empty())
    });
    let need = snapshot(&hub)["needs"][0].clone();
    assert_eq!(need["agent"], agent);
    assert_eq!(need["worker"], serde_json::Value::Null);
    assert_eq!(need["prompt"], "Bash command\nrm -rf junk\nDo you want to proceed?");
    let decided = hub.call("decide", serde_json::json!({ "agent": agent, "approve": true }));
    assert_eq!(decided["ok"], true, "{decided}");
    hub.eventually("the prompt to clear", || {
        snapshot(&hub)["needs"].as_array().is_some_and(|needs| needs.is_empty())
    });
}

#[test]
fn an_orchestrator_puts_its_own_permission_prompt_under_needs_you() {
    let hub = Hub::new("orchprompt");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "request": "prompt me" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    hub.eventually("the prompt to reach Needs you", || {
        snapshot(&hub)["needs"]
            .as_array()
            .is_some_and(|needs| !needs.is_empty())
    });
    let need = snapshot(&hub)["needs"][0].clone();
    assert_eq!(need["agent"], agent);
    assert_eq!(need["worker"], serde_json::Value::Null);
    assert_eq!(need["profile"], "orchestrator");
    assert_eq!(need["title"], "Orchestrator");
    assert_eq!(need["prompt"], "Bash command\nrm -rf junk\nDo you want to proceed?");
    let decided = hub.call("decide", serde_json::json!({ "agent": agent, "approve": true }));
    assert_eq!(decided["ok"], true, "{decided}");
    hub.eventually("the prompt to clear", || {
        snapshot(&hub)["needs"].as_array().is_some_and(|needs| needs.is_empty())
    });
}

#[test]
fn an_unnamed_agent_is_named_after_the_first_request() {
    let hub = Hub::new("naming");
    hub.ok(&["status"]);
    let repo = hub.repo_key();
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": repo, "kind": "orchestrator" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request = serde_json::json!({ "method": "attach", "params": { "agent": agent, "rows": 30, "cols": 100 } });
    stream.write_all(format!("{request}\n").as_bytes()).unwrap();
    stream.write_all(b"/model opus\r").unwrap();
    stream.write_all(b"fix the flaky bench, then rerun it\r").unwrap();
    let name =
        || hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["agents"][0]["name"].clone();
    hub.eventually("the agent to be named", || name() != serde_json::Value::Null);
    assert_eq!(name(), "Fix the flaky bench, then rerun");
    stream.write_all(b"something else entirely\r").unwrap();
    std::thread::sleep(Duration::from_millis(500));
    assert_eq!(
        name(),
        "Fix the flaky bench, then rerun",
        "only the first request names it"
    );
    hub.call("agent.rename", serde_json::json!({ "agent": agent, "name": "Bench" }));
    assert_eq!(name(), "Bench");
}

#[test]
fn a_new_agent_starts_on_the_request_it_was_opened_with() {
    let hub = Hub::new("request");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "request",
                            "request": "Fix issue #12: the bench is flaky" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let attach = serde_json::json!({ "method": "attach", "params": { "agent": agent, "rows": 30, "cols": 100 } });
    stream.write_all(format!("{attach}\n").as_bytes()).unwrap();
    stream.set_read_timeout(Some(Duration::from_secs(15))).unwrap();
    read_until(
        &mut stream,
        &mut Vec::new(),
        "first request: Fix issue #12: the bench is flaky",
    );
}

#[test]
fn events_stream_a_snapshot_on_every_change() {
    let hub = Hub::new("events");
    hub.ok(&["status"]);
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request = serde_json::json!({ "method": "events", "params": { "repo": hub.repo_key() } });
    stream.write_all(format!("{request}\n").as_bytes()).unwrap();
    stream.set_read_timeout(Some(Duration::from_secs(15))).unwrap();
    let mut lines = BufReader::new(stream).lines();
    assert!(lines.next().unwrap().unwrap().contains("\"ok\":true"));
    let first: serde_json::Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
    assert_eq!(first["workers"].as_array().unwrap().len(), 0);

    hub.ok(&["worker", "start", "lee", "--spec", "ask about color"]);
    loop {
        let snapshot: serde_json::Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
        if snapshot["needs"].as_array().is_some_and(|needs| !needs.is_empty()) {
            assert_eq!(snapshot["needs"][0]["kind"], "question");
            assert_eq!(snapshot["needs"][0]["body"], "Which color?");
            assert_eq!(snapshot["workers"][0]["state"], "needs you");
            // Echo counts the quiet time up from here; `echoctl status` still gets seconds.
            assert!(snapshot["workers"][0]["quietSince"].is_i64(), "{snapshot}");
            assert!(snapshot["workers"][0].get("quietSeconds").is_none(), "{snapshot}");
            break;
        }
    }
    let status = hub.call("status", serde_json::json!({ "repo": hub.repo_key() }));
    assert!(status["result"]["workers"][0]["quietSeconds"].is_i64(), "{status}");
}

#[test]
fn events_send_nothing_while_the_repo_is_unchanged() {
    let hub = Hub::new("unchanged");
    hub.ok(&["status"]);
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request = serde_json::json!({ "method": "events", "params": { "repo": hub.repo_key() } });
    stream.write_all(format!("{request}\n").as_bytes()).unwrap();
    // Longer than the 5-second resend, so a repeated snapshot would arrive.
    stream.set_read_timeout(Some(Duration::from_secs(7))).unwrap();
    let mut lines = BufReader::new(stream).lines();
    lines.next();
    // The first snapshot, then the usage refresh it starts may change it once or twice.
    let quiet = (0..5).any(|_| lines.next().unwrap().is_err());
    assert!(quiet, "an unchanged repo kept sending snapshots");
}

#[test]
fn approving_a_prompt_presses_it_and_tells_the_orchestrator() {
    let hub = Hub::new("approve");
    hub.ok(&["worker", "start", "lee", "--spec", "prompt me"]);
    let blocker = hub.wait();
    assert!(blocker.contains("blocker from w1"), "{blocker}");
    assert!(
        blocker.contains("The prompt:\nBash command\nrm -rf junk\nDo you want to proceed?"),
        "{blocker}"
    );
    assert!(
        !blocker.contains("Worker screen") && !blocker.contains("->"),
        "{blocker}"
    );
    let mut events = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request = serde_json::json!({ "method": "events", "params": { "repo": hub.repo_key() } });
    events.write_all(format!("{request}\n").as_bytes()).unwrap();
    let mut lines = BufReader::new(events).lines();
    lines.next();
    let snapshot: serde_json::Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
    assert_eq!(snapshot["needs"][0]["kind"], "permission_prompt");
    assert_eq!(
        snapshot["needs"][0]["prompt"],
        "Bash command\nrm -rf junk\nDo you want to proceed?"
    );
    let decided = hub.call("decide", serde_json::json!({ "worker": 1, "approve": true }));
    assert_eq!(decided["ok"], true, "{decided}");
    hub.eventually("the prompt to be approved", || {
        hub.ok(&["worker", "read", "w1"]).contains("approved")
    });
    let told = hub.wait();
    assert!(told.contains("human from w1"), "{told}");
    assert!(told.contains("The human approved this permission prompt"));
    assert!(told.contains("rm -rf junk"));
    let again = hub.call("decide", serde_json::json!({ "worker": 1, "approve": true }));
    assert_eq!(again["ok"], false, "a cleared prompt cannot be approved twice");
}

#[test]
fn denying_a_prompt_tells_the_worker_why() {
    let hub = Hub::new("deny");
    hub.ok(&["worker", "start", "lee", "--spec", "prompt me"]);
    hub.wait();
    hub.call(
        "decide",
        serde_json::json!({ "worker": 1, "approve": false, "note": "Use trash instead." }),
    );
    hub.eventually("the worker to hear the denial", || {
        let screen = hub.ok(&["worker", "read", "w1"]);
        screen.contains("denied:") && screen.contains("Use trash instead.")
    });
    assert!(hub.wait().contains("The human denied this permission prompt"));
}

#[test]
fn a_human_reply_in_the_app_is_reported() {
    let hub = Hub::new("hreply");
    hub.ok(&["worker", "start", "lee", "--spec", "ask about color"]);
    hub.wait();
    let replied = hub.call(
        "reply",
        serde_json::json!({ "id": 1, "body": "green", "by_human": true }),
    );
    assert_eq!(replied["ok"], true, "{replied}");
    let messages = hub.wait();
    assert!(
        messages.contains("The human answered question #1 from w1 in the Hub App:\ngreen"),
        "{messages}"
    );
    assert!(messages.contains("answer was green"));
}

#[test]
fn a_worker_diff_shows_its_branch_and_a_review_reaches_it() {
    let hub = Hub::new("review");
    hub.ok(&[
        "worker",
        "start",
        "lee",
        "--spec",
        "echo",
        "--worktree",
        "new:feat/review",
    ]);
    let listed = hub.call("worker.list", serde_json::json!({ "repo": hub.repo_key() }));
    let cwd = PathBuf::from(
        listed["result"]["workers"][0]["cwd"]
            .as_str()
            .unwrap_or_else(|| panic!("{listed}")),
    );
    let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam"];
    // The Worker commits one change and leaves a new file uncommitted.
    std::fs::write(cwd.join("README.md"), "# test\nworker line\n").unwrap();
    git(&cwd, &[&commit[..], &["worker change"]].concat());
    std::fs::write(cwd.join("notes.txt"), "new file\n").unwrap();
    // Main moves on meanwhile; that is not the Worker's change.
    std::fs::write(hub.repo.join("MAIN.md"), "main only\n").unwrap();
    git(&hub.repo, &["add", "."]);
    git(&hub.repo, &[&commit[..], &["main change"]].concat());

    let diff = hub.call("worker.diff", serde_json::json!({ "id": 1 }));
    let text = diff["result"]["diff"].as_str().unwrap_or_else(|| panic!("{diff}"));
    assert!(text.contains("+worker line"), "{text}");
    assert!(text.contains("+++ b/notes.txt") && text.contains("+new file"), "{text}");
    assert!(!text.contains("MAIN.md"), "{text}");
    assert_eq!(diff["result"]["truncated"], false);

    let sent = hub.call(
        "worker.review",
        serde_json::json!({ "id": 1, "to": "worker", "body": "README.md:2 say why" }),
    );
    assert_eq!(sent["ok"], true, "{sent}");
    hub.eventually("the review to be typed into the Worker", || {
        hub.ok(&["worker", "read", "w1"]).contains("got: README.md:2 say why")
    });
    hub.call(
        "worker.review",
        serde_json::json!({ "id": 1, "to": "orchestrator", "body": "notes.txt:1 drop this file" }),
    );
    let messages = hub.wait();
    assert!(
        messages.contains("The human sent w1 a review of its changes in Echo:\nREADME.md:2 say why"),
        "{messages}"
    );
    assert!(
        messages
            .contains("The human reviewed w1's changes in Echo and wants them addressed:\nnotes.txt:1 drop this file"),
        "{messages}"
    );
}

#[test]
fn a_fan_out_runs_one_task_three_ways_and_the_pick_is_merged() {
    let hub = Hub::new("fanout");
    hub.ok(&["status"]);
    let profiles = hub.call("profiles.list", serde_json::json!({}));
    let naruto = profiles["result"]["profiles"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["name"] == "naruto")
        .cloned();
    assert_eq!(
        naruto.map(|p| p["writes"].clone()),
        Some(serde_json::json!(true)),
        "{profiles}"
    );
    let fanned = hub.call(
        "worker.fanout",
        serde_json::json!({ "repo": hub.repo_key(), "profile": "lee", "spec": "done", "title": "Try it",
                            "branch": "feat/try", "count": 3 }),
    );
    assert_eq!(
        fanned["result"]["workers"],
        serde_json::json!(["w1", "w2", "w3"]),
        "{fanned}"
    );
    let workers =
        || hub.call("worker.list", serde_json::json!({ "repo": hub.repo_key() }))["result"]["workers"].clone();
    hub.eventually("every try to finish", || {
        workers().as_array().unwrap().iter().all(|w| w["state"] == "done")
    });
    let tries = workers();
    let by_branch = |branch: &str| {
        let row = tries
            .as_array()
            .unwrap()
            .iter()
            .find(|w| w["branch"] == branch)
            .unwrap();
        (
            row["id"].as_str().unwrap().to_string(),
            PathBuf::from(row["cwd"].as_str().unwrap()),
        )
    };
    let (winner_id, winner) = by_branch("feat/try-2");
    let (_, loser) = by_branch("feat/try-1");
    std::fs::write(winner.join("picked.txt"), "picked\n").unwrap();
    hub.wait();

    let number: i64 = winner_id[1..].parse().unwrap();
    let picked = hub.call("worker.pick", serde_json::json!({ "id": number }));
    assert_eq!(picked["result"]["into"], "main", "{picked}");
    assert_eq!(picked["result"]["closed"].as_array().unwrap().len(), 2, "{picked}");
    assert_eq!(
        std::fs::read_to_string(hub.repo.join("picked.txt")).unwrap(),
        "picked\n"
    );
    assert!(!loser.exists(), "the losing worktree is removed");
    let ids: Vec<String> = snapshot(&hub)["workers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|w| w["id"].as_str().unwrap().to_string())
        .collect();
    assert_eq!(ids, vec![winner_id.clone()], "only the kept try stays in Echo");
    assert!(
        git(&hub.repo, &["branch", "--list", "feat/try-1"]).contains("feat/try-1"),
        "its branch stays"
    );
    let messages = hub.wait();
    assert!(
        messages.contains(&format!(
            "The human picked {winner_id} of a fan-out in Echo and merged feat/try-2 into main."
        )),
        "{messages}"
    );
}

#[test]
fn an_orchestrator_in_its_own_worktree_keeps_its_workers_there() {
    let hub = Hub::new("place");
    hub.ok(&["status"]);
    let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam"];
    git(&hub.repo, &["branch", "fix/old"]);
    let open = |params: serde_json::Value| {
        let opened = hub.call("agent.open", params);
        assert_eq!(opened["ok"], true, "{opened}");
        opened["result"]["agent"].as_i64().unwrap()
    };
    let login = open(
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "new_branch": "feat/login", "base": "main" }),
    );
    let old =
        open(serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "sleeper", "branch": "fix/old" }));
    let here =
        open(serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "sleeper", "branch": "main" }));
    let agents = hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["agents"].clone();
    let agent = |id: i64| {
        agents
            .as_array()
            .unwrap()
            .iter()
            .find(|a| a["id"] == id)
            .unwrap()
            .clone()
    };
    let home = PathBuf::from(agent(login)["cwd"].as_str().unwrap());
    assert!(home.ends_with("feat-login"), "{}", home.display());
    assert_eq!(agent(login)["branch"], "feat/login");
    assert!(agent(old)["cwd"].as_str().unwrap().ends_with("fix-old"));
    assert_eq!(
        agent(here)["cwd"],
        serde_json::Value::Null,
        "main is the repo's own checkout"
    );

    // The Orchestrator commits on its branch; its Workers start from there, not from main.
    std::fs::write(home.join("README.md"), "# login\n").unwrap();
    git(&home, &[&commit[..], &["login work"]].concat());
    let start = |worktree: &str| {
        let started = hub.call(
            "worker.start",
            serde_json::json!({ "repo": hub.repo_key(), "profile": "lee", "spec": "sleep", "agent": login, "worktree": worktree }),
        );
        PathBuf::from(started["result"]["cwd"].as_str().unwrap_or_else(|| panic!("{started}")))
    };
    assert_eq!(start("current"), home, "in place means the Orchestrator's worktree");
    let branched = start("new:feat/form");
    assert_eq!(
        std::fs::read_to_string(branched.join("README.md")).unwrap(),
        "# login\n"
    );

    let branches = hub.call("branches.list", serde_json::json!({ "repo": hub.repo_key() }))["result"].clone();
    assert_eq!(branches["current"], "main");
    let row = branches["branches"]
        .as_array()
        .unwrap()
        .iter()
        .find(|b| b["name"] == "feat/login")
        .unwrap()
        .clone();
    assert_eq!(row["agent"], login, "{branches}");
}

#[test]
fn simultaneous_starts_leave_one_daemon() {
    let hub = Hub::new("race");
    let starts: Vec<_> = (0..10)
        .map(|_| {
            Command::new(env!("CARGO_BIN_EXE_echoctl"))
                .arg("daemon")
                .env("HUB_STATE", &hub.state)
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn()
                .unwrap()
        })
        .collect();
    std::thread::sleep(Duration::from_millis(1500));
    let holders = Command::new("lsof")
        .arg("-t")
        .arg(hub.state.join("hub.db"))
        .output()
        .unwrap();
    let alive = String::from_utf8_lossy(&holders.stdout).split_whitespace().count();
    for mut start in starts {
        let _ = start.kill();
        let _ = start.wait();
    }
    assert_eq!(alive, 1, "exactly one daemon holds this state folder");
}

#[test]
fn account_usage_comes_from_claude_usage() {
    let hub = Hub::new("usage");
    hub.ok(&["status"]);
    hub.call("usage.refresh", serde_json::json!({}));
    hub.eventually("usage to load", || {
        hub.call("usage", serde_json::json!({}))["result"]["limits"]
            .as_array()
            .is_some_and(|limits| limits.len() == 3)
    });
    let usage = hub.call("usage", serde_json::json!({}));
    assert_eq!(usage["result"]["limits"][0]["name"], "Session");
    assert_eq!(usage["result"]["limits"][0]["percent"], 48);
    assert_eq!(usage["result"]["limits"][0]["resets"], "Oct 17 at 4:50pm");
    assert_eq!(usage["result"]["limits"][2]["name"], "Week (Fable)");
}

#[test]
fn a_usage_read_that_prints_no_limits_is_retried() {
    let hub = Hub::new("flaky");
    let marker = hub.state.join("usage-failed-once");
    let out = hub.run_with(&["status"], &[("HUB_FAKE_USAGE_FLAKY", marker.to_str().unwrap())]);
    assert!(out.status.success());
    hub.call("usage.refresh", serde_json::json!({}));
    hub.eventually("usage to load after a retry", || {
        hub.call("usage", serde_json::json!({}))["result"]["limits"]
            .as_array()
            .is_some_and(|limits| limits.len() == 3)
    });
    assert!(marker.exists(), "the first read failed");
    assert!(hub.call("usage", serde_json::json!({}))["result"]["error"].is_null());
}

#[test]
fn what_echo_types_reaches_the_agent_as_given() {
    let hub = Hub::new("write");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "echo me" }),
    );
    let agent = serde_json::json!({ "agent": opened["result"]["agent"] });
    hub.eventually("the agent to start", || screen_of(&hub, &agent).contains("Working"));
    let mut write = agent.clone();
    write["text"] = serde_json::json!("typed by echo\r");
    let wrote = hub.call("terminal.write", write);
    assert_eq!(wrote["ok"], true, "{wrote}");
    hub.eventually("the typed line", || {
        screen_of(&hub, &agent).contains("got: typed by echo")
    });
    let ping = hub.call("ping", serde_json::json!({}));
    assert!(
        ping["result"]["exe"]
            .as_str()
            .is_some_and(|exe| exe.ends_with("echoctl")),
        "{ping}"
    );
}

/// Reads an attached stream until `want` shows up.
fn read_until(reader: &mut impl Read, seen: &mut Vec<u8>, want: &str) {
    let mut buf = [0u8; 4096];
    while !String::from_utf8_lossy(seen).contains(want) {
        let n = reader
            .read(&mut buf)
            .unwrap_or_else(|e| panic!("waiting for {want:?}: {e}\n{}", String::from_utf8_lossy(seen)));
        assert!(n > 0, "stream ended before {want:?}: {}", String::from_utf8_lossy(seen));
        seen.extend_from_slice(&buf[..n]);
    }
}

#[test]
fn hub_opens_the_orchestrator_working_in_this_checkout() {
    let hub = Hub::new("which");
    hub.ok(&["status"]);
    let open = |params: serde_json::Value| {
        let opened = hub.call("agent.open", params);
        assert_eq!(opened["ok"], true, "{opened}");
        opened["result"]["agent"].as_i64().unwrap()
    };
    let first = open(serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator" }));
    let login = open(
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "new_branch": "feat/login", "base": "main" }),
    );
    let agents = hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["agents"].clone();
    let home = agents.as_array().unwrap().iter().find(|a| a["id"] == login).unwrap()["cwd"]
        .as_str()
        .unwrap()
        .to_string();
    let session = |extra: serde_json::Value| {
        let mut params = serde_json::json!({ "repo": hub.repo_key() });
        params
            .as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        let opened = hub.call("session.open", params);
        assert_eq!(opened["ok"], true, "{opened}");
        opened["result"]["agent"].as_i64().unwrap()
    };
    assert_eq!(session(serde_json::json!({ "checkout": home })), login, "its worktree");
    assert_eq!(
        session(serde_json::json!({ "checkout": hub.repo_key() })),
        first,
        "the repo's own checkout"
    );
    assert_eq!(session(serde_json::json!({})), first, "an older client");
}

#[test]
fn an_attached_terminal_passes_its_resize_on() {
    use portable_pty::{native_pty_system, CommandBuilder, PtySize};
    let hub = Hub::new("winch");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "size me" }),
    );
    let id = opened["result"]["agent"].as_i64().unwrap();
    let agent = serde_json::json!({ "agent": id });
    let mut enter = agent.clone();
    enter["text"] = serde_json::json!("\r");

    // `echoctl attach --echo`, as an Echo pane runs it, in a terminal that grows after it attaches.
    let size = |rows, cols| PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    };
    let pair = native_pty_system().openpty(size(16, 47)).unwrap();
    let mut command = CommandBuilder::new(env!("CARGO_BIN_EXE_echoctl"));
    command.args(["attach", "--echo", &format!("a{id}")]);
    command.env("HUB_STATE", &hub.state);
    let mut child = pair.slave.spawn_command(command).unwrap();
    let mut output = pair.master.try_clone_reader().unwrap();
    std::thread::spawn(move || std::io::copy(&mut output, &mut std::io::sink()));
    hub.eventually("the pane to attach at its size", || {
        hub.call("terminal.write", enter.clone());
        screen_of(&hub, &agent).contains("size: 16 47")
    });
    pair.master.resize(size(61, 144)).unwrap();
    hub.eventually("the resize to reach the agent", || {
        hub.call("terminal.write", enter.clone());
        screen_of(&hub, &agent).contains("size: 61 144")
    });
    child.kill().unwrap();
}

/// What a terminal shows now: its redrawn screen, read without resizing it.
fn screen_of(hub: &Hub, target: &serde_json::Value) -> String {
    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request = serde_json::json!({ "method": "attach", "params": target });
    stream.write_all(format!("{request}\n").as_bytes()).unwrap();
    stream.set_read_timeout(Some(Duration::from_millis(500))).unwrap();
    let mut seen = Vec::new();
    let mut buf = [0u8; 4096];
    while let Ok(n) = stream.read(&mut buf) {
        if n == 0 {
            break;
        }
        seen.extend_from_slice(&buf[..n]);
    }
    String::from_utf8_lossy(&seen).into_owned()
}

/// `echoctl mux` in a terminal of its own, as an Echo pane runs it: what it prints, and keys to type.
struct MuxPane {
    output: std::sync::Arc<std::sync::Mutex<Vec<u8>>>,
    keys: Box<dyn Write + Send>,
    child: Box<dyn portable_pty::Child + Send + Sync>,
}

impl MuxPane {
    fn start(hub: &Hub, line: &str) -> MuxPane {
        use portable_pty::{native_pty_system, CommandBuilder, PtySize};
        let pair = native_pty_system()
            .openpty(PtySize {
                rows: 30,
                cols: 100,
                pixel_width: 0,
                pixel_height: 0,
            })
            .unwrap();
        let mut command = CommandBuilder::new(env!("CARGO_BIN_EXE_echoctl"));
        command.arg("mux");
        command.env("HUB_STATE", &hub.state);
        command.env("HUB_SHELL", "/bin/sh");
        command.env("HUB_MUX", line);
        let child = pair.slave.spawn_command(command).unwrap();
        let output = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let sink = std::sync::Arc::clone(&output);
        let mut reader = pair.master.try_clone_reader().unwrap();
        std::thread::spawn(move || {
            let mut buf = [0u8; 4096];
            while let Ok(n) = reader.read(&mut buf) {
                if n == 0 {
                    break;
                }
                sink.lock().unwrap().extend_from_slice(&buf[..n]);
            }
        });
        let keys = pair.master.take_writer().unwrap();
        MuxPane { output, keys, child }
    }

    fn wait_for(&self, want: &str) {
        let deadline = Instant::now() + Duration::from_secs(15);
        loop {
            let seen = String::from_utf8_lossy(&self.output.lock().unwrap()).into_owned();
            if seen.contains(want) {
                return;
            }
            assert!(Instant::now() < deadline, "no {want:?} in {seen}");
            std::thread::sleep(Duration::from_millis(100));
        }
    }

    fn clear(&self) {
        self.output.lock().unwrap().clear();
    }

    fn type_keys(&mut self, keys: &[u8]) {
        self.keys.write_all(keys).unwrap();
        self.keys.flush().unwrap();
    }
}

#[test]
fn a_multiplexer_line_names_its_session_and_dir() {
    let hub = Hub::new("muxline");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "sleeper" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    let mux = hub.call(
        "mux.command",
        serde_json::json!({ "agent": agent, "command": "tmux new-session -A -s {session} -c {dir} {command}" }),
    );
    assert_eq!(mux["result"]["session"], format!("echo-repo-a{agent}"), "{mux}");
    let line = mux["result"]["command"].as_str().unwrap();
    assert!(
        line.starts_with(&format!("tmux new-session -A -s echo-repo-a{agent} -c ")),
        "{line}"
    );
    assert!(line.contains(&format!("attach --follow a{agent}")), "{line}");
}

#[test]
fn a_multiplexer_line_runs_with_the_daemons_environment() {
    let hub = Hub::new("muxenv");
    hub.ok(&["status"]);
    let env = hub.call("shell.env", serde_json::json!({}));
    assert!(env["result"]["HUB_TEST_AGENT"].is_string(), "{env}");
    assert!(
        env["result"].get("TERM").is_none(),
        "the pane's terminal names itself: {env}"
    );
    // The pane's own environment lacks HUB_TEST_AGENT; only the daemon's has it.
    let pane = MuxPane::start(&hub, "printf 'agent=%s\\n' \"${HUB_TEST_AGENT##*/}\"");
    pane.wait_for("agent=fake-agent.sh");
}

#[test]
fn a_multiplexer_shows_an_agent_and_follows_it_through_restarts() {
    let hub = Hub::new("mux");
    let repo = hub.repo_key();
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": repo, "kind": "claude", "name": "echo me" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    // A stand-in for `tmux new-session -A -s {session} -c {dir} {command}`.
    let command = "printf 'mux %s in %s\\n' {session} {dir}; sh -c {command}";
    let mux = hub.call("mux.command", serde_json::json!({ "agent": agent, "command": command }));
    let mut pane = MuxPane::start(&hub, mux["result"]["command"].as_str().unwrap());
    pane.wait_for(&format!("mux echo-repo-a{agent} in {repo}"));
    pane.wait_for("Working");
    pane.type_keys(b"hello\r");
    pane.wait_for("got: hello");

    // Stopped, it shows its shell until it starts again.
    hub.call("agent.close", serde_json::json!({ "agent": agent }));
    pane.clear();
    hub.eventually("the shell to take its place", || {
        pane.type_keys(b"echo shell-$((2+3))\r");
        std::thread::sleep(Duration::from_millis(300));
        String::from_utf8_lossy(&pane.output.lock().unwrap()).contains("shell-5")
    });
    hub.call("agent.open", serde_json::json!({ "agent": agent }));
    pane.clear();
    pane.wait_for("Working");
    pane.type_keys(b"again\r");
    pane.wait_for("got: again");

    hub.call("agent.forget", serde_json::json!({ "agent": agent }));
    pane.wait_for(&format!("a{agent} is closed"));
    hub.eventually("the multiplexer to exit", || pane.child.try_wait().unwrap().is_some());
}

#[test]
fn tmux_runs_the_agent_in_its_first_pane() {
    if Command::new("tmux").arg("-V").output().is_err() {
        eprintln!("tmux is not installed; skipping");
        return;
    }
    let hub = Hub::new("tmux");
    hub.ok(&["status"]);
    let socket = format!("hubt{}", std::process::id());
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "echo me" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    // Echo's default, on a private tmux server.
    let command = format!("tmux -L {socket} new-session -A -s {{session}} -c {{dir}} {{command}}");
    let mux = hub.call("mux.command", serde_json::json!({ "agent": agent, "command": command }));
    let mut pane = MuxPane::start(&hub, mux["result"]["command"].as_str().unwrap());
    pane.wait_for("Working");
    pane.type_keys(b"hello\r");
    pane.wait_for("got: hello");
    let panes = Command::new("tmux")
        .args([
            "-L",
            &socket,
            "list-panes",
            "-t",
            &format!("echo-repo-a{agent}"),
            "-F",
            "#{pane_current_command}",
        ])
        .output()
        .unwrap();
    let _ = Command::new("tmux").args(["-L", &socket, "kill-server"]).output();
    let _ = pane.child.kill();
    assert!(panes.status.success(), "{}", String::from_utf8_lossy(&panes.stderr));
}

#[test]
fn a_terminal_agent_is_a_shell_in_its_repo() {
    let hub = Hub::new("term");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "terminal" }),
    );
    assert_eq!(opened["result"]["started"], false, "{opened}");
    let agent = serde_json::json!({ "agent": opened["result"]["agent"] });
    let mut write = agent.clone();
    write["text"] = serde_json::json!("echo in-$(basename \"$PWD\")-$((1+1))\r");
    hub.eventually("the shell to run the line", || {
        hub.call("terminal.write", write.clone());
        screen_of(&hub, &agent).contains("in-repo-2")
    });
    let agents = hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["agents"].clone();
    assert_eq!(agents[0]["kind"], "terminal", "{agents}");
    assert_eq!(agents[0]["live"], true, "always ready: {agents}");
}

#[test]
fn a_stopped_agent_shows_a_shell_until_it_starts_again() {
    let hub = Hub::new("fallback");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "claude", "name": "echo me" }),
    );
    let id = opened["result"]["agent"].clone();
    let agent = serde_json::json!({ "agent": id });
    hub.eventually("the agent to start", || screen_of(&hub, &agent).contains("Working"));
    hub.call("agent.close", agent.clone());
    let live = || {
        hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["agents"][0]["live"]
            .as_bool()
            .unwrap()
    };
    hub.eventually("the agent to stop", || !live());
    let mut write = agent.clone();
    write["text"] = serde_json::json!("echo shell-$((2+3))\r");
    hub.eventually("its shell to run the line", || {
        hub.call("terminal.write", write.clone());
        screen_of(&hub, &agent).contains("shell-5")
    });
    let resumed = hub.call("agent.open", agent.clone());
    assert_eq!(resumed["result"]["started"], true, "{resumed}");
    hub.eventually("the agent to replace its shell", || {
        let screen = screen_of(&hub, &agent);
        screen.contains("Working") && !screen.contains("shell-5")
    });
}

#[test]
fn a_new_branch_that_exists_is_worked_on_where_it_is() {
    let hub = Hub::new("reuse");
    hub.ok(&["status"]);
    let open = || {
        let opened = hub.call(
            "agent.open",
            serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "new_branch": "feat/login", "base": "main" }),
        );
        assert_eq!(opened["ok"], true, "{opened}");
        opened["result"]["agent"].as_i64().unwrap()
    };
    let (first, second) = (open(), open());
    let agents = hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["agents"].clone();
    let home = |id: i64| {
        let cwd = agents.as_array().unwrap().iter().find(|a| a["id"] == id).unwrap()["cwd"].clone();
        std::fs::canonicalize(cwd.as_str().unwrap_or_else(|| panic!("{agents}"))).unwrap()
    };
    assert_eq!(home(first), home(second), "{agents}");

    // A branch checked out in the repo itself is worked on there.
    git(&hub.repo, &["branch", "feat/here"]);
    git(&hub.repo, &["checkout", "-q", "feat/here"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "new_branch": "feat/here" }),
    );
    let id = opened["result"]["agent"].as_i64().unwrap();
    let agents = hub.call("sessions.list", serde_json::json!({}))["result"]["sessions"][0]["agents"].clone();
    let agent = agents
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["id"] == id)
        .unwrap()
        .clone();
    assert!(agent["cwd"].is_null(), "{agent}");
    assert_eq!(agent["branch"], "feat/here", "{agent}");
}

/// One HTTP request to Echo Remote: its status, headers, and body.
fn http(port: u16, method: &str, path: &str, headers: &[&str], body: &str) -> (u16, String, String) {
    let mut stream = std::net::TcpStream::connect(("127.0.0.1", port)).unwrap();
    let mut request = format!(
        "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nContent-Length: {}\r\n",
        body.len()
    );
    for header in headers {
        request.push_str(header);
        request.push_str("\r\n");
    }
    request.push_str("\r\n");
    request.push_str(body);
    stream.write_all(request.as_bytes()).unwrap();
    let mut response = String::new();
    stream.read_to_string(&mut response).unwrap();
    let (head, body) = response.split_once("\r\n\r\n").unwrap();
    let status = head.split_whitespace().nth(1).unwrap().parse().unwrap();
    (status, head.to_string(), body.to_string())
}

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

#[test]
fn echo_remote_pairs_a_phone_and_drives_an_agent() {
    let hub = Hub::new("remote");
    let port = free_port();
    let on = hub.ok(&["remote", "on", "--port", &port.to_string()]);
    assert!(on.contains("Echo Remote is on."), "{on}");
    let config: serde_json::Value =
        serde_json::from_slice(&std::fs::read(hub.state.join("remote.json")).unwrap()).unwrap();
    let token = config["token"].as_str().unwrap().to_string();
    assert!(on.contains(&format!("/#pair={token}")), "{on}");
    let mode = std::fs::metadata(hub.state.join("remote.json")).unwrap().permissions();
    assert_eq!(std::os::unix::fs::PermissionsExt::mode(&mode) & 0o777, 0o600);

    // The page is open; the ledger is not, until the phone pairs.
    let (status, _, page) = http(port, "GET", "/", &[], "");
    assert_eq!(status, 200);
    assert!(page.contains("Echo Remote"));
    assert_eq!(http(port, "GET", "/api/screen?agent=1", &[], "").0, 401);
    let json = "Content-Type: application/json";
    assert_eq!(http(port, "POST", "/api/pair", &[json], r#"{"token":"wrong"}"#).0, 403);
    let (status, head, _) = http(port, "POST", "/api/pair", &[json], &format!(r#"{{"token":"{token}"}}"#));
    assert_eq!(status, 200);
    assert!(
        head.contains(&format!(
            "Set-Cookie: echo_remote={token}; Path=/; HttpOnly; SameSite=Strict"
        )),
        "{head}"
    );
    let cookie = format!("Cookie: echo_remote={token}");

    // Only Echo's own actions, and only from its own page.
    let (status, _, body) = http(port, "POST", "/api/call/worker.start", &[json, &cookie], "{}");
    assert_eq!(status, 403, "{body}");
    let evil = "Origin: https://evil.example";
    assert_eq!(
        http(port, "POST", "/api/call/decide", &[json, &cookie, evil], "{}").0,
        403
    );
    assert_eq!(
        http(
            port,
            "POST",
            "/api/call/decide",
            &["Content-Type: text/plain", &cookie],
            "{}"
        )
        .0,
        403
    );

    // A new agent from the phone, then a message to it, read back off its screen.
    let repo = hub.repo_key();
    let (_, _, opened) = http(
        port,
        "POST",
        "/api/call/agent.open",
        &[json, &cookie],
        &serde_json::json!({ "repo": repo, "kind": "claude", "name": "echo" }).to_string(),
    );
    let opened: serde_json::Value = serde_json::from_str(&opened).unwrap();
    let agent = opened["result"]["agent"].as_i64().unwrap();
    let send = serde_json::json!({ "agent": agent, "text": "hello from the phone" }).to_string();
    let (_, _, sent) = http(port, "POST", "/api/call/terminal.send", &[json, &cookie], &send);
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&sent).unwrap()["ok"],
        true,
        "{sent}"
    );
    hub.eventually("the phone's message on the agent's screen", || {
        let (_, _, screen) = http(port, "GET", &format!("/api/screen?agent={agent}"), &[&cookie], "");
        screen.contains("got: hello from the phone")
    });

    // The ledger streams, and a permission prompt is settled from it.
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": repo, "kind": "claude", "name": "prompt me" }),
    );
    let prompted = opened["result"]["agent"].as_i64().unwrap();
    let mut stream = std::net::TcpStream::connect(("127.0.0.1", port)).unwrap();
    write!(
        stream,
        "GET /api/stream HTTP/1.1\r\nHost: 127.0.0.1\r\n{cookie}\r\n\r\n"
    )
    .unwrap();
    let mut reader = BufReader::new(stream);
    let mut world = serde_json::Value::Null;
    hub.eventually("the prompt in the stream", || {
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        if let Some(data) = line.strip_prefix("data: ") {
            world = serde_json::from_str(data).unwrap();
        }
        world["repos"][0]["needs"]
            .as_array()
            .is_some_and(|needs| !needs.is_empty())
    });
    assert_eq!(world["repos"][0]["needs"][0]["agent"], prompted);
    let decide = serde_json::json!({ "agent": prompted, "approve": true }).to_string();
    let (_, _, decided) = http(port, "POST", "/api/call/decide", &[json, &cookie], &decide);
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&decided).unwrap()["ok"],
        true,
        "{decided}"
    );
    hub.eventually("the approval on screen", || {
        let (_, _, screen) = http(port, "GET", &format!("/api/screen?agent={prompted}"), &[&cookie], "");
        screen.contains("approved")
    });

    // A new pairing link unpairs every phone; off lets the port go.
    hub.ok(&["remote", "pair"]);
    assert_eq!(
        http(port, "GET", &format!("/api/screen?agent={agent}"), &[&cookie], "").0,
        401
    );
    assert!(hub.ok(&["remote", "off"]).contains("Echo Remote is off."));
    hub.eventually("the port to close", || {
        std::net::TcpStream::connect(("127.0.0.1", port)).is_err()
    });
}

#[test]
fn ui_requests_need_echo_open_and_reach_its_snapshot() {
    let hub = Hub::new("ui");
    hub.ok(&["status"]);
    let refused = hub.fails(&["ui", "open", "README.md:1"]);
    assert!(refused.contains("Echo is not open on repo"), "{refused}");
    // An Orchestrator starts whether or not Echo is open.
    assert!(hub.ok(&["ui", "orchestrator"]).contains("Started Orchestrator a1"));

    let mut stream = UnixStream::connect(hub.state.join("hubd.sock")).unwrap();
    let request = serde_json::json!({ "method": "events", "params": { "repo": hub.repo_key() } });
    stream.write_all(format!("{request}\n").as_bytes()).unwrap();
    stream.set_read_timeout(Some(Duration::from_secs(15))).unwrap();
    let mut lines = BufReader::new(stream).lines();
    lines.next();
    lines.next();
    hub.run_with(&["ui", "open", "README.md:1"], &[("HUB_AGENT", "1")]);
    assert!(hub.fails(&["ui", "show", "w9"]).contains("no Worker w9"));
    assert!(hub.fails(&["ui", "diff", "a1"]).contains("only a Worker has a diff"));
    hub.ok(&["ui", "notify", "tests pass"]);
    let mut seen = Vec::new();
    while seen.len() < 2 {
        let snapshot: serde_json::Value = serde_json::from_str(&lines.next().unwrap().unwrap()).unwrap();
        seen = snapshot["ui"].as_array().cloned().unwrap_or_default();
    }
    assert_eq!(seen[0]["action"], "open");
    assert_eq!(seen[0]["path"], "README.md");
    assert_eq!(seen[0]["line"], 1);
    assert_eq!(seen[0]["from"], "a1");
    assert_eq!(seen[0]["root"], hub.repo_key());
    assert_eq!(seen[1]["action"], "notify");
    assert_eq!(seen[1]["text"], "tests pass");
}

#[test]
fn an_orchestrators_chat_reads_its_transcript_then_only_new_lines() {
    let hub = Hub::new("chat");
    let claude = hub.state.join("claude");
    let config = claude.display().to_string();
    // The first call starts the daemon, which reads transcripts under this folder.
    hub.run_with(&["status"], &[("CLAUDE_CONFIG_DIR", &config)]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "name": "chat" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    let read = |params: serde_json::Value| hub.call("chat.read", params)["result"].clone();
    let empty = read(serde_json::json!({ "agent": agent }));
    assert_eq!(
        (empty["supported"].as_bool(), empty["items"].as_array().map(Vec::len)),
        (Some(true), Some(0))
    );
    let session = empty["session"].as_str().unwrap().to_string();
    let file = claude.join("projects").join("repo").join(format!("{session}.jsonl"));
    std::fs::create_dir_all(file.parent().unwrap()).unwrap();
    let line = |v: serde_json::Value| format!("{v}\n");
    std::fs::write(
        &file,
        line(serde_json::json!({ "type": "user", "uuid": "u1", "message": { "content": "build it" } }))
            + &line(
                serde_json::json!({ "type": "assistant", "uuid": "a1", "message": { "content": [
                { "type": "text", "text": "Built." } ] } }),
            ),
    )
    .unwrap();
    let first = read(serde_json::json!({ "agent": agent }));
    let texts = |r: &serde_json::Value| -> Vec<String> {
        r["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["text"].as_str().unwrap().to_string())
            .collect()
    };
    assert_eq!(texts(&first), ["build it", "Built."]);
    let mut more = std::fs::OpenOptions::new().append(true).open(&file).unwrap();
    std::io::Write::write_all(
        &mut more,
        line(serde_json::json!({ "type": "user", "uuid": "u2", "message": { "content": "thanks" } })).as_bytes(),
    )
    .unwrap();
    let next = read(serde_json::json!({ "agent": agent, "session": session, "after": first["end"] }));
    assert_eq!(texts(&next), ["thanks"]);
}

#[test]
fn a_chat_message_is_typed_at_the_orchestrator_and_its_turn_shows_as_working() {
    let hub = Hub::new("chatsend");
    let claude = hub.state.join("claude");
    let chat = hub.state.join("chat.jsonl");
    let (config, file) = (claude.display().to_string(), chat.display().to_string());
    hub.run_with(&["status"], &[("CLAUDE_CONFIG_DIR", &config), ("HUB_FAKE_CHAT", &file)]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "name": "chat" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    let read = || hub.call("chat.read", serde_json::json!({ "agent": agent }))["result"].clone();
    // Its transcript is the file the fake agent writes.
    let session = read()["session"].as_str().unwrap().to_string();
    std::fs::create_dir_all(claude.join("projects/repo")).unwrap();
    std::fs::write(&chat, "").unwrap();
    std::os::unix::fs::symlink(&chat, claude.join(format!("projects/repo/{session}.jsonl"))).unwrap();
    hub.eventually("its input box", || read()["state"]["look"] == "idle");
    let sent = hub.call("chat.send", serde_json::json!({ "agent": agent, "text": "hello" }));
    assert_eq!(sent["ok"], true, "{sent}");
    hub.eventually("the Working row", || {
        let state = read()["state"].clone();
        state["look"] == "working" && state["step"] == "Bash(sleep 2)"
    });
    hub.eventually("the reply", || {
        let items = read()["items"].clone();
        items
            .as_array()
            .is_some_and(|i| i.len() == 2 && i[1]["text"] == "got: hello")
    });
}

#[test]
fn a_chat_message_is_refused_while_the_orchestrator_shows_a_prompt() {
    let hub = Hub::new("chatprompt");
    hub.ok(&["status"]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "name": "p", "request": "prompt me" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    hub.eventually("the prompt", || {
        hub.call("chat.read", serde_json::json!({ "agent": agent }))["result"]["state"]["look"] == "prompt"
    });
    let sent = hub.call("chat.send", serde_json::json!({ "agent": agent, "text": "yes" }));
    assert_eq!(sent["ok"], false);
    assert!(sent["error"].as_str().unwrap().contains("permission prompt"), "{sent}");
}

#[test]
fn a_workers_chat_says_who_typed_each_message() {
    let hub = Hub::new("chatworker");
    let claude = hub.state.join("claude");
    let config = claude.display().to_string();
    hub.run_with(&["status"], &[("CLAUDE_CONFIG_DIR", &config)]);
    let started: serde_json::Value =
        serde_json::from_str(&hub.ok(&["worker", "start", "lee", "--spec", "idle for now", "--json"])).unwrap();
    let id: i64 = started["id"].as_str().unwrap()[1..].parse().unwrap();
    let read = || hub.call("chat.read", serde_json::json!({ "worker": id }))["result"].clone();
    hub.eventually("its input box", || read()["state"]["look"] == "idle");
    let sent = hub.call("chat.send", serde_json::json!({ "worker": id, "text": "please hurry" }));
    assert_eq!(sent["ok"], true, "{sent}");
    let session = read()["session"].as_str().unwrap().to_string();
    let file = claude.join("projects/repo").join(format!("{session}.jsonl"));
    std::fs::create_dir_all(file.parent().unwrap()).unwrap();
    let user = |text: &str| serde_json::json!({ "type": "user", "message": { "content": text } }).to_string() + "\n";
    std::fs::write(
        &file,
        user("idle for now") + &user("please hurry") + &user("typed in the terminal"),
    )
    .unwrap();
    let items = read()["items"].clone();
    let from: Vec<&str> = items
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["from"].as_str().unwrap_or("-"))
        .collect();
    assert_eq!(from, ["orchestrator", "human", "-"], "{items}");
}

#[test]
fn a_renewed_orchestrators_chat_scrolls_back_into_its_earlier_session() {
    let hub = Hub::new("chatrenew");
    let claude = hub.state.join("claude");
    let config = claude.display().to_string();
    hub.run_with(&["status"], &[("CLAUDE_CONFIG_DIR", &config)]);
    let opened = hub.call(
        "agent.open",
        serde_json::json!({ "repo": hub.repo_key(), "kind": "orchestrator", "name": "renew" }),
    );
    let agent = opened["result"]["agent"].as_i64().unwrap();
    let read = |params: serde_json::Value| hub.call("chat.read", params)["result"].clone();
    let dir = claude.join("projects/repo");
    std::fs::create_dir_all(&dir).unwrap();
    let say = |text: &str| serde_json::json!({ "type": "user", "message": { "content": text } }).to_string() + "\n";
    let first = read(serde_json::json!({ "agent": agent }))["session"]
        .as_str()
        .unwrap()
        .to_string();
    std::fs::write(dir.join(format!("{first}.jsonl")), say("old one") + &say("old two")).unwrap();
    let renewed = hub.call("agent.renew", serde_json::json!({ "agent": agent }));
    assert_eq!(renewed["ok"], true, "{renewed}");
    let now = read(serde_json::json!({ "agent": agent }));
    let second = now["session"].as_str().unwrap().to_string();
    assert_ne!(first, second);
    std::fs::write(dir.join(format!("{second}.jsonl")), say("new one")).unwrap();
    let now = read(serde_json::json!({ "agent": agent }));
    let texts = |r: &serde_json::Value| -> Vec<String> {
        r["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["text"].as_str().unwrap().to_string())
            .collect()
    };
    assert_eq!(
        (texts(&now), now["more"].as_bool()),
        (vec!["new one".to_string()], Some(true))
    );
    let older = read(serde_json::json!({ "agent": agent, "before": now["start"], "page_session": second }));
    assert_eq!(
        texts(&older),
        ["old one", "old two", "Session renewed, context cleared"]
    );
    assert_eq!(
        (older["page_session"].as_str(), older["more"].as_bool()),
        (Some(first.as_str()), Some(false))
    );
}

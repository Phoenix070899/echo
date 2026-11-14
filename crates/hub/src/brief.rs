//! `echoctl brief`: what a fresh Orchestrator session needs to carry on from the daemon's state.

use serde_json::Value;

/// The first line of `text`, cut to a length that fits a line of a brief.
fn first_line(text: &str) -> String {
    let line = text.lines().find(|l| !l.trim().is_empty()).unwrap_or("").trim();
    match line.char_indices().nth(160) {
        Some((at, _)) => format!("{}…", &line[..at]),
        None => line.to_string(),
    }
}

/// How a Worker's row names what it is: its Profile alone, or `member (profile)` when it started as a Member.
pub fn who(row: &Value) -> String {
    let profile = row["profile"].as_str().unwrap_or("");
    match row["member"].as_str() {
        Some(member) => format!("{member} ({profile})"),
        None => profile.to_string(),
    }
}

/// The brief for the Workers `worker.list` gives (open ones: running, or settled and not closed) and
/// the open questions `inbox` gives.
pub fn brief(workers: &[Value], questions: &[Value]) -> String {
    let text = |v: &Value| v.as_str().unwrap_or("").to_string();
    let line = |w: &Value| {
        format!(
            "  {} {} {} {} \"{}\"",
            text(&w["id"]),
            who(w),
            text(&w["state"]),
            w["branch"].as_str().unwrap_or("in place"),
            text(&w["title"])
        )
    };
    let settled =
        |w: &&Value| ["done", "blocked", "exited", "ended", "lost"].contains(&w["state"].as_str().unwrap_or(""));
    let (done, running): (Vec<&Value>, Vec<&Value>) = workers.iter().partition(settled);
    let mut out = String::from(
        "Brief for a fresh Orchestrator session. The Hub Daemon keeps only what is listed here: \
         Workers, their branches and reports, and open questions. Give the human a Summary from it.\n",
    );
    out += "\nRunning (or waiting):\n";
    if running.is_empty() {
        out += "  none\n";
    }
    for w in running {
        out += &line(w);
        if let Some(blocker) = w["blocker"].as_str() {
            out += &format!("  [blocked: {blocker}]");
        }
        out += &format!("  quiet {}s\n", w["quiet_seconds"]);
    }
    out += "\nSettled and still open (a branch kept for its next Task, or not yet closed):\n";
    if done.is_empty() {
        out += "  none\n";
    }
    for w in done {
        out += &format!(
            "{}\n    report: {}\n",
            line(w),
            first_line(w["final_report"].as_str().unwrap_or(""))
        );
    }
    out += "\nOpen questions:\n";
    if questions.is_empty() {
        out += "  none\n";
    }
    for q in questions {
        out += &format!(
            "  #{} from w{}: {}\n",
            q["id"],
            q["worker_id"],
            first_line(q["body"].as_str().unwrap_or(""))
        );
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_brief_lists_running_settled_and_asking_workers() {
        let workers = [
            json!({ "id": "w3", "profile": "lee", "state": "running", "branch": null, "title": "run tests",
                    "quiet_seconds": 40, "blocker": "permission_prompt", "final_report": null }),
            json!({ "id": "w5", "profile": "naruto", "state": "done", "branch": "feat/x", "title": "build x",
                    "quiet_seconds": 9, "blocker": null, "final_report": "State: done\nChanged: a.rs" }),
        ];
        let questions = [json!({ "id": 12, "worker_id": 3, "body": "Which color?\nBlue or red" })];
        let text = brief(&workers, &questions);
        assert!(text.contains("w3 lee running in place \"run tests\"  [blocked: permission_prompt]  quiet 40s"));
        assert!(
            text.contains("w5 naruto done feat/x \"build x\"\n    report: State: done\n"),
            "{text}"
        );
        assert!(text.contains("#12 from w3: Which color?\n"), "{text}");
        let empty = brief(&[], &[]);
        assert_eq!(empty.matches("  none\n").count(), 3, "{empty}");
    }

    #[test]
    fn a_worker_is_named_by_its_profile_or_by_its_member_and_profile() {
        assert_eq!(who(&json!({ "profile": "lee", "member": null })), "lee");
        assert_eq!(who(&json!({ "profile": "lee" })), "lee");
        assert_eq!(
            who(&json!({ "profile": "naruto", "member": "builder" })),
            "builder (naruto)"
        );
        let workers = [
            json!({ "id": "w2", "profile": "naruto", "member": "builder", "state": "running",
                               "branch": null, "title": "t", "quiet_seconds": 1, "blocker": null,
                               "final_report": null }),
        ];
        assert!(brief(&workers, &[]).contains("w2 builder (naruto) running"));
    }
}

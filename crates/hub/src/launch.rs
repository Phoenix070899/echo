//! The Orchestrator: how the daemon starts it, and `echoctl` with no command, which attaches to it.

use std::path::Path;

use anyhow::{Context, Result};
use serde_json::json;

use crate::db::Agent;
use crate::{attach, lessons, paths, proto, repo};

/// The first message of a resumed Orchestrator session.
const RESUMED: &str = "Your terminal was restarted. Run `echoctl worker list`, give the human a Summary, \
                       and start the listener if Workers are open.";

/// Arguments after `claude` for a repo's Orchestrator: a new session, or its saved one resumed.
/// A new session given a `request` starts on it, as if the human had typed it first.
pub fn orchestrator_args(
    hub: &Path,
    repo: &Path,
    worktree: Option<(&str, &str)>,
    session_id: &str,
    resume: bool,
    request: Option<&str>,
    extra: &[String],
) -> Result<Vec<String>> {
    let state = paths::state_dir();
    let key = repo.to_string_lossy();
    let orchestrator = std::fs::read_to_string(hub.join("orchestrator.md"))?
        .replace("$ECHO_REPO", &hub.display().to_string())
        .replace(
            "$ECHO_PREFERENCES",
            &lessons::preferences_path(&state, hub).display().to_string(),
        )
        .replace(
            "$ECHO_LESSONS",
            &lessons::lessons_path(&state, &key).display().to_string(),
        );
    let preferences = lessons::preferences(hub);
    let mut prompt = format!("{orchestrator}\n\n# Preferences\n\n{preferences}");
    let known = lessons::lessons(&state, &key);
    if !known.is_empty() {
        prompt += &format!("\n\n{}\n\n{}", lessons::WORKER_INTRO, known.trim_end());
    }
    prompt += &format!("\n\nRepo for this Hub Session: {}", repo.display());
    if let Some((cwd, branch)) = worktree {
        prompt += &format!(
            "\nYou work in your own worktree {cwd} on branch {branch}, apart from other Orchestrators in this repo. \
             Workers you start in place work there too, and new Worker worktrees branch from it."
        );
    }
    let name = repo
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut args = vec![
        "-n".to_string(),
        format!("echo: {name}"),
        "--plugin-dir".into(),
        hub.join("mod").display().to_string(),
        "--plugin-dir".into(),
        hub.join("skills").display().to_string(),
        "--add-dir".into(),
        hub.display().to_string(),
        "--add-dir".into(),
        lessons::memory_dir(&state).display().to_string(),
        "--append-system-prompt".into(),
        prompt,
    ];
    args.extend(extra.iter().cloned());
    if resume {
        args.extend(["--resume".into(), session_id.into(), "--".into(), RESUMED.into()]);
    } else {
        args.extend(["--session-id".into(), session_id.into()]);
        args.extend(first_request(request));
    }
    Ok(args)
}

/// Arguments after `claude` for a Normal session: plain Claude Code in the repo, new or resumed,
/// with only the skills for driving Echo added (`skills/`), not the Orchestrator's view.
pub fn claude_args(hub: &Path, agent: &Agent, resume: bool, request: Option<&str>, extra: &[String]) -> Vec<String> {
    let name = agent.name.clone().unwrap_or_else(|| {
        let repo = Path::new(&agent.repo);
        repo.file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default()
    });
    let mut args = vec![
        "-n".to_string(),
        format!("echo: {name}"),
        "--plugin-dir".into(),
        hub.join("skills").display().to_string(),
    ];
    args.extend(extra.iter().cloned());
    if resume {
        args.extend(["--resume".into(), agent.session_id.clone()]);
    } else {
        args.extend(["--session-id".into(), agent.session_id.clone()]);
        args.extend(first_request(request));
    }
    args
}

/// A new session's first message, after `--` so a request starting with `-` is not an option.
fn first_request(request: Option<&str>) -> Vec<String> {
    request
        .map(|r| vec!["--".to_string(), r.to_string()])
        .unwrap_or_default()
}

/// Starts an Orchestrator in the Hub Daemon, or finds it running, then attaches to it: the agent
/// named first (`echoctl a10`), else the Orchestrator working in this checkout, else the repo's first.
pub fn run(mut extra: Vec<String>) -> Result<()> {
    if let Some(id) = extra.first().and_then(|first| agent_id(first)) {
        extra.remove(0);
        let opened = proto::call("agent.open", json!({ "agent": id, "args": extra }))
            .with_context(|| format!("starting a{id}"))?;
        return attach::run(json!({ "agent": opened["agent"] }), &format!("a{id}"));
    }
    let here = std::env::current_dir()?;
    let repo = repo::root(&here)?.display().to_string();
    let checkout = repo::toplevel(&here)?.display().to_string();
    let opened = proto::call(
        "session.open",
        json!({ "repo": repo, "checkout": checkout, "args": extra }),
    )
    .context("starting the Orchestrator")?;
    attach::run(json!({ "agent": opened["agent"] }), "the Orchestrator")
}

/// `a10` as 10.
pub fn agent_id(text: &str) -> Option<i64> {
    text.strip_prefix('a')?.parse().ok()
}

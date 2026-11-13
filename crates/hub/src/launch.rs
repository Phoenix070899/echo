//! The Orchestrator: how the daemon starts it, and `echoctl` with no command, which attaches to it.

use std::path::Path;

use anyhow::{Context, Result};
use serde_json::json;

use crate::cli::Start;
use crate::db::Agent;
use crate::team::Team;
use crate::{attach, lessons, paths, proto, repo, settings};

/// The first message of a resumed Orchestrator session.
pub const RESUMED: &str = "Your terminal was restarted. Run `echoctl worker list`, give the human a Summary, \
                       and start the listener if Workers are open.";

/// The first message of an Orchestrator session the daemon renewed to clear its context.
pub const RENEWED: &str = "Your session was renewed to clear its context; nothing else changed. Run `echoctl brief`, \
                           give the human a Summary of what is open, and start the listener if Workers are open.";

/// What a repo's Orchestrator starts with: a new session, or its saved one resumed. A new session
/// given a `request` starts on it, as if the human had typed it first. Its `team`'s rules replace
/// the human's same-named ones and its instructions follow them (features/0081).
pub fn orchestrator_start(
    hub: &Path,
    repo: &Path,
    worktree: Option<(&str, &str)>,
    session: Session,
    team: Option<&Team>,
) -> Result<Start> {
    start_in(&paths::state_dir(), hub, repo, worktree, session, team)
}

fn start_in(
    state: &Path,
    hub: &Path,
    repo: &Path,
    worktree: Option<(&str, &str)>,
    session: Session,
    team: Option<&Team>,
) -> Result<Start> {
    let key = repo.to_string_lossy();
    let orchestrator = std::fs::read_to_string(hub.join("orchestrator.md"))?
        .replace("$ECHO_REPO", &hub.display().to_string())
        .replace(
            "$ECHO_PREFERENCES",
            &lessons::preferences_path(state, hub).display().to_string(),
        )
        .replace(
            "$ECHO_LESSONS",
            &lessons::lessons_path(state, &key).display().to_string(),
        );
    let preferences = lessons::preferences(hub);
    let mut prompt = format!("{orchestrator}\n\n# Preferences\n\n{preferences}");
    let human = settings::read(state).unwrap_or_default();
    let known = lessons::lessons(state, &key);
    if !known.is_empty() && settings::orchestrator_lessons(&human) {
        prompt += &format!("\n\n{}\n\n{}", lessons::WORKER_INTRO, known.trim_end());
    }
    let mut rules = settings::Rules::from(&human);
    if let Some(setup) = team.and_then(|team| team.rules.as_ref()) {
        rules = rules.with_team(setup);
    }
    let rules = rules.overrides();
    if !rules.is_empty() {
        prompt += &format!("\n\n{rules}");
    }
    if let Some(instructions) = team
        .and_then(|team| team.instructions.as_deref())
        .map(str::trim)
        .filter(|text| !text.is_empty())
    {
        prompt += &format!("\n\n# Team instructions\n\n{instructions}");
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
    let first = if session.resume {
        Some(RESUMED.to_string())
    } else {
        session.request
    };
    Ok(Start {
        title: format!("echo: {name}"),
        prompt,
        dirs: vec![hub.to_path_buf(), lessons::memory_dir(state)],
        plugins: vec![hub.join("mod"), hub.join("skills")],
        model: session.model,
        effort: session.effort,
        session_id: session.id,
        resume: session.resume,
        first,
        extra: session.extra,
        ..Start::default()
    })
}

/// An agent session as the daemon opens it: which saved session, and what the human added.
pub struct Session {
    pub id: String,
    pub resume: bool,
    pub request: Option<String>,
    pub model: Option<String>,
    /// How hard an Orchestrator thinks; a Normal session keeps its CLI's own.
    pub effort: Option<String>,
    pub extra: Vec<String>,
}

/// What a Normal session starts with: plain Claude Code in the repo, new or resumed, with only
/// the skills for driving Echo added (`skills/`), not the Orchestrator's view.
pub fn normal_start(hub: &Path, agent: &Agent, session: Session) -> Start {
    let name = agent.name.clone().unwrap_or_else(|| {
        let repo = Path::new(&agent.repo);
        repo.file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default()
    });
    Start {
        title: format!("echo: {name}"),
        plugins: vec![hub.join("skills")],
        model: session.model,
        session_id: session.id,
        first: if session.resume { None } else { session.request },
        resume: session.resume,
        extra: session.extra,
        ..Start::default()
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::team;

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("hub-launch-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn prompt(state: &Path, team: Option<&team::Team>) -> String {
        let session = Session {
            id: "s".into(),
            resume: false,
            request: None,
            model: None,
            effort: None,
            extra: vec![],
        };
        start_in(
            state,
            &paths::hub_dir(),
            Path::new("/tmp/some-repo"),
            None,
            session,
            team,
        )
        .unwrap()
        .prompt
    }

    fn team_of(text: &str) -> team::Team {
        team::parse(text).unwrap()
    }

    #[test]
    fn a_teams_rules_replace_the_humans_and_absent_keys_fall_through() {
        let state = scratch("rules");
        std::fs::write(state.join("settings.json"), r#"{"review": true, "maxWorkers": 6}"#).unwrap();
        let plain = prompt(&state, None);
        assert!(plain.contains("At most 6 Workers"));
        assert!(!plain.contains("Skip the sasuke verification"));
        let team = team_of(r#"{"rules": {"review": false}}"#);
        let merged = prompt(&state, Some(&team));
        assert!(
            merged.contains("Skip the sasuke verification"),
            "the Team's review:false wins"
        );
        assert!(
            merged.contains("At most 6 Workers"),
            "maxWorkers falls through to the human's"
        );
        let team = team_of(r#"{"rules": {"maxWorkers": 2, "planApproval": false}}"#);
        let merged = prompt(&state, Some(&team));
        assert!(merged.contains("At most 2 Workers"));
        assert!(merged.contains("without waiting for a \"go\""));
        assert!(!merged.contains("At most 6 Workers"));
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn a_teams_instructions_follow_the_rules_and_come_before_the_repo_line() {
        let state = scratch("instructions");
        std::fs::write(state.join("settings.json"), r#"{"maxWorkers": 6}"#).unwrap();
        let team = team_of(r#"{"instructions": "  Prefer small Tasks.  "}"#);
        let text = prompt(&state, Some(&team));
        let rules = text.find("# The human's Settings").unwrap();
        let heading = text
            .find("# Team instructions\n\nPrefer small Tasks.\n\nRepo for this Hub Session")
            .unwrap();
        assert!(rules < heading, "after the rules block");
        assert!(text.ends_with("Repo for this Hub Session: /tmp/some-repo"));
        assert!(!prompt(&state, None).contains("# Team instructions"));
        let blank = team_of(r#"{"instructions": "  "}"#);
        assert!(!prompt(&state, Some(&blank)).contains("# Team instructions"));
        let _ = std::fs::remove_dir_all(&state);
    }
}

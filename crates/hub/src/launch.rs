//! The Orchestrator: how the daemon starts it, and `echoctl` with no command, which attaches to it.

use std::path::Path;

use anyhow::{Context, Result};
use serde_json::json;

use crate::action::{self, Action};
use crate::cli::{self, Start};
use crate::db::Agent;
use crate::team::{Member, Team};
use crate::{attach, lessons, paths, profile, proto, repo, settings};

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
    if let Some(team) = team.filter(|team| !team.members.is_empty()) {
        let actions = action::list(hub);
        let section = workers_section(team, &actions, &|member| member_facts(state, hub, repo, team, member));
        prompt += &format!("\n\n{section}");
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

/// What the "Your Workers" section says about a Member that its file does not: its Profile's
/// description and the model its Worker will run on.
pub struct MemberFacts {
    pub description: String,
    /// `None` when no level names a model; the CLI then runs its own default.
    pub model: Option<String>,
}

/// A Member's Profile description and resolved model, as the daemon starts its Worker (features/0085).
fn member_facts(state: &Path, hub: &Path, repo: &Path, team: &Team, member: &Member) -> MemberFacts {
    let Ok(loaded) = profile::load(hub, state, Some(repo), &member.profile) else {
        return MemberFacts {
            description: String::new(),
            model: member.model.clone(),
        };
    };
    let model = profile::resolve(
        state,
        Some(repo),
        &loaded,
        Some(team),
        Some(member),
        &cli::Choice::default(),
    )
    .ok()
    .and_then(|(_, model, _)| model);
    MemberFacts {
        description: loaded.description,
        model,
    }
}

/// The generated "Your Workers" section of a Team's Orchestrator prompt (features/0086): a line
/// for each Member in tree order, the tree's hand-offs as sentences, how to start a Worker, and the
/// rule to start them by these ids. A Member's own role text is not copied into it.
pub fn workers_section(team: &Team, actions: &[Action], facts: &dyn Fn(&Member) -> MemberFacts) -> String {
    let mut lines = vec![
        "# Your Workers".to_string(),
        String::new(),
        "This Team names the Workers you start, in tree order; among siblings, prefer the earlier. \
         The tree is a plan of hand-offs that you carry out: a Worker never starts another Worker, and every one still reports only to you."
            .to_string(),
        String::new(),
    ];
    for member in &team.members {
        let action = actions.iter().find(|action| action.id == member.action);
        lines.push(member_line(team, member, action, &facts(member)));
    }
    let handoffs: Vec<String> = team.members.iter().flat_map(|member| handoffs(team, member)).collect();
    if !handoffs.is_empty() {
        lines.push(String::new());
        lines.push("Hand-offs:".to_string());
        lines.extend(handoffs.into_iter().map(|sentence| format!("- {sentence}")));
        lines.push(
            "`--from-report <w>` is an option of `echoctl worker task`: it appends that Worker's Final Report to a settled \
             Worker's next Task. A Worker you start new gets the report quoted in its spec file."
                .to_string(),
        );
    }
    lines.push(String::new());
    lines.push(
        "Start a Worker with `echoctl worker start <id> --spec-file <file> --worktree <current|new:<type>/<task>|path:<worktree>|worker:<w>>`, \
         where `<id>` is one of the ids above. Start Workers by these ids, not by Profile name, and use `echoctl profile list` only \
         for a Profile this list lacks. A worktree named above is a hint, and `new` stands for `new:<type>/<task>`."
            .to_string(),
    );
    lines.join("\n")
}

fn member_line(team: &Team, member: &Member, action: Option<&Action>, facts: &MemberFacts) -> String {
    let indent = "  ".repeat(depth(team, member) - 1);
    let title = match action {
        Some(action) => action.title.as_str(),
        None if member.action == action::CUSTOM => "Custom",
        None => member.action.as_str(),
    };
    let mut parts = vec![format!(
        "{indent}- `{}` ({title}, from Profile `{}`):",
        member.id, member.profile
    )];
    if let Some(action) = action {
        parts.push(sentence(&action.routing));
    }
    parts.push(sentence(&facts.description));
    parts.push(match &facts.model {
        Some(model) => format!("Runs on {model}."),
        None => "Runs on the default model.".to_string(),
    });
    let worktree = member
        .worktree
        .as_deref()
        .or(action.map(|action| action.worktree.as_str()))
        .unwrap_or("current");
    parts.push(format!("Worktree: {worktree}."));
    parts
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

/// The sentences for what follows `member`: its first `verify` child is the daemon's verifier, and
/// every other child is a hand-off of its report.
fn handoffs(team: &Team, member: &Member) -> Vec<String> {
    let verifier = team.verifier_of(&member.id).map(|verifier| verifier.id.as_str());
    let mut sentences = Vec::new();
    if let Some(verifier) = verifier {
        sentences.push(format!(
            "`{verifier}` verifies `{id}` automatically; start `{id}` with `--verify`.",
            id = member.id
        ));
    }
    for child in team.children(&member.id) {
        if child.action == "verify" {
            continue;
        }
        sentences.push(format!(
            "When `{}` reports, give its report to `{}` with `--from-report`.",
            member.id, child.id
        ));
    }
    sentences
}

/// A Member's level in the tree; 1 for a Member with no parent. A broken chain stops at the deepest allowed.
fn depth(team: &Team, member: &Member) -> usize {
    let mut level = 1;
    let mut above = member.parent.as_deref();
    while let Some(parent) = above.filter(|_| level < crate::team::MAX_DEPTH) {
        level += 1;
        above = team
            .members
            .iter()
            .find(|candidate| candidate.id == parent)
            .and_then(|candidate| candidate.parent.as_deref());
    }
    level
}

/// `text` trimmed, ended with a full stop; empty stays empty.
fn sentence(text: &str) -> String {
    let text = text.trim();
    match text.chars().last() {
        None => String::new(),
        Some('.' | '!' | '?') => text.to_string(),
        Some(_) => format!("{text}."),
    }
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
        assert!(!plain.contains("Skip the verifier"));
        let team = team_of(r#"{"rules": {"review": false}}"#);
        let merged = prompt(&state, Some(&team));
        assert!(merged.contains("Skip the verifier"), "the Team's review:false wins");
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

    const THREE: &str = r#"{
        "workers": {"profiles": {"hinata": {"model": "anthropic/claude-haiku-5-5"}}},
        "members": [
            {"id": "scan", "action": "scan", "profile": "hinata"},
            {"id": "build", "action": "execute", "profile": "naruto", "parent": "scan",
             "model": "anthropic/claude-opus-5-5", "worktree": "new"},
            {"id": "check", "action": "verify", "profile": "sasuke", "parent": "build"}
        ],
        "instructions": "Prefer small Tasks."
    }"#;

    fn facts(member: &Member) -> MemberFacts {
        MemberFacts {
            description: format!("{} does its part", member.profile),
            model: member.model.clone(),
        }
    }

    #[test]
    fn the_workers_section_lists_members_in_tree_order_with_hand_offs() {
        let team = team_of(THREE);
        let text = workers_section(&team, &action::list(&paths::hub_dir()), &facts);
        let scan = text.find("- `scan` (Scan code, from Profile `hinata`):").unwrap();
        let build = text.find("  - `build` (Write code, from Profile `naruto`):").unwrap();
        let check = text.find("    - `check` (Verify, from Profile `sasuke`):").unwrap();
        assert!(text.starts_with("# Your Workers\n\n") && scan < build && build < check);
        assert!(text.contains("Send questions about how existing code works here. hinata does its part."));
        assert!(text.contains("Runs on anthropic/claude-opus-5-5. Worktree: new."));
        assert!(text.contains("Runs on the default model. Worktree: current."));
        assert!(text.contains("When `scan` reports, give its report to `build` with `--from-report`."));
        assert!(text.contains("`check` verifies `build` automatically; start `build` with `--verify`."));
        assert!(
            !text.contains("give its report to `check`"),
            "a verifier is not a hand-off"
        );
        assert!(text.contains("echoctl worker start <id>"));
        assert!(text.contains("Start Workers by these ids"));
        assert!(!text.contains('\u{2014}'));
    }

    #[test]
    fn a_member_without_a_verify_child_has_no_verify_sentence_and_custom_has_no_routing() {
        let team = team_of(
            r#"{"members": [{"id": "scribe-2", "action": "custom", "profile": "mine", "worktree": "current"}]}"#,
        );
        let text = workers_section(&team, &action::list(&paths::hub_dir()), &facts);
        assert!(text.contains("- `scribe-2` (Custom, from Profile `mine`): mine does its part. Runs on the default model. Worktree: current."));
        assert!(!text.contains("--verify") && !text.contains("Hand-offs:"));
    }

    #[test]
    fn a_teams_prompt_has_the_workers_section_after_the_rules_and_before_its_instructions() {
        let state = scratch("workers");
        std::fs::write(state.join("settings.json"), r#"{"maxWorkers": 6}"#).unwrap();
        let team = team_of(THREE);
        let text = prompt(&state, Some(&team));
        let rules = text.find("# The human's Settings").unwrap();
        let workers = text.find("# Your Workers").unwrap();
        let instructions = text.find("# Team instructions").unwrap();
        assert!(rules < workers && workers < instructions);
        assert!(text.ends_with("Repo for this Hub Session: /tmp/some-repo"));
        let scan = text.find("- `scan` (Scan code").unwrap();
        let build = text.find("- `build` (Write code").unwrap();
        let check = text.find("- `check` (Verify").unwrap();
        assert!(scan < build && build < check);
        assert!(
            text.contains("Runs on anthropic/claude-haiku-5-5."),
            "the Team's workers.profiles entry"
        );
        assert!(
            text.contains("Runs on anthropic/claude-opus-5-5. Worktree: new."),
            "the Member's own model"
        );
        assert!(text.contains("Codebase analyst."), "the Profile's description");
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn a_team_without_members_leaves_the_prompt_as_it_was_before_the_section() {
        let state = scratch("nomembers");
        std::fs::write(state.join("settings.json"), r#"{"maxWorkers": 6}"#).unwrap();
        let hub = paths::hub_dir();
        let before = |rules: &str, instructions: &str| {
            let orchestrator = std::fs::read_to_string(hub.join("orchestrator.md"))
                .unwrap()
                .replace("$ECHO_REPO", &hub.display().to_string())
                .replace(
                    "$ECHO_PREFERENCES",
                    &lessons::preferences_path(&state, &hub).display().to_string(),
                )
                .replace(
                    "$ECHO_LESSONS",
                    &lessons::lessons_path(&state, "/tmp/some-repo").display().to_string(),
                );
            format!(
                "{orchestrator}\n\n# Preferences\n\n{}{rules}{instructions}\n\nRepo for this Hub Session: /tmp/some-repo",
                lessons::preferences(&hub)
            )
        };
        let rules = format!(
            "\n\n{}",
            settings::Rules::from(&settings::read(&state).unwrap_or_default()).overrides()
        );
        assert_eq!(prompt(&state, None), before(&rules, ""));
        let team =
            team_of(r#"{"instructions": "Prefer small Tasks.", "workers": {"model": "anthropic/claude-opus-5-5"}}"#);
        assert_eq!(
            prompt(&state, Some(&team)),
            before(&rules, "\n\n# Team instructions\n\nPrefer small Tasks.")
        );
        assert!(!prompt(&state, Some(&team)).contains("# Your Workers"));
        let _ = std::fs::remove_dir_all(&state);
    }
}

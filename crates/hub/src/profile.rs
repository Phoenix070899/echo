//! Agent Profiles: `<name>.md`, frontmatter plus the role text, from three levels. Each level's
//! file replaces a same-named one before it, whole: Echo's own (`profiles/` in the echo repo),
//! the human's (`profiles/` in the daemon's state), then the repo's (`.echo/profiles/`, shared
//! through its git).

use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};

use crate::{lessons, paths};

#[derive(Debug, Clone)]
pub struct Profile {
    pub name: String,
    pub model: String,
    pub effort: Option<String>,
    pub tools: Vec<String>,
    pub skills: Vec<String>,
    pub context: Vec<String>,
    pub role: String,
    pub description: String,
    /// It edits files, so its tries of a Task differ and are worth comparing.
    pub writes: bool,
}

/// Where a Profile comes from; a later level wins.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    BuiltIn,
    Yours,
    Repo,
}

impl Level {
    pub fn label(self) -> &'static str {
        match self {
            Level::BuiltIn => "built-in",
            Level::Yours => "yours",
            Level::Repo => "repo",
        }
    }
}

/// Each level's folder, Echo's first. `repo` is a checkout; without one there is no repo level.
pub fn dirs(hub: &Path, state: &Path, repo: Option<&Path>) -> Vec<(Level, PathBuf)> {
    let mut dirs = vec![
        (Level::BuiltIn, hub.join("profiles")),
        (Level::Yours, state.join("profiles")),
    ];
    if let Some(repo) = repo {
        dirs.push((Level::Repo, repo.join(".echo").join("profiles")));
    }
    dirs
}

/// One name's winning file: the Profile it parses to, or why it does not.
pub struct Entry {
    pub name: String,
    pub level: Level,
    pub path: PathBuf,
    /// The levels below that this file replaces.
    pub replaces: Vec<Level>,
    pub profile: Result<Profile, String>,
}

/// Every Profile name across the levels, sorted, each with its winning file.
pub fn entries(hub: &Path, state: &Path, repo: Option<&Path>) -> Vec<Entry> {
    let mut found: Vec<(String, Level, PathBuf)> = Vec::new();
    for (level, dir) in dirs(hub, state, repo) {
        let Ok(read) = std::fs::read_dir(&dir) else { continue };
        for entry in read.flatten() {
            let path = entry.path();
            if path.extension().is_some_and(|e| e == "md") {
                if let Some(stem) = path.file_stem() {
                    found.push((stem.to_string_lossy().into_owned(), level, path));
                }
            }
        }
    }
    let mut names: Vec<String> = found.iter().map(|(name, _, _)| name.clone()).collect();
    names.sort();
    names.dedup();
    names
        .into_iter()
        .map(|name| {
            let mut levels: Vec<&(String, Level, PathBuf)> = found.iter().filter(|(n, _, _)| *n == name).collect();
            levels.sort_by_key(|(_, level, _)| *level as u8);
            let (_, level, path) = levels.pop().unwrap().clone();
            let profile = std::fs::read_to_string(&path)
                .map_err(|e| format!("reading {}: {e}", path.display()))
                .and_then(|text| parse(&name, &text).map_err(|e| e.to_string()));
            Entry {
                replaces: levels.iter().map(|(_, level, _)| *level).collect(),
                name,
                level,
                path,
                profile,
            }
        })
        .collect()
}

/// The Profile a Worker in `repo` starts as.
pub fn load(hub: &Path, state: &Path, repo: Option<&Path>, name: &str) -> Result<Profile> {
    let all = entries(hub, state, repo);
    let known: Vec<String> = all.iter().map(|entry| entry.name.clone()).collect();
    match all.into_iter().find(|entry| entry.name == name) {
        Some(entry) => entry.profile.map_err(|e| anyhow::anyhow!(e)),
        None => bail!("unknown profile {name:?}; known: {}", known.join(", ")),
    }
}

/// A new Profile's file: every field there to fill in, a read-only Worker until changed.
pub fn blank(name: &str) -> String {
    let mut title = name.to_string();
    if let Some(first) = title.get_mut(0..1) {
        first.make_ascii_uppercase();
    }
    format!(
        "---\nname: {name}\ndescription: One line: what this Worker does, for the Orchestrator picking a Profile.\n\
         cli: claude\nmodel: claude-sonnet-5-5\neffort: medium\ntools: Read, Grep, Glob, Bash\nskills:\n\
         context: CONTEXT.md, AGENTS.md, CLAUDE.md\nwrites: false\n---\n\n\
         You are {title}. Say what you do, in steps the Worker follows.\n\n\
         Your Final Report, sent with `echoctl done`, lists: what the Orchestrator needs back.\n\n\
         Rules:\n- Stay inside the Task's scope.\n"
    )
}

/// Profile names are file names, and appear in commands and branch names.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 32
        && name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        && !name.starts_with('-')
}

fn parse(name: &str, text: &str) -> Result<Profile> {
    let mut parts = text.splitn(3, "---");
    let (_, front, body) = match (parts.next(), parts.next(), parts.next()) {
        (Some(a), Some(b), Some(c)) => (a, b, c),
        _ => bail!("profile {name}: missing --- frontmatter"),
    };
    let field = |key: &str| {
        front.lines().find_map(|line| {
            let (k, v) = line.split_once(':')?;
            (k.trim() == key).then(|| v.trim().to_string())
        })
    };
    let list = |key: &str| -> Vec<String> {
        field(key)
            .unwrap_or_default()
            .split(',')
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .map(String::from)
            .collect()
    };
    let cli = field("cli").unwrap_or_default();
    if cli != "claude" {
        bail!("profile {name}: cli {cli:?} is not supported yet (only claude)");
    }
    Ok(Profile {
        name: field("name").unwrap_or_else(|| name.to_string()),
        model: field("model").with_context(|| format!("profile {name}: no model"))?,
        effort: field("effort").filter(|v| !v.is_empty()),
        tools: list("tools"),
        skills: list("skills"),
        context: list("context"),
        role: body.trim().to_string(),
        description: field("description").unwrap_or_default(),
        writes: field("writes").as_deref() == Some("true"),
    })
}

/// Every profile that loads, by name.
pub fn all(hub: &Path, state: &Path, repo: Option<&Path>) -> Vec<Profile> {
    entries(hub, state, repo)
        .into_iter()
        .filter_map(|entry| entry.profile.ok())
        .collect()
}

/// Worker Contract, Preferences, the repo's Lessons, then the profile's role, skills, and context.
pub fn system_prompt(hub: &Path, state: &Path, repo: &str, profile: &Profile) -> Result<String> {
    let mut parts = vec![
        std::fs::read_to_string(hub.join("worker-contract.md"))?,
        format!(
            "# Preferences\n\nApply these standing instructions from the human.\n\n{}",
            std::fs::read_to_string(lessons::preferences_path(state, hub)).unwrap_or_default()
        ),
    ];
    let lessons = lessons::lessons(state, repo);
    if !lessons.is_empty() {
        parts.push(format!("{}\n\n{}", lessons::WORKER_INTRO, lessons.trim_end()));
    }
    parts.push(format!("# Your role: {}\n\n{}", profile.name, profile.role));
    if !profile.skills.is_empty() {
        parts.push(format!(
            "Use these skills when they fit the Task: {}.",
            profile.skills.join(", ")
        ));
    }
    if !profile.context.is_empty() {
        parts.push(format!(
            "Before starting, read whichever of these files exist (paths relative to your working directory unless absolute): {}.",
            profile.context.join(", ")
        ));
    }
    Ok(parts.join("\n\n"))
}

/// The first message of a resumed Worker session.
const RESUMED: &str = "Your terminal was restarted. Continue your Task from where you left off: \
                       check what is already done before repeating anything, then finish with echoctl done.";

/// How a Worker's Claude session begins: a new session on its Task, or a resumed one.
pub enum Launch<'a> {
    New { spec: &'a str },
    Resume,
}

/// Arguments after `claude` for a Worker session.
pub fn claude_args(
    hub: &Path,
    repo: &str,
    profile: &Profile,
    title: &str,
    session_id: &str,
    launch: Launch,
) -> Result<Vec<String>> {
    let mut args: Vec<String> = vec![
        "--model".into(),
        profile.model.clone(),
        "--permission-mode".into(),
        "auto".into(),
        "--settings".into(),
        hub.join("settings").join("worker.json").display().to_string(),
        "--disallowedTools".into(),
        "AskUserQuestion".into(),
        "--add-dir".into(),
        hub.display().to_string(),
        "--add-dir".into(),
        lessons::memory_dir(&paths::state_dir()).display().to_string(),
        "-n".into(),
        format!("{}: {title}", profile.name),
    ];
    if let Some(effort) = &profile.effort {
        args.extend(["--effort".into(), effort.clone()]);
    }
    if !profile.tools.is_empty() {
        args.extend(["--tools".into(), profile.tools.join(",")]);
    }
    args.extend([
        "--append-system-prompt".into(),
        system_prompt(hub, &paths::state_dir(), repo, profile)?,
    ]);
    match launch {
        Launch::New { spec } => args.extend(["--session-id".into(), session_id.into(), "--".into(), spec.into()]),
        Launch::Resume => args.extend(["--resume".into(), session_id.into(), "--".into(), RESUMED.into()]),
    }
    Ok(args)
}

#[cfg(test)]
mod tests {
    use super::*;

    const NARUTO: &str = "---\nname: naruto\ndescription: writes code\ncli: claude\nmodel: claude-sonnet-5-5\neffort: high\ntools: Bash, Read, Edit\nskills:\ncontext: AGENTS.md, CLAUDE.md\nwrites: true\n---\n\nYou implement.\n";

    #[test]
    fn parses_frontmatter_and_role() {
        let profile = parse("naruto", NARUTO).unwrap();
        assert_eq!(profile.model, "claude-sonnet-5-5");
        assert_eq!(profile.effort.as_deref(), Some("high"));
        assert_eq!(profile.tools, ["Bash", "Read", "Edit"]);
        assert!(profile.skills.is_empty());
        assert_eq!(profile.context, ["AGENTS.md", "CLAUDE.md"]);
        assert_eq!(profile.role, "You implement.");
    }

    #[test]
    fn refuses_other_clis() {
        let text = NARUTO.replace("cli: claude", "cli: codex");
        assert!(parse("naruto", &text)
            .unwrap_err()
            .to_string()
            .contains("not supported"));
    }

    #[test]
    fn real_profiles_load() {
        let hub = crate::paths::hub_dir();
        for name in ["hinata", "naruto", "jiraiya", "sasuke", "ino", "lee"] {
            load(&hub, Path::new("/nonexistent"), None, name).unwrap_or_else(|e| panic!("{name}: {e}"));
        }
    }

    #[test]
    fn a_worker_prompt_carries_preferences_then_the_repos_lessons() {
        let hub = crate::paths::hub_dir();
        let state = std::env::temp_dir().join(format!("hub-prompt-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&state);
        std::fs::create_dir_all(state.join("memory")).unwrap();
        std::fs::write(state.join("memory/preferences.md"), "- Never push to main\n").unwrap();
        let profile = load(&hub, &state, None, "lee").unwrap();
        let plain = system_prompt(&hub, &state, "/code/shop", &profile).unwrap();
        assert!(plain.contains("- Never push to main"));
        assert!(!plain.contains("# Lessons"), "no Lessons section before there are any");
        lessons::add(&state, "/code/shop", "w2", "2026-10-28", &["Run make db first".into()]).unwrap();
        let prompt = system_prompt(&hub, &state, "/code/shop", &profile).unwrap();
        let (prefs, rest) = prompt.split_once("# Lessons for this repo").unwrap();
        assert!(prefs.contains("- Never push to main"));
        assert!(rest.contains("- Run make db first (2026-10-28, w2)"));
        assert!(rest.contains("# Your role: lee"));
        assert!(!system_prompt(&hub, &state, "/code/other", &profile)
            .unwrap()
            .contains("# Lessons"));
    }

    #[test]
    fn a_later_level_replaces_a_profile_whole_and_a_broken_one_says_why() {
        let root = std::env::temp_dir().join(format!("hub-levels-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (hub, state, repo) = (root.join("hub"), root.join("state"), root.join("repo"));
        for dir in [
            hub.join("profiles"),
            state.join("profiles"),
            repo.join(".echo/profiles"),
        ] {
            std::fs::create_dir_all(dir).unwrap();
        }
        std::fs::write(hub.join("profiles/naruto.md"), NARUTO).unwrap();
        std::fs::write(hub.join("profiles/lee.md"), NARUTO.replace("naruto", "lee")).unwrap();
        let mine = NARUTO
            .replace("model: claude-sonnet-5-5", "model: claude-opus-5-5")
            .replace("effort: high\n", "");
        std::fs::write(state.join("profiles/naruto.md"), mine).unwrap();
        std::fs::write(repo.join(".echo/profiles/lee.md"), "no frontmatter").unwrap();

        let naruto = load(&hub, &state, Some(&repo), "naruto").unwrap();
        assert_eq!(naruto.model, "claude-opus-5-5");
        assert_eq!(naruto.effort, None, "whole file, no field taken from the built-in one");
        let all = entries(&hub, &state, Some(&repo));
        let lee = all.iter().find(|e| e.name == "lee").unwrap();
        assert_eq!((lee.level, lee.replaces.clone()), (Level::Repo, vec![Level::BuiltIn]));
        assert!(lee.profile.as_ref().unwrap_err().contains("frontmatter"));
        assert!(load(&hub, &state, None, "lee").is_ok(), "no repo level outside a repo");
        assert!(load(&hub, &state, None, "kakashi")
            .unwrap_err()
            .to_string()
            .contains("known: lee, naruto"));
    }

    #[test]
    fn a_blank_profile_loads() {
        let profile = parse("code-reviewer", &blank("code-reviewer")).unwrap();
        assert!(!profile.writes);
        assert!(profile.role.starts_with("You are Code-reviewer."));
        assert!(valid_name("code-reviewer") && !valid_name("Code") && !valid_name("-x") && !valid_name(""));
    }
}

//! Agent Profiles: `<name>.md`, frontmatter plus the role text, from three levels. Each level's
//! file replaces a same-named one before it, whole: Echo's own (`profiles/` in the echo repo),
//! the human's (`profiles/` in the daemon's state), then the repo's (`.echo/profiles/`, shared
//! through its git).

use std::path::{Path, PathBuf};

use anyhow::{bail, Result};

use crate::cli::{Cli, Start};
use crate::{lessons, paths};

#[derive(Debug, Clone)]
pub struct Profile {
    pub name: String,
    /// Its own CLI and model, over the settings; either left out leaves it to them.
    pub cli: Option<String>,
    pub model: Option<String>,
    pub effort: Option<String>,
    pub tools: Vec<String>,
    pub skills: Vec<String>,
    pub context: Vec<String>,
    pub role: String,
    pub description: String,
    /// It edits files, so its tries of a Task differ and are worth comparing.
    pub writes: bool,
    /// Its prompt carries the repo's Lessons; a Member may leave them out (features/0084).
    pub lessons: bool,
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

/// The folder a level's Profiles live in; Echo's own is never written.
pub fn level_dir(state: &Path, repo: Option<&Path>, level: Level) -> Result<PathBuf> {
    match (level, repo) {
        (Level::BuiltIn, _) => bail!("Echo's own Profiles are not changed; copy one into yours"),
        (Level::Yours, _) => Ok(state.join("profiles")),
        (Level::Repo, Some(repo)) => Ok(repo.join(".echo").join("profiles")),
        (Level::Repo, None) => bail!("a repo's Profile needs a git checkout"),
    }
}

/// Copies the Profile now in force into `level`, where it replaces the original; returns the copy.
pub fn copy(hub: &Path, state: &Path, repo: Option<&Path>, name: &str, level: Level) -> Result<(PathBuf, Level)> {
    let entries = entries(hub, state, repo);
    let Some(entry) = entries.iter().find(|e| e.name == name) else {
        let known: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        bail!("no Profile {name:?}; known: {}", known.join(", "));
    };
    let dir = level_dir(state, repo, level)?;
    let to = dir.join(format!("{name}.md"));
    if entry.level == level || to.exists() {
        bail!("{name} is already {}: edit {}", level.label(), to.display());
    }
    std::fs::create_dir_all(&dir)?;
    std::fs::copy(&entry.path, &to)?;
    Ok((to, entry.level))
}

/// Writes a blank Profile into `level`; the name must be new at every level.
pub fn create(hub: &Path, state: &Path, repo: Option<&Path>, name: &str, level: Level) -> Result<PathBuf> {
    if !valid_name(name) {
        bail!("a Profile name is lowercase letters, digits, and -, like code-reviewer");
    }
    if let Some(entry) = entries(hub, state, repo).iter().find(|e| e.name == name) {
        bail!(
            "{name} already exists ({}); change it with: echoctl profile copy {name}",
            entry.level.label()
        );
    }
    let dir = level_dir(state, repo, level)?;
    let to = dir.join(format!("{name}.md"));
    std::fs::create_dir_all(&dir)?;
    std::fs::write(&to, blank(name))?;
    Ok(to)
}

/// Deletes the copy at `level`, so the one below it is in force again.
pub fn reset(state: &Path, repo: Option<&Path>, name: &str, level: Level) -> Result<()> {
    let path = level_dir(state, repo, level)?.join(format!("{name}.md"));
    if !path.exists() {
        bail!("{name} has no {} copy to reset", level.label());
    }
    std::fs::remove_file(path)?;
    Ok(())
}

/// Sets frontmatter fields in a Profile file, keeping the rest as it is; `None` empties one.
pub fn set_fields(path: &Path, fields: &[(&str, Option<&str>)]) -> Result<()> {
    let text = std::fs::read_to_string(path)?;
    let Some(rest) = text.strip_prefix("---\n") else {
        bail!("{}: missing --- frontmatter", path.display());
    };
    let Some(end) = rest.find("\n---") else {
        bail!("{}: missing closing ---", path.display());
    };
    let mut lines: Vec<String> = rest[..end].lines().map(String::from).collect();
    for (key, value) in fields {
        let line = format!("{key}: {}", value.unwrap_or_default());
        match lines
            .iter()
            .position(|l| l.split_once(':').is_some_and(|(k, _)| k.trim() == *key))
        {
            Some(at) => lines[at] = line,
            None => lines.push(line),
        }
    }
    let text = format!("---\n{}{}", lines.join("\n"), &rest[end..]);
    parse("check", &text)?;
    std::fs::write(path, text)?;
    Ok(())
}

impl Level {
    pub fn parse(name: &str) -> Result<Level> {
        match name {
            "yours" => Ok(Level::Yours),
            "repo" => Ok(Level::Repo),
            other => bail!("a Profile level is yours or repo, not {other:?}"),
        }
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
         cli: claude\nmodel: anthropic/claude-sonnet-5-5\neffort: medium\ntools: Read, Grep, Glob, Bash\nskills:\n\
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
    let cli = field("cli").filter(|v| !v.is_empty());
    if let Some(cli) = &cli {
        crate::cli::Cli::parse(cli).map_err(|e| anyhow::anyhow!("profile {name}: {e}"))?;
    }
    Ok(Profile {
        name: field("name").unwrap_or_else(|| name.to_string()),
        cli,
        model: field("model").filter(|v| !v.is_empty()),
        effort: field("effort").filter(|v| !v.is_empty()),
        tools: list("tools"),
        skills: list("skills"),
        context: list("context"),
        role: body.trim().to_string(),
        description: field("description").unwrap_or_default(),
        writes: field("writes").as_deref() == Some("true"),
        lessons: true,
    })
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
    let lessons = if profile.lessons {
        lessons::lessons(state, repo)
    } else {
        String::new()
    };
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
pub const RESUMED: &str = "Your terminal was restarted. Continue your Task from where you left off: \
                       check what is already done before repeating anything, then finish with echoctl done.";

/// The longest Task, in characters, that a Kiro resume message repeats.
const KIRO_RESUME_TASK_LIMIT: usize = 4000;

/// The first message of a resumed Worker session. Kiro's carries the Worker's Task after the
/// usual lead line: a Kiro resume can land in a session that never saw the Task (features/0076),
/// and a model with no instruction answers that it has none. Claude's and Codex's stay `RESUMED`.
pub fn resumed(cli: Cli, spec: &str) -> String {
    if cli != Cli::Kiro {
        return RESUMED.to_string();
    }
    let task: String = spec.trim().chars().take(KIRO_RESUME_TASK_LIMIT).collect();
    let cut = if spec.trim().chars().count() > KIRO_RESUME_TASK_LIMIT {
        format!("\n[Task cut at {KIRO_RESUME_TASK_LIMIT} characters.]")
    } else {
        String::new()
    };
    format!("{RESUMED}\n\nYour Task:\n\n{task}{cut}")
}

/// How a Worker's Claude session begins: a new session on its Task, a resumed one (`spec` is its
/// Task), or a resumed one on its next Task.
pub enum Launch<'a> {
    New { spec: &'a str },
    Resume { spec: &'a str },
    Next { spec: &'a str },
}

/// The heading of a Member's instructions in its Worker's role.
const MEMBER_INSTRUCTIONS: &str = "# This Team's instructions for you";

impl Profile {
    /// This Profile with `member` laid over it, for the Worker that starts as that Member
    /// (features/0084). Its `instructions` follow the role under their own heading, or take the
    /// role's place when `replace_role`; a `tools`, `skills` or `context` list that is not empty
    /// replaces the Profile's; `lessons` and `writes` replace the Profile's when the Member sets
    /// them. Instructions that are blank leave the role as it is, so a Worker never starts with
    /// no role. The CLI, model and effort are not laid over here; `resolve` picks them.
    pub fn with_member(&self, member: &crate::team::Member) -> Profile {
        let mut profile = self.clone();
        let instructions = member.instructions.as_deref().map(str::trim).unwrap_or_default();
        if !instructions.is_empty() {
            profile.role = if member.replace_role {
                instructions.to_string()
            } else {
                format!("{}\n\n{MEMBER_INSTRUCTIONS}\n\n{instructions}", self.role)
            };
        }
        for (own, theirs) in [
            (&mut profile.tools, &member.tools),
            (&mut profile.skills, &member.skills),
            (&mut profile.context, &member.context),
        ] {
            if !theirs.is_empty() {
                own.clone_from(theirs);
            }
        }
        profile.lessons = member.lessons.unwrap_or(self.lessons);
        profile.writes = member.writes.unwrap_or(self.writes);
        profile
    }

    pub fn choice(&self) -> crate::cli::Choice {
        crate::cli::Choice {
            cli: self.cli.clone(),
            model: self.model.clone(),
        }
    }
}

/// A Worker's CLI, model and effort, from the highest: what was picked for it (`picked`), its
/// Member (features/0085), its Orchestrator's Team for its Profile, its Team for all Workers, then
/// its Profile's own and the levels below (features/0081, 0036). `forceCli` (features/0075) puts a
/// Profile's own cli and model aside but never what a Team names, a Member included, so it applies
/// only where the Team names nothing. Without a Team this is `cli::pick`, and the effort is the
/// Profile's.
pub fn resolve(
    state: &Path,
    repo: Option<&Path>,
    profile: &Profile,
    team: Option<&crate::team::Team>,
    member: Option<&crate::team::Member>,
    picked: &crate::cli::Choice,
) -> Result<(Cli, Option<String>, Option<String>)> {
    let (all, own) = team.map(|team| team.worker_levels(&profile.name)).unwrap_or_default();
    let member = member.map(member_choice).unwrap_or_default();
    let (cli, model) = crate::cli::pick(
        state,
        repo,
        Some(&profile.choice()),
        &[&all.runs(), &own.runs(), &member.runs(), picked],
    )?;
    let effort = member
        .effort
        .or(own.effort)
        .or(all.effort)
        .or_else(|| profile.effort.clone());
    Ok((cli, model, effort))
}

/// What a Member names for its Worker's CLI, model and effort.
pub fn member_choice(member: &crate::team::Member) -> crate::team::Choice {
    crate::team::Choice {
        cli: member.cli.clone(),
        model: member.model.clone(),
        effort: member.effort.clone(),
    }
}

/// What a Worker starts with, whatever its CLI; `picked` is the CLI and model already picked for it.
pub fn start(
    hub: &Path,
    repo: &str,
    profile: &Profile,
    title: &str,
    session_id: &str,
    launch: Launch,
    picked: (Cli, Option<String>),
) -> Result<Start> {
    let (cli, model) = picked;
    let state = paths::state_dir();
    let (resume, first) = match launch {
        Launch::New { spec } => (false, spec.to_string()),
        Launch::Resume { spec } => (true, resumed(cli, spec)),
        Launch::Next { spec } => (true, spec.to_string()),
    };
    Ok(Start {
        title: format!("{}: {title}", profile.name),
        prompt: system_prompt(hub, &state, repo, profile)?,
        dirs: vec![hub.to_path_buf(), lessons::memory_dir(&state)],
        model,
        effort: profile.effort.clone(),
        tools: profile.tools.clone(),
        worker: true,
        session_id: session_id.to_string(),
        resume,
        first: Some(first),
        ..Start::default()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const NARUTO: &str = "---\nname: naruto\ndescription: writes code\ncli: claude\nmodel: claude-sonnet-5-5\neffort: high\ntools: Bash, Read, Edit\nskills:\ncontext: AGENTS.md, CLAUDE.md\nwrites: true\n---\n\nYou implement.\n";

    #[test]
    fn parses_frontmatter_and_role() {
        let profile = parse("naruto", NARUTO).unwrap();
        assert_eq!(profile.model.as_deref(), Some("claude-sonnet-5-5"));
        assert_eq!(profile.effort.as_deref(), Some("high"));
        assert_eq!(profile.tools, ["Bash", "Read", "Edit"]);
        assert!(profile.skills.is_empty());
        assert_eq!(profile.context, ["AGENTS.md", "CLAUDE.md"]);
        assert_eq!(profile.role, "You implement.");
    }

    #[test]
    fn refuses_other_clis() {
        let text = NARUTO.replace("cli: claude", "cli: gemini");
        assert!(parse("naruto", &text)
            .unwrap_err()
            .to_string()
            .contains("not supported"));
    }

    #[test]
    fn accepts_kiro_as_a_cli_with_its_own_model_id() {
        let text = NARUTO
            .replace("cli: claude", "cli: kiro")
            .replace("claude-sonnet-5-5", "claude-sonnet-5.5");
        let profile = parse("naruto", &text).unwrap();
        assert_eq!(profile.cli.as_deref(), Some("kiro"));
        assert_eq!(profile.model.as_deref(), Some("claude-sonnet-5.5"));
        assert_eq!(
            profile.choice(),
            crate::cli::Choice {
                cli: Some("kiro".into()),
                model: Some("claude-sonnet-5.5".into())
            }
        );
    }

    #[test]
    fn a_kiro_profile_says_which_cli_it_wants_when_the_name_is_wrong() {
        let text = NARUTO.replace("cli: claude", "cli: kiro-cli");
        let err = parse("naruto", &text).unwrap_err().to_string();
        assert!(
            err.contains("profile naruto") && err.contains("claude, codex and kiro"),
            "{err}"
        );
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
        assert_eq!(naruto.model.as_deref(), Some("claude-opus-5-5"));
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
    fn a_kiro_resume_message_carries_the_task_and_the_others_stay_as_they_were() {
        let spec = "Fix the login test.\nThe codeword is TANGERINE-7.";
        let kiro = resumed(Cli::Kiro, spec);
        assert!(kiro.starts_with(RESUMED), "{kiro}");
        assert!(kiro.ends_with(spec), "{kiro}");
        assert_eq!(resumed(Cli::Claude, spec), RESUMED);
        assert_eq!(resumed(Cli::Codex, spec), RESUMED);
    }

    #[test]
    fn a_kiro_resume_message_cuts_a_long_task_and_says_so() {
        let spec = "é".repeat(KIRO_RESUME_TASK_LIMIT + 50);
        let kiro = resumed(Cli::Kiro, &spec);
        assert!(kiro.contains(&"é".repeat(KIRO_RESUME_TASK_LIMIT)));
        assert!(!kiro.contains(&"é".repeat(KIRO_RESUME_TASK_LIMIT + 1)));
        assert!(kiro.ends_with(&format!("[Task cut at {KIRO_RESUME_TASK_LIMIT} characters.]")));
        let exact = "x".repeat(KIRO_RESUME_TASK_LIMIT);
        assert!(!resumed(Cli::Kiro, &exact).contains("Task cut"));
    }

    #[test]
    fn a_resumed_worker_starts_on_the_message_of_its_cli() {
        let hub = crate::paths::hub_dir();
        let profile = load(&hub, Path::new("/nonexistent"), None, "lee").unwrap();
        let first = |cli: Cli, launch: Launch| {
            let start = start(&hub, "/code/shop", &profile, "t", "s1", launch, (cli, None)).unwrap();
            assert!(start.resume);
            start.first.unwrap()
        };
        let spec = "Fix the login test.";
        assert!(first(Cli::Kiro, Launch::Resume { spec }).ends_with(spec));
        assert_eq!(first(Cli::Claude, Launch::Resume { spec }), RESUMED);
        assert_eq!(first(Cli::Codex, Launch::Resume { spec }), RESUMED);
        assert_eq!(first(Cli::Kiro, Launch::Next { spec: "next one" }), "next one");
    }

    #[test]
    fn a_blank_profile_loads() {
        let profile = parse("code-reviewer", &blank("code-reviewer")).unwrap();
        assert!(!profile.writes);
        assert!(profile.role.starts_with("You are Code-reviewer."));
        assert!(valid_name("code-reviewer") && !valid_name("Code") && !valid_name("-x") && !valid_name(""));
    }

    #[test]
    fn copies_are_edited_by_field_and_reset_to_the_original() {
        let root = std::env::temp_dir().join(format!("hub-edit-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (hub, state) = (root.join("hub"), root.join("state"));
        std::fs::create_dir_all(hub.join("profiles")).unwrap();
        std::fs::write(hub.join("profiles/naruto.md"), NARUTO).unwrap();
        assert!(copy(&hub, &state, None, "naruto", Level::BuiltIn).is_err());
        let (path, from) = copy(&hub, &state, None, "naruto", Level::Yours).unwrap();
        assert_eq!(from, Level::BuiltIn);
        set_fields(
            &path,
            &[
                ("cli", Some("codex")),
                ("model", Some("openai/gpt-5.6-terra")),
                ("effort", None),
            ],
        )
        .unwrap();
        let mine = load(&hub, &state, None, "naruto").unwrap();
        assert_eq!(
            (mine.cli.as_deref(), mine.model.as_deref(), mine.effort),
            (Some("codex"), Some("openai/gpt-5.6-terra"), None)
        );
        assert_eq!(mine.role, "You implement.", "the role is kept");
        assert!(
            set_fields(&path, &[("cli", Some("vim"))]).is_err(),
            "a field that breaks the Profile is not written"
        );
        assert_eq!(
            load(&hub, &state, None, "naruto").unwrap().cli.as_deref(),
            Some("codex")
        );
        reset(&state, None, "naruto", Level::Yours).unwrap();
        assert_eq!(
            load(&hub, &state, None, "naruto").unwrap().cli.as_deref(),
            Some("claude")
        );
        assert!(create(&hub, &state, None, "naruto", Level::Yours).is_err());
        assert!(create(&hub, &state, None, "scout", Level::Yours)
            .unwrap()
            .ends_with("profiles/scout.md"));
    }

    /// The Member `id` of a Team of one Profile's Members, from the JSON of its fields.
    fn member(fields: &str) -> crate::team::Member {
        let team = format!(r#"{{"members": [{{"id": "build", "action": "execute", "profile": "naruto"{fields}}}]}}"#);
        crate::team::parse(&team).unwrap().members.remove(0)
    }

    /// A state folder with a preference and one Lesson for `/code/shop`.
    fn state_with_lessons(name: &str) -> PathBuf {
        let state = std::env::temp_dir().join(format!("hub-overlay-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&state);
        std::fs::create_dir_all(state.join("memory")).unwrap();
        std::fs::write(state.join("memory/preferences.md"), "- Never push to main\n").unwrap();
        lessons::add(&state, "/code/shop", "w2", "2026-10-28", &["Run make db first".into()]).unwrap();
        state
    }

    fn naruto() -> Profile {
        parse("naruto", NARUTO).unwrap()
    }

    #[test]
    fn a_member_with_no_overlay_gives_the_prompt_the_profile_alone_gives() {
        let hub = crate::paths::hub_dir();
        let state = state_with_lessons("golden");
        let profile = naruto();
        let plain = member("");
        let laid = profile.with_member(&plain);
        assert_eq!(
            system_prompt(&hub, &state, "/code/shop", &laid).unwrap(),
            system_prompt(&hub, &state, "/code/shop", &profile).unwrap()
        );
        assert_eq!(laid.tools, profile.tools);
        assert_eq!(laid.skills, profile.skills);
        assert_eq!(laid.context, profile.context);
        assert_eq!(laid.role, profile.role);
        assert_eq!((laid.writes, laid.lessons), (profile.writes, profile.lessons));
        let blank = member(r#", "instructions": "  \n", "replaceRole": true"#);
        assert_eq!(
            profile.with_member(&blank).role,
            "You implement.",
            "blank instructions never empty the role"
        );
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn a_members_instructions_follow_the_role_under_their_own_heading() {
        let hub = crate::paths::hub_dir();
        let state = state_with_lessons("instructions");
        let laid = naruto().with_member(&member(r#", "instructions": "Only touch src/api.\n""#));
        let prompt = system_prompt(&hub, &state, "/code/shop", &laid).unwrap();
        assert!(
            prompt.contains(
                "# Your role: naruto\n\nYou implement.\n\n# This Team's instructions for you\n\nOnly touch src/api."
            ),
            "{prompt}"
        );
        let (before, after) = prompt.split_once("# Your role: naruto").unwrap();
        assert!(before.contains("- Never push to main") && before.contains("# Lessons for this repo"));
        assert!(after.contains("Only touch src/api."));
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn a_members_instructions_replace_the_role_when_it_says_so() {
        let hub = crate::paths::hub_dir();
        let state = state_with_lessons("replace");
        let member = member(r#", "instructions": "You only review.", "replaceRole": true"#);
        let prompt = system_prompt(&hub, &state, "/code/shop", &naruto().with_member(&member)).unwrap();
        assert!(prompt.contains("# Your role: naruto\n\nYou only review."), "{prompt}");
        assert!(!prompt.contains("You implement.") && !prompt.contains("This Team's instructions"));
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn a_members_lists_replace_the_profiles_only_when_they_are_not_empty() {
        let hub = crate::paths::hub_dir();
        let state = state_with_lessons("lists");
        let profile = naruto();
        let kept = profile.with_member(&member(r#", "tools": [], "skills": [], "context": []"#));
        assert_eq!((&kept.tools, &kept.context), (&profile.tools, &profile.context));
        let laid = profile.with_member(&member(
            r#", "tools": ["Read", "Grep"], "skills": ["tdd", "review"], "context": ["docs/api.md"]"#,
        ));
        assert_eq!(laid.tools, ["Read", "Grep"]);
        assert_eq!(laid.skills, ["tdd", "review"]);
        assert_eq!(laid.context, ["docs/api.md"]);
        let prompt = system_prompt(&hub, &state, "/code/shop", &laid).unwrap();
        assert!(prompt.contains("Use these skills when they fit the Task: tdd, review."));
        assert!(prompt.contains("read whichever of these files exist (paths relative to your working directory unless absolute): docs/api.md."));
        assert!(
            !prompt.contains("AGENTS.md"),
            "the Profile's context is replaced, not added to"
        );
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn lessons_false_drops_the_lessons_and_nothing_else() {
        let hub = crate::paths::hub_dir();
        let state = state_with_lessons("lessons");
        let profile = naruto();
        let with = system_prompt(&hub, &state, "/code/shop", &profile).unwrap();
        let without = system_prompt(
            &hub,
            &state,
            "/code/shop",
            &profile.with_member(&member(r#", "lessons": false"#)),
        )
        .unwrap();
        assert!(with.contains("# Lessons for this repo") && with.contains("Run make db first"));
        assert!(!without.contains("# Lessons") && !without.contains("Run make db first"));
        assert!(without.contains("- Never push to main"), "Preferences stay");
        let block = format!(
            "{}\n\n{}\n\n",
            lessons::WORKER_INTRO,
            lessons::lessons(&state, "/code/shop").trim_end()
        );
        assert_eq!(with.replace(&block, ""), without, "only the Lessons block differs");
        let kept = system_prompt(
            &hub,
            &state,
            "/code/shop",
            &profile.with_member(&member(r#", "lessons": true"#)),
        )
        .unwrap();
        assert_eq!(kept, with);
        let _ = std::fs::remove_dir_all(&state);
    }

    #[test]
    fn a_members_writes_replaces_the_profiles_and_tools_reach_the_start() {
        let hub = crate::paths::hub_dir();
        let profile = naruto();
        assert!(profile.writes);
        let read_only = profile.with_member(&member(r#", "writes": false, "tools": ["Read", "Grep"]"#));
        assert!(!read_only.writes);
        let started = start(
            &hub,
            "/code/shop",
            &read_only,
            "t",
            "s1",
            Launch::New { spec: "go" },
            (Cli::Claude, None),
        )
        .unwrap();
        assert_eq!(started.tools, ["Read", "Grep"]);
        assert!(started.prompt.contains("# Your role: naruto"));
        assert!(profile.with_member(&member("")).writes, "left out, the Profile's stays");
    }

    /// What `resolve` gives naruto (claude, claude-sonnet-5-5, high in its file) under the settings
    /// and the Team given, with `picked` as the explicit choice.
    fn resolved(
        settings: &str,
        team: Option<&str>,
        profile: &str,
        picked: (Option<&str>, Option<&str>),
    ) -> Result<(Cli, Option<String>, Option<String>)> {
        resolved_as(settings, team, profile, None, picked)
    }

    /// As `resolved`, for a Worker started as the Member `member` of the Team.
    fn resolved_as(
        settings: &str,
        team: Option<&str>,
        profile: &str,
        member: Option<&str>,
        picked: (Option<&str>, Option<&str>),
    ) -> Result<(Cli, Option<String>, Option<String>)> {
        static COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = COUNT.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let state = std::env::temp_dir().join(format!("hub-profile-resolve-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&state).unwrap();
        std::fs::write(state.join("settings.json"), settings).unwrap();
        let mut found = parse("naruto", NARUTO).unwrap();
        found.name = profile.to_string();
        let team = team.map(|text| crate::team::parse(text).unwrap());
        let member = member.map(|id| {
            team.as_ref()
                .and_then(|team| team.members.iter().find(|m| m.id == id))
                .unwrap_or_else(|| panic!("no Member {id}"))
        });
        let picked = crate::cli::Choice {
            cli: picked.0.map(String::from),
            model: picked.1.map(String::from),
        };
        let resolved = resolve(&state, None, &found, team.as_ref(), member, &picked);
        let _ = std::fs::remove_dir_all(&state);
        resolved
    }

    fn runs(cli: Cli, model: &str, effort: &str) -> (Cli, Option<String>, Option<String>) {
        (cli, Some(model.to_string()), Some(effort.to_string()))
    }

    #[test]
    fn every_step_of_the_order_for_a_worker() {
        let sonnet = "claude-sonnet-5-5";
        let team = r#"{"workers": {"model": "claude-haiku-5-5", "effort": "low",
            "profiles": {"naruto": {"model": "claude-opus-5-5", "effort": "max"}}}}"#;
        let all_only = r#"{"workers": {"model": "claude-haiku-5-5", "effort": "low"}}"#;
        let effort_only = r#"{"workers": {"effort": "medium"}}"#;
        let kiro = r#"{"workers": {"cli": "kiro", "model": "claude-haiku-5.5", "effort": "low",
            "profiles": {"naruto": {"model": "claude-sonnet-5.5"}}}}"#;
        let none = (None, None);
        let cases: [(&str, Option<&str>, &str, (Option<&str>, Option<&str>), _); 11] = [
            (
                "no Team: the Profile's own",
                None,
                "naruto",
                none,
                runs(Cli::Claude, sonnet, "high"),
            ),
            (
                "an empty Team changes nothing",
                Some("{}"),
                "naruto",
                none,
                runs(Cli::Claude, sonnet, "high"),
            ),
            (
                "Team workers over the Profile",
                Some(all_only),
                "naruto",
                none,
                runs(Cli::Claude, "claude-haiku-5-5", "low"),
            ),
            (
                "a Team's effort alone leaves the Profile's model",
                Some(effort_only),
                "naruto",
                none,
                runs(Cli::Claude, sonnet, "medium"),
            ),
            (
                "Team profile entry over Team workers",
                Some(team),
                "naruto",
                none,
                runs(Cli::Claude, "claude-opus-5-5", "max"),
            ),
            (
                "another Profile's entry does not apply",
                Some(team),
                "naruto-two",
                none,
                runs(Cli::Claude, "claude-haiku-5-5", "low"),
            ),
            (
                "picked over the Team's profile entry",
                Some(team),
                "naruto",
                (None, Some("claude-fable-5-1")),
                runs(Cli::Claude, "claude-fable-5-1", "max"),
            ),
            (
                "the Team's cli carries its model",
                Some(kiro),
                "naruto-two",
                none,
                runs(Cli::Kiro, "claude-haiku-5.5", "low"),
            ),
            (
                "an entry mixes its own fields with the Team's",
                Some(kiro),
                "naruto",
                none,
                runs(Cli::Kiro, "claude-sonnet-5.5", "low"),
            ),
            (
                "picked cli and model over a Team",
                Some(kiro),
                "naruto",
                (Some("claude"), Some("claude-opus-5-5")),
                runs(Cli::Claude, "claude-opus-5-5", "low"),
            ),
            (
                "a Team with workers for other Profiles only",
                Some(r#"{"workers": {"profiles": {"lee": {"model": "claude-haiku-5-5"}}}}"#),
                "naruto",
                none,
                runs(Cli::Claude, sonnet, "high"),
            ),
        ];
        for (what, team, profile, picked, want) in cases {
            assert_eq!(resolved("{}", team, profile, picked).unwrap(), want, "{what}");
        }
    }

    #[test]
    fn forcecli_applies_only_where_the_team_names_nothing() {
        let force = r#"{"cli": "kiro", "model": "claude-haiku-5.5", "forceCli": true}"#;
        let kiro = |model: &str, effort: &str| runs(Cli::Kiro, model, effort);
        let entry =
            r#"{"workers": {"profiles": {"naruto": {"cli": "kiro", "model": "claude-sonnet-5.5", "effort": "low"}}}}"#;
        let model_only = r#"{"workers": {"model": "claude-sonnet-5.5"}}"#;
        let effort_only = r#"{"workers": {"effort": "low"}}"#;
        let cases: [(&str, Option<&str>, &str, _); 5] = [
            (
                "no Team: force puts the Profile's cli and model aside",
                None,
                "naruto",
                kiro("claude-haiku-5.5", "high"),
            ),
            (
                "a Team entry beats force",
                Some(entry),
                "naruto",
                kiro("claude-sonnet-5.5", "low"),
            ),
            (
                "no entry for this Profile: force applies",
                Some(entry),
                "lee",
                kiro("claude-haiku-5.5", "high"),
            ),
            (
                "a Team's model alone beats the forced model, the forced cli stays",
                Some(model_only),
                "naruto",
                kiro("claude-sonnet-5.5", "high"),
            ),
            (
                "a Team's effort alone leaves cli and model to force",
                Some(effort_only),
                "naruto",
                kiro("claude-haiku-5.5", "low"),
            ),
        ];
        for (what, team, profile, want) in cases {
            assert_eq!(resolved(force, team, profile, (None, None)).unwrap(), want, "{what}");
        }
    }

    #[test]
    fn a_pair_the_teams_cli_cannot_run_is_an_error() {
        let team = r#"{"workers": {"cli": "kiro", "model": "anthropic/claude-haiku-5-5"}}"#;
        let error = resolved("{}", Some(team), "naruto", (None, None)).unwrap_err();
        assert!(error.to_string().contains("kiro runs its own model ids"), "{error}");
    }

    /// A Team with Workers entries and Members for naruto: `build` names a model and an effort,
    /// `plain` names nothing, `swap` names a CLI with its model, `mine` names a model alone.
    const MEMBERS: &str = r#"{"workers": {"model": "claude-haiku-5-5", "effort": "low",
        "profiles": {"naruto": {"model": "claude-opus-5-5", "effort": "max"}}},
        "members": [
            {"id": "build", "action": "execute", "profile": "naruto", "model": "claude-fable-5-1", "effort": "medium"},
            {"id": "plain", "action": "execute", "profile": "naruto"},
            {"id": "swap", "action": "execute", "profile": "naruto", "cli": "kiro", "model": "claude-sonnet-5.5"},
            {"id": "mine", "action": "execute", "profile": "naruto", "model": "claude-haiku-5-5"}]}"#;

    #[test]
    fn every_step_of_the_order_for_a_member() {
        let sonnet = "claude-sonnet-5-5";
        let no_entry = r#"{"workers": {"model": "claude-haiku-5-5", "effort": "low"},
            "members": [{"id": "plain", "action": "execute", "profile": "naruto"},
                        {"id": "build", "action": "execute", "profile": "naruto", "model": "claude-fable-5-1"}]}"#;
        let only_members = r#"{"members": [{"id": "build", "action": "execute", "profile": "naruto",
            "model": "claude-fable-5-1", "effort": "medium"}]}"#;
        let none = (None, None);
        let cases: [(&str, &str, &str, &str, (Option<&str>, Option<&str>), _); 10] = [
            (
                "a Member's model and effort over the Team's entry for its Profile",
                MEMBERS,
                "naruto",
                "build",
                none,
                runs(Cli::Claude, "claude-fable-5-1", "medium"),
            ),
            (
                "a Member naming nothing leaves the Team's entry for its Profile",
                MEMBERS,
                "naruto",
                "plain",
                none,
                runs(Cli::Claude, "claude-opus-5-5", "max"),
            ),
            (
                "a Member's model alone leaves the Team's effort",
                MEMBERS,
                "naruto",
                "mine",
                none,
                runs(Cli::Claude, "claude-haiku-5-5", "max"),
            ),
            (
                "a Member's cli carries its model",
                MEMBERS,
                "naruto",
                "swap",
                none,
                runs(Cli::Kiro, "claude-sonnet-5.5", "max"),
            ),
            (
                "picked over the Member, field by field",
                MEMBERS,
                "naruto",
                "build",
                (None, Some("claude-opus-5-5")),
                runs(Cli::Claude, "claude-opus-5-5", "medium"),
            ),
            (
                "picked cli and model over a Member's",
                MEMBERS,
                "naruto",
                "swap",
                (Some("claude"), Some("claude-opus-5-5")),
                runs(Cli::Claude, "claude-opus-5-5", "max"),
            ),
            (
                "no Profile entry: a Member over the Team's workers",
                no_entry,
                "naruto",
                "build",
                none,
                runs(Cli::Claude, "claude-fable-5-1", "low"),
            ),
            (
                "no Profile entry, a Member naming nothing: the Team's workers",
                no_entry,
                "naruto",
                "plain",
                none,
                runs(Cli::Claude, "claude-haiku-5-5", "low"),
            ),
            (
                "no Workers entries: a Member over the Profile",
                only_members,
                "naruto",
                "build",
                none,
                runs(Cli::Claude, "claude-fable-5-1", "medium"),
            ),
            (
                "a Member over a Profile that is not naruto",
                only_members,
                "lee",
                "build",
                none,
                runs(Cli::Claude, "claude-fable-5-1", "medium"),
            ),
        ];
        for (what, team, profile, member, picked, want) in cases {
            assert_eq!(
                resolved_as("{}", Some(team), profile, Some(member), picked).unwrap(),
                want,
                "{what}"
            );
        }
        assert_eq!(
            resolved_as("{}", Some(MEMBERS), "naruto", None, none).unwrap(),
            runs(Cli::Claude, "claude-opus-5-5", "max"),
            "no Member: the order of features/0081"
        );
    }

    #[test]
    fn forcecli_gives_way_to_a_member_and_applies_where_the_team_names_nothing() {
        let force = r#"{"cli": "kiro", "model": "claude-haiku-5.5", "forceCli": true}"#;
        let kiro = |model: &str, effort: &str| runs(Cli::Kiro, model, effort);
        let team = r#"{"members": [
            {"id": "build", "action": "execute", "profile": "naruto", "model": "claude-sonnet-5.5", "effort": "low"},
            {"id": "own-cli", "action": "execute", "profile": "naruto", "cli": "claude", "model": "claude-opus-5-5"},
            {"id": "effort", "action": "execute", "profile": "naruto", "effort": "medium"},
            {"id": "plain", "action": "execute", "profile": "naruto"}]}"#;
        let cases: [(&str, Option<&str>, _); 5] = [
            (
                "a Member's model beats the forced one, the forced cli stays",
                Some("build"),
                kiro("claude-sonnet-5.5", "low"),
            ),
            (
                "a Member's cli and model beat the forced ones",
                Some("own-cli"),
                runs(Cli::Claude, "claude-opus-5-5", "high"),
            ),
            (
                "a Member's effort alone leaves cli and model to force",
                Some("effort"),
                kiro("claude-haiku-5.5", "medium"),
            ),
            (
                "a Member naming nothing leaves everything to force",
                Some("plain"),
                kiro("claude-haiku-5.5", "high"),
            ),
            ("no Member: force applies", None, kiro("claude-haiku-5.5", "high")),
        ];
        for (what, member, want) in cases {
            let team = member.map(|_| team).or(Some("{}"));
            assert_eq!(
                resolved_as(force, team, "naruto", member, (None, None)).unwrap(),
                want,
                "{what}"
            );
        }
    }

    #[test]
    fn a_pair_a_member_cannot_run_is_an_error() {
        let team = r#"{"members": [{"id": "build", "action": "execute", "profile": "naruto",
            "cli": "kiro", "model": "anthropic/claude-haiku-5-5"}]}"#;
        let error = resolved_as("{}", Some(team), "naruto", Some("build"), (None, None)).unwrap_err();
        assert!(error.to_string().contains("kiro runs its own model ids"), "{error}");
    }
}

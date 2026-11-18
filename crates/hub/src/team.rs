//! Teams: `<name>.json`, a named setup for an Orchestrator, its Workers and its rules
//! (features/0081). Like Profiles, they come from three levels and each level's file replaces a
//! same-named one before it, whole: Echo's own (`teams/` in the echo repo), the human's (`teams/`
//! in the daemon's state), then the repo's (`.echo/teams/`, shared through its git).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};

use crate::cli::{self, Cli};
use crate::{action, profile, settings};

/// A Team's file, apart from its name, which is the file's.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Team {
    #[serde(skip)]
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub orchestrator: Option<OrchestratorSetup>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workers: Option<WorkersSetup>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rules: Option<RulesSetup>,
    /// The Team's Workers, flat and in file order; a Member's `after` names the Hand-offs into it
    /// (features/0092).
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub members: Vec<Member>,
    /// Text added to the end of the Orchestrator's prompt, after the rules.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instructions: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct OrchestratorSetup {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cli: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    /// The context size in tokens at which an idle Orchestrator is renewed; 0 turns renewal off.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rotate_at: Option<u64>,
}

/// What a Worker runs with; `None` leaves each field to the level below.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Choice {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cli: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
}

impl Choice {
    /// Its CLI and model, as the order of `cli::pick` takes them; the effort is read apart.
    pub fn runs(&self) -> cli::Choice {
        cli::Choice {
            cli: self.cli.clone(),
            model: self.model.clone(),
        }
    }
}

/// One Worker slot of a Team (features/0084, 0094): an Action, the Profile it starts from, its place
/// in the flow, and the CLI, model and effort it runs on. A field left out means the level below.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Member {
    pub id: String,
    pub action: String,
    pub profile: String,
    /// The Member above in a Team from before Hand-offs; `parse` turns it into `after`, and it is
    /// never written.
    #[serde(skip_serializing)]
    pub parent: Option<String>,
    /// The Hand-offs into this Member; absent, it hangs from the Orchestrator alone, and empty it
    /// cannot be reached, which `validate` refuses.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub after: Option<Vec<HandOff>>,
    /// Its place on the Teams canvas, in points; absent, Echo lays it out.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub x: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub y: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cli: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    /// The fields a Member held before they moved into its Profile (features/0095): read only so
    /// `migrate` can move them, and never written.
    #[serde(skip_serializing)]
    pub instructions: Option<String>,
    #[serde(skip_serializing)]
    pub replace_role: bool,
    #[serde(skip_serializing)]
    pub tools: Vec<String>,
    #[serde(skip_serializing)]
    pub skills: Vec<String>,
    #[serde(skip_serializing)]
    pub context: Vec<String>,
    #[serde(skip_serializing)]
    pub lessons: Option<bool>,
    #[serde(skip_serializing)]
    pub writes: Option<bool>,
    #[serde(skip_serializing)]
    pub worktree: Option<String>,
}

/// A line into a Member from the Orchestrator or another Member, saying what follows: a hint the
/// Orchestrator reads, or with `auto` one the daemon carries out itself (features/0093).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct HandOff {
    /// A Member's `id`, or `ORCHESTRATOR`.
    pub from: String,
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub auto: bool,
}

/// The `from` of a Hand-off out of the Orchestrator; no Member may take it as its `id`.
pub const ORCHESTRATOR: &str = "orchestrator";

/// The most Members a Team holds.
pub const MAX_MEMBERS: usize = 24;

impl Team {
    /// The Member a name stands for: a Member `id` first, else the first Member in tree order whose
    /// `profile` is the name.
    pub fn member_for(&self, name: &str) -> Option<&Member> {
        self.members
            .iter()
            .find(|member| member.id == name)
            .or_else(|| self.members.iter().find(|member| member.profile == name))
    }

    /// The Members with a Hand-off from `id` (a Member's, or `ORCHESTRATOR`), in file order.
    pub fn following(&self, id: &str) -> Vec<&Member> {
        self.members
            .iter()
            .filter(|member| member.hand_offs().iter().any(|hand_off| hand_off.from == id))
            .collect()
    }

    /// The Members the daemon starts itself when a Worker of `id` ends done (features/0093).
    pub fn automatic_after(&self, id: &str) -> Vec<&Member> {
        self.members
            .iter()
            .filter(|member| {
                member
                    .hand_offs()
                    .iter()
                    .any(|hand_off| hand_off.from == id && hand_off.auto)
            })
            .collect()
    }

    /// The Member that verifies the writer `id`: the first, in file order, with a Hand-off from it
    /// whose Action is `verify` (features/0092).
    pub fn verifier_of(&self, id: &str) -> Option<&Member> {
        self.following(id).into_iter().find(|member| member.action == "verify")
    }

    /// What the Team names for every Worker whose Member does not name its own (features/0094).
    pub fn workers_choice(&self) -> Choice {
        self.workers
            .as_ref()
            .map(|workers| workers.all.clone())
            .unwrap_or_default()
    }
}

impl Member {
    /// The Hand-offs into it; a Member without `after` hangs from the Orchestrator.
    pub fn hand_offs(&self) -> Vec<HandOff> {
        self.after.clone().unwrap_or_else(|| {
            vec![HandOff {
                from: ORCHESTRATOR.into(),
                auto: false,
            }]
        })
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WorkersSetup {
    /// For every Worker the Team does not name.
    #[serde(flatten)]
    pub all: Choice,
    /// A Profile's name to what its Workers ran with, from before features/0094: read only so
    /// `migrate` can move each entry onto that Profile's Members, and never written.
    #[serde(skip_serializing)]
    pub profiles: BTreeMap<String, Choice>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RulesSetup {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_workers: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub plan_approval: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub review: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub merge_without_asking: Option<bool>,
    /// How many times a writer whose verification fails is sent back with the findings before it
    /// needs the human (features/0104); 1 when absent.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verify_retries: Option<u64>,
}

/// Where a Team comes from; a later level wins.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Origin {
    Shipped,
    User,
    Repo,
}

impl Origin {
    pub fn label(self) -> &'static str {
        match self {
            Origin::Shipped => "shipped",
            Origin::User => "user",
            Origin::Repo => "repo",
        }
    }

    pub fn parse(name: &str) -> Result<Origin> {
        match name {
            "user" => Ok(Origin::User),
            "repo" => Ok(Origin::Repo),
            "shipped" => bail!("Echo's own Teams are not changed; duplicate one into yours"),
            other => bail!("a Team level is user or repo, not {other:?}"),
        }
    }
}

/// Each level's folder, Echo's first. `repo` is a checkout; without one there is no repo level.
pub fn dirs(hub: &Path, state: &Path, repo: Option<&Path>) -> Vec<(Origin, PathBuf)> {
    let mut dirs = vec![
        (Origin::Shipped, hub.join("teams")),
        (Origin::User, state.join("teams")),
    ];
    if let Some(repo) = repo {
        dirs.push((Origin::Repo, repo.join(".echo").join("teams")));
    }
    dirs
}

/// The folder a level's Teams are written to; Echo's own is never written.
pub fn level_dir(state: &Path, repo: Option<&Path>, origin: Origin) -> Result<PathBuf> {
    match (origin, repo) {
        (Origin::Shipped, _) => bail!("Echo's own Teams are not changed; duplicate one into yours"),
        (Origin::User, _) => Ok(state.join("teams")),
        (Origin::Repo, Some(repo)) => Ok(repo.join(".echo").join("teams")),
        (Origin::Repo, None) => bail!("a repo's Team needs a git checkout"),
    }
}

/// One name's winning file: the Team it parses to, if it does, and what is wrong with it, if
/// anything. A Team with a `problem` is listed but cannot be used.
#[derive(Debug)]
pub struct Entry {
    pub name: String,
    pub origin: Origin,
    pub path: PathBuf,
    /// The levels below that this file replaces.
    pub replaces: Vec<Origin>,
    pub team: Option<Team>,
    pub problem: Option<String>,
}

/// The CLI a field with no `cli` of its own runs on at the bottom: the repo's `cli` setting, else
/// the human's, else claude.
pub fn default_cli(state: &Path, repo: Option<&Path>) -> Cli {
    let from = |dir: &Path| {
        let settings = settings::read(dir).ok()?;
        Cli::parse(settings.get("cli")?.as_str()?).ok()
    };
    repo.and_then(|repo| from(&repo.join(".echo")))
        .or_else(|| from(state))
        .unwrap_or(Cli::Claude)
}

/// The context size at which an idle Orchestrator is renewed: its Team's `rotateAt` (0 is off)
/// where it has one, else the human's `orchestratorRotateAt`.
pub fn rotate_at(human: &serde_json::Map<String, serde_json::Value>, team: Option<&Team>) -> Option<u64> {
    match team.and_then(|team| team.orchestrator.as_ref()?.rotate_at) {
        Some(at) => Some(at).filter(|at| *at > 0),
        None => settings::orchestrator_rotate_at(human),
    }
}

/// Every Team name across the levels, sorted, each with its winning file.
pub fn list(hub: &Path, state: &Path, repo: Option<&Path>) -> Vec<Entry> {
    let mut found: Vec<(String, Origin, PathBuf)> = Vec::new();
    for (origin, dir) in dirs(hub, state, repo) {
        let Ok(read) = std::fs::read_dir(&dir) else { continue };
        for entry in read.flatten() {
            let path = entry.path();
            if path.extension().is_some_and(|e| e == "json") {
                if let Some(stem) = path.file_stem() {
                    found.push((stem.to_string_lossy().into_owned(), origin, path));
                }
            }
        }
    }
    for (name, origin, path) in &found {
        match migrate(hub, state, repo, *origin, name, path) {
            Ok(moved) => {
                for line in moved {
                    eprintln!("echo: team {name} ({}): {line}", origin.label());
                }
            }
            Err(e) => eprintln!("echo: team {name} ({}): nothing moved yet: {e}", origin.label()),
        }
    }
    let mut names: Vec<String> = found.iter().map(|(name, _, _)| name.clone()).collect();
    names.sort();
    names.dedup();
    let fallback = default_cli(state, repo);
    names
        .into_iter()
        .map(|name| {
            let mut levels: Vec<&(String, Origin, PathBuf)> = found.iter().filter(|(n, _, _)| *n == name).collect();
            levels.sort_by_key(|(_, origin, _)| *origin as u8);
            let (_, origin, path) = levels.pop().unwrap().clone();
            let replaces = levels.iter().map(|(_, origin, _)| *origin).collect();
            let (team, problem) = match read(&name, &path) {
                Err(e) => (None, Some(e.to_string())),
                Ok(team) => {
                    let problem = validate(&team, fallback)
                        .err()
                        .map(|e| format!("{}: {e}", path.display()));
                    (Some(team), problem)
                }
            };
            Entry {
                name,
                origin,
                path,
                replaces,
                team,
                problem,
            }
        })
        .collect()
}

/// The Team a session starts with; a Team that does not parse or validate is an error.
pub fn load(hub: &Path, state: &Path, repo: Option<&Path>, name: &str) -> Result<Team> {
    let all = list(hub, state, repo);
    let known: Vec<String> = all.iter().map(|entry| entry.name.clone()).collect();
    let Some(entry) = all.into_iter().find(|entry| entry.name == name) else {
        bail!("unknown team {name:?}; known: {}", known.join(", "));
    };
    match (entry.problem, entry.team) {
        (Some(problem), _) => Err(anyhow!(problem)),
        (None, Some(team)) => Ok(team),
        (None, None) => bail!("team {name:?} has no content"),
    }
}

/// Writes `team` as `<name>.json` in `dir` (a level's folder, see `level_dir`), whole and atomically:
/// the file is complete or the old one stays. The name and every field are checked first, so a Team
/// that cannot run is never written; `fallback` is the CLI a field without its own runs on.
pub fn save(dir: &Path, team: &Team, fallback: Cli) -> Result<PathBuf> {
    if !valid_name(&team.name) {
        bail!("a Team name is 1 to 40 lowercase letters, digits, and -, like claude-lean");
    }
    validate(team, fallback)?;
    write(dir, team)
}

/// Writes `team` as `<name>.json` in `dir`, whole and atomically, unchecked.
fn write(dir: &Path, team: &Team) -> Result<PathBuf> {
    std::fs::create_dir_all(dir)?;
    let to = dir.join(format!("{}.json", team.name));
    let part = dir.join(format!(".{}.json.{}.part", team.name, std::process::id()));
    let text = serde_json::to_string_pretty(team)? + "\n";
    std::fs::write(&part, text)
        .and_then(|()| std::fs::rename(&part, &to))
        .map_err(|e| {
            let _ = std::fs::remove_file(&part);
            anyhow!("writing {}: {e}", to.display())
        })?;
    Ok(to)
}

/// The Member keys that moved into Profiles (features/0094, 0095).
const MOVED: [&str; 8] = [
    "instructions",
    "replaceRole",
    "tools",
    "skills",
    "context",
    "lessons",
    "writes",
    "worktree",
];

/// Moves what a user or repo Team's file still holds in the old places, once (features/0095). A
/// `workers.profiles.<P>` entry fills each field that a Member of Profile P leaves out; a Member that
/// sets any of `MOVED` starts from a new Profile `<team>-<member>` at the Team's level, its Profile
/// with those fields laid over it as features/0084 laid them. The Team file is then written without
/// them. Echo's own Teams are never written. Returns what moved, one line each; nothing when the
/// file holds nothing to move. A Member whose Profile does not load stops the whole move, so it is
/// tried again at the next listing and nothing is half moved.
pub fn migrate(
    hub: &Path,
    state: &Path,
    repo: Option<&Path>,
    origin: Origin,
    name: &str,
    path: &Path,
) -> Result<Vec<String>> {
    static ONE_AT_A_TIME: std::sync::Mutex<()> = std::sync::Mutex::new(());
    if origin == Origin::Shipped || !valid_name(name) {
        return Ok(Vec::new());
    }
    let _held = ONE_AT_A_TIME.lock().unwrap_or_else(|e| e.into_inner());
    let Ok(text) = std::fs::read_to_string(path) else {
        return Ok(Vec::new());
    };
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&text) else {
        return Ok(Vec::new());
    };
    let old_member_keys = value["members"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(serde_json::Value::as_object)
        .any(|member| MOVED.iter().any(|key| member.contains_key(*key)));
    if !old_member_keys && value["workers"].get("profiles").is_none() {
        return Ok(Vec::new());
    }
    let Ok(mut team) = from_value(value) else {
        return Ok(Vec::new());
    };
    team.name = name.to_string();
    let mut moved = Vec::new();

    let entries = team
        .workers
        .as_mut()
        .map(|workers| std::mem::take(&mut workers.profiles))
        .unwrap_or_default();
    for (profile, choice) in entries {
        let mut onto = Vec::new();
        for member in team.members.iter_mut().filter(|member| member.profile == profile) {
            for (own, entry) in [
                (&mut member.cli, &choice.cli),
                (&mut member.model, &choice.model),
                (&mut member.effort, &choice.effort),
            ] {
                if own.is_none() {
                    own.clone_from(entry);
                }
            }
            onto.push(member.id.clone());
        }
        moved.push(match onto.is_empty() {
            true => format!("workers.profiles.{profile} dropped: no Member starts from {profile}"),
            false => format!("workers.profiles.{profile} moved onto {}", onto.join(", ")),
        });
    }

    let level = match origin {
        Origin::Repo => profile::Level::Repo,
        _ => profile::Level::Yours,
    };
    let dir = profile::level_dir(state, repo, level)?;
    let mut taken: Vec<String> = profile::entries(hub, state, repo)
        .into_iter()
        .map(|entry| entry.name)
        .collect();
    let mut writes = Vec::new();
    for member in &mut team.members {
        let fields = moved_fields(member);
        if !fields.is_empty() {
            // A user Team is used in every repo, so its Member's Profile is the one outside any repo,
            // unless only this repo has it.
            let base = match origin {
                Origin::User => profile::load(hub, state, None, &member.profile)
                    .or_else(|_| profile::load(hub, state, repo, &member.profile)),
                _ => profile::load(hub, state, repo, &member.profile),
            }
            .map_err(|e| anyhow!("members.{}: {e}", member.id))?;
            let new = unique_profile_name(&format!("{name}-{}", member.id), &taken);
            if !profile::valid_name(&new) {
                bail!("members.{}: {new:?} is not a Profile name", member.id);
            }
            let mut laid = base.with_member(member);
            laid.name = new.clone();
            taken.push(new.clone());
            moved.push(format!(
                "members.{}'s {} moved into Profile {new}, from {}",
                member.id,
                fields.join(", "),
                member.profile
            ));
            writes.push((dir.join(format!("{new}.md")), laid.file_text()));
            member.profile = new;
        }
        member.instructions = None;
        member.replace_role = false;
        member.tools.clear();
        member.skills.clear();
        member.context.clear();
        member.lessons = None;
        member.writes = None;
        member.worktree = None;
    }
    if !writes.is_empty() {
        std::fs::create_dir_all(&dir)?;
    }
    for (to, text) in writes {
        std::fs::write(&to, text).map_err(|e| anyhow!("writing {}: {e}", to.display()))?;
    }
    let dir = path.parent().unwrap_or(Path::new("."));
    write(dir, &team)?;
    moved.push(format!("{} written without the moved fields", path.display()));
    Ok(moved)
}

/// The moved fields a Member sets in a way that changes its Worker, by their file names.
fn moved_fields(member: &Member) -> Vec<&'static str> {
    let mut fields = Vec::new();
    if member
        .instructions
        .as_deref()
        .is_some_and(|text| !text.trim().is_empty())
    {
        fields.push(if member.replace_role {
            "instructions (replace role)"
        } else {
            "instructions"
        });
    }
    for (key, list) in [
        ("tools", &member.tools),
        ("skills", &member.skills),
        ("context", &member.context),
    ] {
        if !list.is_empty() {
            fields.push(key);
        }
    }
    for (key, set) in [("lessons", member.lessons), ("writes", member.writes)] {
        if set.is_some() {
            fields.push(key);
        }
    }
    if member
        .worktree
        .as_deref()
        .is_some_and(|worktree| profile::WORKTREES.contains(&worktree))
    {
        fields.push("worktree");
    }
    fields
}

/// `wanted` as a Profile name: at most 32 characters, then `-2`, `-3` and on until no name in
/// `taken` has it.
fn unique_profile_name(wanted: &str, taken: &[String]) -> String {
    let fit = |suffix: &str| {
        let room = 32 - suffix.len();
        let base: String = wanted.chars().take(room).collect();
        format!("{}{suffix}", base.trim_end_matches('-'))
    };
    let mut name = fit("");
    let mut n = 2;
    while taken.contains(&name) {
        name = fit(&format!("-{n}"));
        n += 1;
    }
    name
}

/// Deletes the Team's file at `origin`, so the one below it is in force again; Echo's own are
/// never deleted.
pub fn delete(state: &Path, repo: Option<&Path>, origin: Origin, name: &str) -> Result<()> {
    if !valid_name(name) {
        bail!("{name:?} is not a Team name");
    }
    let path = level_dir(state, repo, origin)?.join(format!("{name}.json"));
    if !path.exists() {
        bail!("{name} has no {} copy to delete", origin.label());
    }
    std::fs::remove_file(path)?;
    Ok(())
}

/// A Team in one line, for a list: what its Orchestrator and its Workers run with, as far as it
/// says; what it leaves out comes from the level below.
pub fn summary(team: &Team) -> String {
    let part = |cli: &Option<String>, model: &Option<String>, effort: &Option<String>| {
        let words: Vec<&str> = [cli, model, effort].into_iter().flatten().map(String::as_str).collect();
        if words.is_empty() {
            "as set elsewhere".to_string()
        } else {
            words.join(" ")
        }
    };
    let orchestrator = team
        .orchestrator
        .as_ref()
        .map(|o| part(&o.cli, &o.model, &o.effort))
        .unwrap_or_else(|| "as set elsewhere".into());
    let workers = team
        .workers
        .as_ref()
        .map(|w| part(&w.all.cli, &w.all.model, &w.all.effort))
        .unwrap_or_else(|| "by their Profiles".into());
    let members = match team.members.len() {
        0 => String::new(),
        1 => ", 1 Member".to_string(),
        n => format!(", {n} Members"),
    };
    format!("orchestrator: {orchestrator}; workers: {workers}{members}")
}

/// Every field a Team sets, one per line, for `echoctl team show`.
pub fn details(team: &Team) -> String {
    let mut lines = Vec::new();
    if let Some(o) = &team.orchestrator {
        pick_lines(&mut lines, "orchestrator", &o.cli, &o.model, &o.effort);
        if let Some(at) = o.rotate_at {
            lines.push(format!("orchestrator.rotateAt: {at}"));
        }
    }
    if let Some(w) = &team.workers {
        pick_lines(&mut lines, "workers", &w.all.cli, &w.all.model, &w.all.effort);
    }
    if let Some(r) = &team.rules {
        if let Some(max) = r.max_workers {
            lines.push(format!("rules.maxWorkers: {max}"));
        }
        if let Some(retries) = r.verify_retries {
            lines.push(format!("rules.verifyRetries: {retries}"));
        }
        for (key, value) in [
            ("planApproval", r.plan_approval),
            ("review", r.review),
            ("mergeWithoutAsking", r.merge_without_asking),
        ] {
            if let Some(value) = value {
                lines.push(format!("rules.{key}: {value}"));
            }
        }
    }
    if !team.members.is_empty() {
        lines.push("members:".to_string());
        lines.extend(member_lines(team));
    }
    if let Some(text) = &team.instructions {
        lines.push(format!("instructions:\n{}", text.trim_end()));
    }
    lines.join("\n")
}

fn pick_lines(
    lines: &mut Vec<String>,
    label: &str,
    cli: &Option<String>,
    model: &Option<String>,
    effort: &Option<String>,
) {
    for (key, value) in [("cli", cli), ("model", model), ("effort", effort)] {
        if let Some(value) = value {
            lines.push(format!("{label}.{key}: {value}"));
        }
    }
}

/// Every Member's `profile` is one of `known`; the daemon checks this when it saves and uses a Team,
/// and `validate` does not, since the file format cannot know the Profiles.
pub fn check_profiles<S: AsRef<str>>(team: &Team, known: &[S]) -> Result<()> {
    for member in &team.members {
        if !known.iter().any(|name| name.as_ref() == member.profile) {
            let names: Vec<&str> = known.iter().map(AsRef::as_ref).collect();
            bail!(
                "members.{}: profile {:?} is not a Profile; known: {}",
                member.id,
                member.profile,
                names.join(", ")
            );
        }
    }
    Ok(())
}

/// The Members as lines, one per Member in file order, each with the Hand-offs into it.
fn member_lines(team: &Team) -> Vec<String> {
    team.members
        .iter()
        .map(|member| {
            let from: Vec<String> = member
                .hand_offs()
                .iter()
                .map(|hand_off| {
                    if hand_off.auto {
                        format!("{} (automatic)", hand_off.from)
                    } else {
                        hand_off.from.clone()
                    }
                })
                .collect();
            let after = if from.is_empty() {
                "nothing".to_string()
            } else {
                from.join(", ")
            };
            format!("  {}  after {after}", member_line(member))
        })
        .collect()
}

/// `build  execute  naruto  claude-sonnet-5-5  high`: the id, Action and Profile, then the CLI, model
/// and effort it sets.
fn member_line(member: &Member) -> String {
    let mut words = vec![member.id.clone(), member.action.clone(), member.profile.clone()];
    words.extend(
        [&member.cli, &member.model, &member.effort]
            .into_iter()
            .flatten()
            .cloned(),
    );
    words.join("  ")
}

/// Team names are file names, and appear in commands and the New session sheet.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 40
        && name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        && !name.starts_with('-')
}

fn read(name: &str, path: &Path) -> Result<Team> {
    let text = std::fs::read_to_string(path).map_err(|e| anyhow!("reading {}: {e}", path.display()))?;
    let mut team = parse(&text).map_err(|e| anyhow!("{}: {e}", path.display()))?;
    team.name = name.to_string();
    Ok(team)
}

/// A Team's fields from its JSON; unknown fields are left out, a wrong type is an error. The name
/// is the file's, so it is left empty here.
pub fn parse(text: &str) -> Result<Team> {
    from_value(serde_json::from_str(text)?)
}

/// A Team from JSON already read, a `parent` from before Hand-offs read as one Hand-off from it.
pub fn from_value(value: serde_json::Value) -> Result<Team> {
    let mut team: Team = serde_json::from_value(value)?;
    for member in &mut team.members {
        if let Some(parent) = member.parent.take() {
            if member.after.is_none() {
                member.after = Some(vec![HandOff {
                    from: parent,
                    auto: false,
                }]);
            }
        }
    }
    Ok(team)
}

/// What is wrong with the Team's fields, if anything. `fallback` is the CLI a model with no `cli`
/// of its own is checked against, after the Team's own `cli` for that part.
pub fn validate(team: &Team, fallback: Cli) -> Result<()> {
    if !valid_name(&team.name) {
        bail!("a Team name is 1 to 40 lowercase letters, digits, and -, like claude-lean");
    }
    if let Some(orchestrator) = &team.orchestrator {
        let own = orchestrator.cli.as_deref();
        check_pick(
            "orchestrator",
            own,
            own,
            orchestrator.model.as_deref(),
            orchestrator.effort.as_deref(),
            fallback,
        )?;
        if let Some(at) = orchestrator.rotate_at {
            if at != 0 && at < MIN_ROTATE_AT {
                bail!("orchestrator.rotateAt is 0 (never renew) or at least {MIN_ROTATE_AT} tokens, not {at}");
            }
        }
    }
    if let Some(workers) = &team.workers {
        let all = &workers.all;
        let shared = all.cli.as_deref();
        check_pick(
            "workers",
            shared,
            shared,
            all.model.as_deref(),
            all.effort.as_deref(),
            fallback,
        )?;
    }
    if let Some(max) = team.rules.as_ref().and_then(|rules| rules.max_workers) {
        if !(1..=16).contains(&max) {
            bail!("rules.maxWorkers is 1 to 16, not {max}");
        }
    }
    if let Some(retries) = team.rules.as_ref().and_then(|rules| rules.verify_retries) {
        if !(1..=10).contains(&retries) {
            bail!("rules.verifyRetries is 1 to 10, not {retries}");
        }
    }
    validate_members(team, fallback)
}

/// The Members: their count, ids, Actions and picks, then the shape of the tree.
fn validate_members(team: &Team, fallback: Cli) -> Result<()> {
    let members = &team.members;
    if members.len() > MAX_MEMBERS {
        bail!(
            "members: a Team holds at most {MAX_MEMBERS} Members, not {}",
            members.len()
        );
    }
    for (at, member) in members.iter().enumerate() {
        if !profile::valid_name(&member.id) {
            bail!(
                "members[{at}]: id {:?} is 1 to 32 lowercase letters, digits, and -, like build-2",
                member.id
            );
        }
        if members[..at].iter().any(|before| before.id == member.id) {
            bail!("members.{}: id is used by another Member", member.id);
        }
    }
    for member in members {
        let field = format!("members.{}", member.id);
        if !action::is_action(&member.action) {
            bail!(
                "{field}: action {:?} is not one of {}, {}",
                member.action,
                action::IDS.join(", "),
                action::CUSTOM
            );
        }
        if member.profile.trim().is_empty() {
            bail!("{field}: profile is empty; name the Profile it starts from");
        }
        let inherited = team.workers_choice().cli;
        check_pick(
            &field,
            member.cli.as_deref(),
            inherited.as_deref(),
            member.model.as_deref(),
            member.effort.as_deref(),
            fallback,
        )?;
    }
    for member in members {
        let field = format!("members.{}", member.id);
        if member.id == ORCHESTRATOR {
            bail!("{field}: {ORCHESTRATOR} is the Orchestrator's id; pick another");
        }
        let hand_offs = member.hand_offs();
        if hand_offs.is_empty() {
            bail!("{field}: no Hand-off comes into it, so the Orchestrator cannot reach it");
        }
        for (at, hand_off) in hand_offs.iter().enumerate() {
            if hand_offs[..at].iter().any(|before| before.from == hand_off.from) {
                bail!("{field}: two Hand-offs come from {}", hand_off.from);
            }
            let source = if hand_off.from == ORCHESTRATOR {
                None
            } else {
                Some(
                    members
                        .iter()
                        .find(|other| other.id == hand_off.from)
                        .ok_or_else(|| anyhow!("{field}: after {:?} is not a Member", hand_off.from))?,
                )
            };
            if member.action == "verify" && source.is_none_or(|source| source.action != "execute") {
                bail!("{field}: a verify Member comes only after execute Members");
            }
            if hand_off.auto && source.is_none() {
                bail!("{field}: a Hand-off from the Orchestrator cannot be automatic");
            }
            if hand_off.auto && member.action == "verify" {
                bail!("{field}: a Hand-off into a verify Member runs through --verify and cannot be automatic");
            }
        }
        if hand_offs.iter().filter(|hand_off| hand_off.auto).count() > 1 {
            bail!("{field}: at most one automatic Hand-off comes into a Member");
        }
    }
    // Hand-offs never loop: walking back from any Member along them always ends at the Orchestrator.
    fn loops<'a>(members: &'a [Member], id: &'a str, path: &mut Vec<&'a str>) -> bool {
        if path.contains(&id) {
            return true;
        }
        let Some(member) = members.iter().find(|member| member.id == id) else {
            return false;
        };
        path.push(id);
        let found = member
            .after
            .iter()
            .flatten()
            .any(|hand_off| loops(members, &hand_off.from, path));
        path.pop();
        found
    }
    for member in members {
        if loops(members, &member.id, &mut Vec::new()) {
            bail!("members.{}: its Hand-offs lead back to itself", member.id);
        }
    }
    Ok(())
}

/// The least `rotateAt` that is not off, as for the human's `orchestratorRotateAt`.
const MIN_ROTATE_AT: u64 = 10_000;

/// One `cli`, `model`, `effort` triple: the cli is known, the effort is one it takes, and the
/// model is one it accepts. A model with no `cli` of its own is checked against `inherited` (the
/// Team's cli for that part), else `fallback`.
fn check_pick(
    field: &str,
    cli: Option<&str>,
    inherited: Option<&str>,
    model: Option<&str>,
    effort: Option<&str>,
    fallback: Cli,
) -> Result<()> {
    let own = cli
        .map(|name| Cli::parse(name).map_err(|e| anyhow!("{field}.cli: {e}")))
        .transpose()?;
    let applies = match (own, inherited) {
        (Some(cli), _) => cli,
        (None, Some(name)) => Cli::parse(name).map_err(|e| anyhow!("{field}.cli: {e}"))?,
        (None, None) => fallback,
    };
    if let Some(model) = model {
        if model.trim().is_empty() {
            bail!("{field}.model is empty; leave it out to use the level below");
        }
        applies
            .model_arg(model)
            .map_err(|e| anyhow!("{field}.model on {}: {e}", applies.name()))?;
    }
    if let Some(effort) = effort {
        if !settings::EFFORTS.contains(&effort) {
            bail!(
                "{field}.effort {effort:?} is not one of {} for {}",
                settings::EFFORTS.join(", "),
                applies.name()
            );
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!("hub-team-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        root
    }

    fn put(dir: &Path, name: &str, text: &str) {
        std::fs::create_dir_all(dir).unwrap();
        std::fs::write(dir.join(format!("{name}.json")), text).unwrap();
    }

    fn named(name: &str, text: &str) -> Team {
        let mut team = parse(text).unwrap();
        team.name = name.to_string();
        team
    }

    fn problem(name: &str, text: &str) -> String {
        validate(&named(name, text), Cli::Claude).unwrap_err().to_string()
    }

    #[test]
    fn a_teams_rotate_at_replaces_the_humans_and_zero_turns_renewal_off() {
        let human = serde_json::json!({ "orchestratorRotateAt": 200_000 });
        let human = human.as_object().unwrap();
        let with = |text: &str| named("t", text);
        assert_eq!(rotate_at(human, None), Some(200_000));
        assert_eq!(rotate_at(human, Some(&with("{}"))), Some(200_000));
        assert_eq!(
            rotate_at(
                human,
                Some(&with(r#"{"orchestrator": {"model": "claude-sonnet-5-5"}}"#))
            ),
            Some(200_000),
            "no rotateAt in the Team leaves the human's"
        );
        assert_eq!(
            rotate_at(human, Some(&with(r#"{"orchestrator": {"rotateAt": 150000}}"#))),
            Some(150_000),
            "the Team's size is used as written, below the human's floor too"
        );
        assert_eq!(
            rotate_at(human, Some(&with(r#"{"orchestrator": {"rotateAt": 0}}"#))),
            None
        );
        assert_eq!(
            rotate_at(
                &serde_json::Map::new(),
                Some(&with(r#"{"orchestrator": {"rotateAt": 20000}}"#))
            ),
            Some(20_000)
        );
    }

    #[test]
    fn each_shipped_seed_parses_to_what_the_plan_lists() {
        let hub = crate::paths::hub_dir();
        let opus = read("claude-opus", &hub.join("teams/claude-opus.json")).unwrap();
        let orchestrator = opus.orchestrator.clone().unwrap();
        assert_eq!(orchestrator.cli.as_deref(), Some("claude"));
        assert_eq!(orchestrator.model.as_deref(), Some("anthropic/claude-opus-5-5"));
        assert_eq!(orchestrator.effort.as_deref(), Some("high"));
        assert_eq!(orchestrator.rotate_at, None);
        assert_eq!(opus.workers, None);
        assert_eq!(shipped_tree(&opus), SHIPPED_TREE);

        let lean = read("claude-lean", &hub.join("teams/claude-lean.json")).unwrap();
        let orchestrator = lean.orchestrator.clone().unwrap();
        assert_eq!(orchestrator.model.as_deref(), Some("anthropic/claude-sonnet-5-5"));
        assert_eq!(orchestrator.effort.as_deref(), Some("medium"));
        assert_eq!(orchestrator.rotate_at, Some(150_000));
        assert_eq!(lean.workers, None);
        assert_eq!(shipped_tree(&lean), SHIPPED_TREE);

        let kiro = read("kiro-lean", &hub.join("teams/kiro-lean.json")).unwrap();
        let orchestrator = kiro.orchestrator.clone().unwrap();
        assert_eq!(orchestrator.cli.as_deref(), Some("kiro"));
        assert_eq!(orchestrator.model.as_deref(), Some("claude-sonnet-5.5"));
        assert_eq!(orchestrator.effort.as_deref(), Some("medium"));
        let workers = kiro.workers.clone().unwrap();
        assert_eq!(workers.all.cli.as_deref(), Some("kiro"));
        assert_eq!(workers.all.model.as_deref(), Some("claude-haiku-5.5"));
        assert_eq!(workers.all.effort.as_deref(), Some("low"));
        assert!(workers.profiles.is_empty(), "the per-Profile picks live in the Members");
        assert_eq!(shipped_tree(&kiro), SHIPPED_TREE);
        let picks: Vec<(&str, Option<&str>, Option<&str>)> = kiro
            .members
            .iter()
            .map(|member| (member.id.as_str(), member.model.as_deref(), member.effort.as_deref()))
            .collect();
        assert_eq!(
            picks,
            [
                ("scan", None, None),
                ("research", None, None),
                ("build", Some("claude-sonnet-5.5"), Some("high")),
                ("check", Some("claude-sonnet-5.5"), Some("medium")),
                ("run", None, None),
                ("scribe", None, None),
            ]
        );
        for member in &kiro.members {
            assert_eq!(member.cli, None, "{}", member.id);
        }
        for member in opus.members.iter().chain(&lean.members) {
            assert_eq!(
                (&member.cli, &member.model, &member.effort),
                (&None, &None, &None),
                "{}",
                member.id
            );
        }
    }

    /// Every shipped Team's tree: Member id, Action, Profile and parent, in tree order.
    const SHIPPED_TREE: [(&str, &str, &str, Option<&str>); 6] = [
        ("scan", "scan", "hinata", None),
        ("research", "research", "jiraiya", None),
        ("build", "execute", "naruto", None),
        ("check", "verify", "sasuke", Some("build")),
        ("run", "run", "lee", None),
        ("scribe", "scribe", "ino", None),
    ];

    fn shipped_tree(team: &Team) -> Vec<(&str, &str, &str, Option<&str>)> {
        team.members
            .iter()
            .map(|m| {
                (
                    m.id.as_str(),
                    m.action.as_str(),
                    m.profile.as_str(),
                    m.after.as_ref().map(|after| after[0].from.as_str()),
                )
            })
            .collect()
    }

    /// What each shipped Team gave a Worker of each Profile before it had Members: CLI, model and
    /// effort, written out from the old seed files.
    const BEFORE_MEMBERS: [(&str, [(&str, Cli, &str, &str); 6]); 3] = [
        ("claude-opus", CLAUDE_PROFILES),
        ("claude-lean", CLAUDE_PROFILES),
        (
            "kiro-lean",
            [
                ("hinata", Cli::Kiro, "claude-haiku-5.5", "low"),
                ("jiraiya", Cli::Kiro, "claude-haiku-5.5", "low"),
                ("naruto", Cli::Kiro, "claude-sonnet-5.5", "high"),
                ("sasuke", Cli::Kiro, "claude-sonnet-5.5", "medium"),
                ("lee", Cli::Kiro, "claude-haiku-5.5", "low"),
                ("ino", Cli::Kiro, "claude-haiku-5.5", "low"),
            ],
        ),
    ];

    /// The six Profiles as Echo ships them, which the two Claude Teams leave alone.
    const CLAUDE_PROFILES: [(&str, Cli, &str, &str); 6] = [
        ("hinata", Cli::Claude, "anthropic/claude-sonnet-5-5", "high"),
        ("jiraiya", Cli::Claude, "anthropic/claude-sonnet-5-5", "medium"),
        ("naruto", Cli::Claude, "anthropic/claude-sonnet-5-5", "high"),
        ("sasuke", Cli::Claude, "anthropic/claude-opus-5-5", "high"),
        ("lee", Cli::Claude, "anthropic/claude-haiku-5-5", "low"),
        ("ino", Cli::Claude, "anthropic/claude-haiku-5-5", "low"),
    ];

    #[test]
    fn a_shipped_teams_members_give_every_worker_what_its_profile_name_gave_before() {
        let hub = crate::paths::hub_dir();
        let state = scratch("seed-picks");
        let none = crate::cli::Choice::default();
        for (name, expected) in BEFORE_MEMBERS {
            let team = load(&hub, &state, None, name).unwrap();
            validate(&team, Cli::Claude).unwrap();
            for (profile, cli, model, effort) in expected {
                let loaded = crate::profile::load(&hub, &state, None, profile).unwrap();
                let want = (cli, Some(model.to_string()), Some(effort.to_string()));
                let by_profile = team.member_for(profile).unwrap();
                assert_eq!(by_profile.profile, profile, "{name}");
                let got = crate::profile::resolve(&state, None, &loaded, Some(&team), Some(by_profile), &none).unwrap();
                assert_eq!(got, want, "{name} {profile} by its Profile name");
                let by_id = team.members.iter().find(|m| m.profile == profile).unwrap();
                let by_id = team.member_for(&by_id.id).unwrap();
                let got = crate::profile::resolve(&state, None, &loaded, Some(&team), Some(by_id), &none).unwrap();
                assert_eq!(got, want, "{name} {profile} by its Member id");
            }
        }
        let _ = std::fs::remove_dir_all(state);
    }

    #[test]
    fn every_shipped_seed_validates_under_any_default_cli() {
        let hub = crate::paths::hub_dir();
        let state = scratch("seeds");
        let all = list(&hub, &state, None);
        let names: Vec<&str> = all.iter().map(|entry| entry.name.as_str()).collect();
        assert_eq!(names, ["claude-lean", "claude-opus", "kiro-lean"]);
        for entry in &all {
            assert_eq!(entry.origin, Origin::Shipped);
            assert_eq!(entry.problem, None, "{}", entry.name);
            for cli in [Cli::Claude, Cli::Codex, Cli::Kiro] {
                validate(entry.team.as_ref().unwrap(), cli).unwrap();
            }
        }
        let _ = std::fs::remove_dir_all(state);
    }

    #[test]
    fn a_later_level_replaces_a_team_whole_and_a_broken_one_says_why() {
        let root = scratch("levels");
        let (hub, state, repo) = (root.join("hub"), root.join("state"), root.join("repo"));
        let shipped = r#"{"description":"shipped","orchestrator":{"model":"claude-opus-5-5","effort":"high"},"instructions":"be brief"}"#;
        put(&hub.join("teams"), "plan", shipped);
        put(&hub.join("teams"), "lee", shipped);
        put(&hub.join("teams"), "solo", shipped);
        put(
            &state.join("teams"),
            "plan",
            r#"{"orchestrator":{"model":"claude-sonnet-5-5"}}"#,
        );
        put(&repo.join(".echo/teams"), "plan", r#"{"description":"repo's"}"#);
        put(&repo.join(".echo/teams"), "lee", r#"{"orchestrator":{"effort":5}}"#);

        let plan = load(&hub, &state, Some(&repo), "plan").unwrap();
        assert_eq!(plan.name, "plan");
        assert_eq!(plan.description.as_deref(), Some("repo's"));
        assert_eq!(plan.orchestrator, None, "whole file, no field taken from a lower level");
        assert_eq!(plan.instructions, None);

        let without_repo = load(&hub, &state, None, "plan").unwrap();
        assert_eq!(
            without_repo.orchestrator.unwrap().model.as_deref(),
            Some("claude-sonnet-5-5")
        );
        assert_eq!(
            load(&hub, &state, None, "solo").unwrap().instructions.as_deref(),
            Some("be brief")
        );

        let all = list(&hub, &state, Some(&repo));
        let names: Vec<&str> = all.iter().map(|entry| entry.name.as_str()).collect();
        assert_eq!(names, ["lee", "plan", "solo"]);
        let plan = all.iter().find(|entry| entry.name == "plan").unwrap();
        assert_eq!(plan.origin, Origin::Repo);
        assert_eq!(plan.replaces, [Origin::Shipped, Origin::User]);
        let solo = all.iter().find(|entry| entry.name == "solo").unwrap();
        assert_eq!(solo.origin, Origin::Shipped);
        assert!(solo.replaces.is_empty());

        let lee = all.iter().find(|entry| entry.name == "lee").unwrap();
        assert_eq!(lee.origin, Origin::Repo);
        assert!(lee.team.is_none());
        let why = lee.problem.as_deref().unwrap();
        assert!(why.contains("lee.json") && why.contains("invalid type"), "{why}");
        let err = load(&hub, &state, Some(&repo), "lee").unwrap_err().to_string();
        assert!(err.contains("lee.json"), "{err}");

        let err = load(&hub, &state, Some(&repo), "nope").unwrap_err().to_string();
        assert!(err.contains("unknown team") && err.contains("lee, plan, solo"), "{err}");
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn a_team_with_an_invalid_field_is_listed_with_its_problem_and_cannot_be_loaded() {
        let root = scratch("listed");
        let (hub, state) = (root.join("hub"), root.join("state"));
        put(&state.join("teams"), "bad", r#"{"workers":{"effort":"enormous"}}"#);
        let all = list(&hub, &state, None);
        assert_eq!(all.len(), 1);
        assert!(all[0].team.is_some());
        let why = all[0].problem.as_deref().unwrap();
        assert!(why.contains("bad.json") && why.contains("workers.effort"), "{why}");
        assert!(load(&hub, &state, None, "bad").is_err());
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn unknown_fields_are_ignored_and_wrong_types_name_the_file() {
        let root = scratch("types");
        let (hub, state) = (root.join("hub"), root.join("state"));
        put(
            &state.join("teams"),
            "newer",
            r#"{"future":1,"orchestrator":{"model":"claude-opus-5-5","speed":"fast"},"workers":{"profiles":{"lee":{"tier":2}}}}"#,
        );
        put(&state.join("teams"), "typo", r#"{"rules":{"maxWorkers":"four"}}"#);
        put(&state.join("teams"), "broken", "{ not json");
        assert_eq!(
            load(&hub, &state, None, "newer")
                .unwrap()
                .orchestrator
                .unwrap()
                .model
                .as_deref(),
            Some("claude-opus-5-5")
        );
        for name in ["typo", "broken"] {
            let err = load(&hub, &state, None, name).unwrap_err().to_string();
            assert!(err.contains(&format!("{name}.json")), "{err}");
        }
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn validation_refuses_what_cannot_run() {
        assert!(problem("t", r#"{"orchestrator":{"cli":"vim"}}"#).contains("orchestrator.cli"));
        assert!(problem("t", r#"{"workers":{"cli":"gemini"}}"#).contains("not supported yet"));
        let kiro = problem(
            "t",
            r#"{"orchestrator":{"cli":"kiro","model":"anthropic/claude-sonnet-5-5"}}"#,
        );
        assert!(kiro.contains("orchestrator.model") && kiro.contains("kiro"), "{kiro}");
        assert!(problem("t", r#"{"orchestrator":{"effort":"warp"}}"#).contains("orchestrator.effort"));
        assert!(problem("Bad Name", "{}").contains("Team name"));
        assert!(problem("t", r#"{"rules":{"maxWorkers":0}}"#).contains("rules.maxWorkers"));
        assert!(problem("t", r#"{"rules":{"maxWorkers":17}}"#).contains("rules.maxWorkers"));
        assert!(problem("t", r#"{"orchestrator":{"rotateAt":9999}}"#).contains("rotateAt"));
        assert!(problem("t", r#"{"workers":{"model":""}}"#).contains("workers.model"));
        validate(
            &named(
                "t",
                r#"{"workers":{"cli":"kiro","profiles":{"lee":{"model":"openai/gpt-5"}}}}"#,
            ),
            Cli::Claude,
        )
        .expect("a workers.profiles entry is not checked; it is only moved (features/0094)");
    }

    #[test]
    fn validation_accepts_the_edges() {
        for text in [
            "{}",
            r#"{"orchestrator":{"rotateAt":0}}"#,
            r#"{"orchestrator":{"rotateAt":10000}}"#,
            r#"{"rules":{"maxWorkers":1}}"#,
            r#"{"rules":{"maxWorkers":16,"planApproval":false,"review":false,"mergeWithoutAsking":true}}"#,
            r#"{"orchestrator":{"effort":"max"},"workers":{"effort":"xhigh"}}"#,
        ] {
            validate(&named("t", text), Cli::Claude).unwrap();
        }
    }

    #[test]
    fn a_model_without_a_cli_is_checked_against_the_cli_that_would_apply() {
        let bare = r#"{"orchestrator":{"model":"anthropic/claude-opus-5-5"}}"#;
        validate(&named("t", bare), Cli::Claude).unwrap();
        assert!(
            validate(&named("t", bare), Cli::Kiro).is_err(),
            "the settings' cli applies"
        );
        let own = r#"{"orchestrator":{"cli":"claude","model":"anthropic/claude-opus-5-5"}}"#;
        validate(&named("t", own), Cli::Kiro).unwrap();
        let workers = r#"{"workers":{"cli":"kiro","model":"claude-haiku-5.5"}}"#;
        validate(&named("t", workers), Cli::Claude).unwrap();
        let wrong = r#"{"workers":{"cli":"kiro","model":"anthropic/claude-haiku-5-5"}}"#;
        assert!(validate(&named("t", wrong), Cli::Claude).is_err());
    }

    #[test]
    fn the_settings_cli_is_the_fallback_and_a_repo_one_wins() {
        let root = scratch("fallback");
        let (state, repo) = (root.join("state"), root.join("repo"));
        assert_eq!(default_cli(&state, Some(&repo)), Cli::Claude);
        std::fs::create_dir_all(&state).unwrap();
        std::fs::write(state.join("settings.json"), r#"{"cli":"kiro"}"#).unwrap();
        assert_eq!(default_cli(&state, Some(&repo)), Cli::Kiro);
        std::fs::create_dir_all(repo.join(".echo")).unwrap();
        std::fs::write(repo.join(".echo/settings.json"), r#"{"cli":"codex"}"#).unwrap();
        assert_eq!(default_cli(&state, Some(&repo)), Cli::Codex);
        assert_eq!(default_cli(&state, None), Cli::Kiro);

        put(
            &state.join("teams"),
            "t",
            r#"{"orchestrator":{"model":"anthropic/claude-opus-5-5"}}"#,
        );
        let entry = &list(&root.join("hub"), &state, None)[0];
        assert!(entry.problem.is_some(), "under the human's kiro cli");
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn names_are_lowercase_letters_digits_and_dashes_and_never_a_path() {
        for good in ["a", "claude-lean", "team-2", &"x".repeat(40)] {
            assert!(valid_name(good), "{good}");
        }
        for bad in [
            "",
            "Upper",
            "has space",
            "a/b",
            "..",
            "../x",
            "a.b",
            "-lead",
            "ü",
            &"x".repeat(41),
        ] {
            assert!(!valid_name(bad), "{bad}");
        }
    }

    #[test]
    fn a_saved_team_loads_back_the_same_and_an_invalid_one_is_not_written() {
        let root = scratch("save");
        let (hub, state, repo) = (root.join("hub"), root.join("state"), root.join("repo"));
        let mut team = named(
            "mine",
            r#"{"description":"d","orchestrator":{"cli":"kiro","model":"claude-sonnet-5.5","effort":"low","rotateAt":0},
                "workers":{"cli":"kiro","model":"claude-haiku-5.5","effort":"high"},
                "rules":{"maxWorkers":2,"review":false},"instructions":"line one\nline two"}"#,
        );
        let dir = level_dir(&state, Some(&repo), Origin::User).unwrap();
        let path = save(&dir, &team, Cli::Claude).unwrap();
        assert_eq!(path, state.join("teams/mine.json"));
        assert_eq!(load(&hub, &state, Some(&repo), "mine").unwrap(), team);
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.contains("\n  \"orchestrator\""), "pretty printed: {text}");
        assert!(!text.contains("\"name\"") && !text.contains("null"), "{text}");
        let leftovers = std::fs::read_dir(&dir).unwrap().flatten().count();
        assert_eq!(leftovers, 1, "no partial file stays");

        team.description = Some("changed".into());
        save(&dir, &team, Cli::Claude).unwrap();
        assert_eq!(
            load(&hub, &state, None, "mine").unwrap().description.as_deref(),
            Some("changed")
        );

        let repo_dir = level_dir(&state, Some(&repo), Origin::Repo).unwrap();
        save(&repo_dir, &team, Cli::Claude).unwrap();
        let entry = &list(&hub, &state, Some(&repo))[0];
        assert_eq!(entry.origin, Origin::Repo);
        assert_eq!(entry.replaces, [Origin::User]);

        let mut bad = team.clone();
        bad.name = "../escape".into();
        assert!(save(&dir, &bad, Cli::Claude)
            .unwrap_err()
            .to_string()
            .contains("Team name"));
        let mut bad = team.clone();
        bad.rules = Some(RulesSetup {
            max_workers: Some(0),
            ..RulesSetup::default()
        });
        bad.name = "zero".into();
        assert!(save(&dir, &bad, Cli::Claude).is_err());
        assert!(!dir.join("zero.json").exists());
        assert!(!root.join("escape.json").exists() && !state.join("escape.json").exists());
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn delete_removes_a_user_or_repo_copy_and_refuses_a_shipped_team() {
        let root = scratch("delete");
        let (hub, state, repo) = (root.join("hub"), root.join("state"), root.join("repo"));
        put(&hub.join("teams"), "plan", r#"{"description":"shipped"}"#);
        put(&state.join("teams"), "plan", r#"{"description":"mine"}"#);
        put(&repo.join(".echo/teams"), "plan", r#"{"description":"repo's"}"#);

        let err = delete(&state, Some(&repo), Origin::Shipped, "plan")
            .unwrap_err()
            .to_string();
        assert!(err.contains("Echo's own"), "{err}");
        assert!(hub.join("teams/plan.json").exists());
        assert!(Origin::parse("shipped").is_err());

        delete(&state, Some(&repo), Origin::Repo, "plan").unwrap();
        assert_eq!(
            load(&hub, &state, Some(&repo), "plan").unwrap().description.as_deref(),
            Some("mine")
        );
        delete(&state, Some(&repo), Origin::User, "plan").unwrap();
        assert_eq!(
            load(&hub, &state, Some(&repo), "plan").unwrap().description.as_deref(),
            Some("shipped")
        );
        assert!(
            delete(&state, Some(&repo), Origin::User, "plan").is_err(),
            "nothing left to delete"
        );
        assert!(
            delete(&state, None, Origin::Repo, "plan").is_err(),
            "no checkout, no repo level"
        );
        assert!(delete(&state, None, Origin::User, "../x").is_err());
        let _ = std::fs::remove_dir_all(root);
    }

    const TREE: &str = r#"{
        "workers": {"cli": "claude"},
        "members": [
            {"id": "build", "action": "execute", "profile": "naruto", "model": "claude-sonnet-5-5", "effort": "high"},
            {"id": "check", "action": "verify", "profile": "sasuke", "parent": "build", "effort": "low"},
            {"id": "docs", "action": "scribe", "profile": "ino", "after": [{"from": "build", "auto": true}],
             "x": 120, "y": 240}
        ]
    }"#;

    fn members_problem(members: &str) -> String {
        problem("t", &format!(r#"{{"members": {members}}}"#))
    }

    #[test]
    fn a_team_with_members_parses_and_round_trips() {
        let team = named("t", TREE);
        validate(&team, Cli::Claude).unwrap();
        assert_eq!(team.members.len(), 3);
        let build = &team.members[0];
        assert_eq!(
            (build.id.as_str(), build.action.as_str(), build.profile.as_str()),
            ("build", "execute", "naruto")
        );
        assert_eq!((build.parent.as_deref(), build.after.as_deref()), (None, None));
        assert_eq!(build.model.as_deref(), Some("claude-sonnet-5-5"));
        let check = &team.members[1];
        assert_eq!(check.parent, None, "a parent is read as a Hand-off");
        assert_eq!(
            check.after.as_deref(),
            Some(
                &[HandOff {
                    from: "build".into(),
                    auto: false
                }][..]
            )
        );
        assert_eq!(check.effort.as_deref(), Some("low"));
        let docs = &team.members[2];
        assert_eq!((docs.x, docs.y), (Some(120), Some(240)));
        assert!(docs.hand_offs()[0].auto);

        let text = serde_json::to_string_pretty(&team).unwrap();
        assert!(!text.contains("null"), "{text}");
        assert!(!text.contains("parent") && text.contains(r#""after""#), "{text}");
        assert_eq!(named("t", &text), team);
    }

    #[test]
    fn a_members_moved_fields_and_workers_profiles_are_read_but_never_written() {
        let team = named(
            "t",
            r#"{"workers": {"cli": "claude", "profiles": {"naruto": {"model": "claude-opus-5-5"}}},
                "members": [{"id": "build", "action": "execute", "profile": "naruto",
                "instructions": "Only src/api.", "replaceRole": true, "tools": ["Read"], "skills": ["tdd"],
                "context": ["a.md"], "lessons": false, "writes": true, "worktree": "new"}]}"#,
        );
        let build = &team.members[0];
        assert!(build.replace_role && build.instructions.is_some());
        assert_eq!(
            (build.lessons, build.writes, build.worktree.as_deref()),
            (Some(false), Some(true), Some("new"))
        );
        assert_eq!(team.workers.as_ref().unwrap().profiles.len(), 1);
        let text = serde_json::to_string(&team).unwrap();
        for key in MOVED.iter().chain(&["profiles"]) {
            assert!(!text.contains(&format!("\"{key}\"")), "{key}: {text}");
        }
        assert_eq!(
            text,
            r#"{"workers":{"cli":"claude"},"members":[{"id":"build","action":"execute","profile":"naruto"}]}"#
        );
    }

    #[test]
    fn a_shipped_team_serializes_back_to_its_seed_file() {
        let hub = crate::paths::hub_dir();
        for name in ["claude-lean", "claude-opus", "kiro-lean"] {
            let text = std::fs::read_to_string(hub.join(format!("teams/{name}.json"))).unwrap();
            let team = parse(&text).unwrap();
            assert_eq!(team.members.len(), 6, "{name}");
            assert_eq!(serde_json::to_string_pretty(&team).unwrap() + "\n", text, "{name}");
        }
        assert_eq!(serde_json::to_string(&Team::default()).unwrap(), "{}");
        let before = r#"{"description":"d","workers":{"cli":"kiro"}}"#;
        assert_eq!(serde_json::to_string(&parse(before).unwrap()).unwrap(), before);
    }

    #[test]
    fn unknown_member_fields_are_ignored() {
        let team = named(
            "t",
            r#"{"members": [{"id": "a", "action": "scan", "profile": "hinata", "future": 1, "tier": {"x": 2}}]}"#,
        );
        validate(&team, Cli::Claude).unwrap();
        assert_eq!(team.members[0].id, "a");
    }

    #[test]
    fn validation_refuses_a_tree_that_cannot_run() {
        let a = |extra: &str| format!(r#"{{"id": "a", "action": "execute", "profile": "naruto"{extra}}}"#);
        let b = |extra: &str| format!(r#"{{"id": "b", "action": "scan", "profile": "hinata"{extra}}}"#);

        let twice = members_problem(&format!("[{}, {}]", a(""), a("")));
        assert!(
            twice.contains("members.a") && twice.contains("used by another"),
            "{twice}"
        );

        for bad in ["Build", "-x", "", "has space", &"x".repeat(33)] {
            let why = members_problem(&format!(
                r#"[{{"id": "{bad}", "action": "scan", "profile": "hinata"}}]"#
            ));
            assert!(why.contains("members[0]") && why.contains("id"), "{bad:?}: {why}");
        }

        let missing = members_problem(&format!(r#"[{}]"#, a(r#", "parent": "x""#)));
        assert_eq!(missing, r#"members.a: after "x" is not a Member"#);
        let after = members_problem(&format!(r#"[{}]"#, a(r#", "after": [{"from": "x"}]"#)));
        assert_eq!(after, r#"members.a: after "x" is not a Member"#);
        let none = members_problem(&format!(r#"[{}]"#, a(r#", "after": []"#)));
        assert!(none.contains("members.a") && none.contains("cannot reach"), "{none}");
        let named_so = members_problem(r#"[{"id": "orchestrator", "action": "scan", "profile": "hinata"}]"#);
        assert!(named_so.contains("Orchestrator's id"), "{named_so}");
        let doubled = members_problem(&format!(
            r#"[{}, {}]"#,
            a(""),
            b(r#", "after": [{"from": "a"}, {"from": "a", "auto": true}]"#)
        ));
        assert!(doubled.contains("two Hand-offs come from a"), "{doubled}");
        let from_top = members_problem(&format!(
            r#"[{}]"#,
            a(r#", "after": [{"from": "orchestrator", "auto": true}]"#)
        ));
        assert!(
            from_top.contains("from the Orchestrator cannot be automatic"),
            "{from_top}"
        );
        let c = |extra: &str| format!(r#"{{"id": "c", "action": "run", "profile": "lee"{extra}}}"#);
        let two_auto = members_problem(&format!(
            r#"[{}, {}, {}]"#,
            a(""),
            b(""),
            c(r#", "after": [{"from": "a", "auto": true}, {"from": "b", "auto": true}]"#)
        ));
        assert!(
            two_auto.contains("members.c") && two_auto.contains("at most one automatic"),
            "{two_auto}"
        );
        validate(
            &named(
                "t",
                &format!(
                    r#"{{"members": [{}, {}, {}]}}"#,
                    a(""),
                    b(""),
                    c(r#", "after": [{"from": "a", "auto": true}, {"from": "b"}, {"from": "orchestrator"}], "x": 40, "y": -8"#)
                ),
            ),
            Cli::Claude,
        )
        .unwrap();

        let cycle = members_problem(&format!(
            r#"[{}, {}]"#,
            a(r#", "parent": "b""#),
            b(r#", "parent": "a""#)
        ));
        assert!(cycle.contains("back to itself"), "{cycle}");
        let own = members_problem(&format!(r#"[{}]"#, a(r#", "parent": "a""#)));
        assert!(own.contains("members.a") && own.contains("back to itself"), "{own}");
        let tail = members_problem(&format!(
            r#"[{}, {}, {}]"#,
            a(r#", "parent": "b""#),
            b(r#", "parent": "a""#),
            c(r#", "parent": "a""#)
        ));
        assert!(tail.contains("back to itself"), "{tail}");
        let side = members_problem(&format!(
            r#"[{}, {}]"#,
            a(r#", "after": [{"from": "orchestrator"}, {"from": "b"}]"#),
            b(r#", "after": [{"from": "a"}]"#)
        ));
        assert!(
            side.contains("back to itself"),
            "a loop beside a line from the Orchestrator: {side}"
        );

        let deep = |n: usize| {
            let members: Vec<String> = (1..=n)
                .map(|i| match i {
                    1 => r#"{"id": "m1", "action": "scan", "profile": "hinata"}"#.to_string(),
                    _ => format!(
                        r#"{{"id": "m{i}", "action": "scan", "profile": "hinata", "parent": "m{}"}}"#,
                        i - 1
                    ),
                })
                .collect();
            format!("[{}]", members.join(","))
        };
        validate(&named("t", &format!(r#"{{"members": {}}}"#, deep(8))), Cli::Claude)
            .expect("a graph has no depth limit");

        let under_scan = members_problem(&format!(
            r#"[{}, {{"id": "v", "action": "verify", "profile": "sasuke", "parent": "b"}}]"#,
            b("")
        ));
        assert!(
            under_scan.contains("members.v") && under_scan.contains("execute"),
            "{under_scan}"
        );
        let top = members_problem(r#"[{"id": "v", "action": "verify", "profile": "sasuke"}]"#);
        assert!(top.contains("members.v") && top.contains("execute"), "{top}");
        let mixed = members_problem(&format!(
            r#"[{}, {}, {{"id": "v", "action": "verify", "profile": "sasuke", "after": [{{"from": "a"}}, {{"from": "b"}}]}}]"#,
            a(""),
            b("")
        ));
        assert!(mixed.contains("members.v") && mixed.contains("execute"), "{mixed}");
        let auto_verify = members_problem(&format!(
            r#"[{}, {{"id": "v", "action": "verify", "profile": "sasuke", "after": [{{"from": "a", "auto": true}}]}}]"#,
            a("")
        ));
        assert!(auto_verify.contains("--verify"), "{auto_verify}");

        let action = members_problem(r#"[{"id": "a", "action": "deploy", "profile": "naruto"}]"#);
        assert!(action.contains("members.a") && action.contains("deploy"), "{action}");
        validate(
            &named(
                "t",
                r#"{"members": [{"id": "a", "action": "custom", "profile": "mine"}]}"#,
            ),
            Cli::Claude,
        )
        .unwrap();

        let empty = members_problem(r#"[{"id": "a", "action": "scan", "profile": " "}]"#);
        assert!(empty.contains("members.a") && empty.contains("profile"), "{empty}");
    }

    #[test]
    fn a_members_picks_are_checked_as_the_teams_are() {
        let model = members_problem(
            r#"[{"id": "a", "action": "scan", "profile": "hinata", "cli": "kiro", "model": "anthropic/claude-sonnet-5-5"}]"#,
        );
        assert!(model.contains("members.a.model") && model.contains("kiro"), "{model}");
        let effort = members_problem(r#"[{"id": "a", "action": "scan", "profile": "hinata", "effort": "warp"}]"#);
        assert!(effort.contains("members.a.effort"), "{effort}");
        let cli = members_problem(r#"[{"id": "a", "action": "scan", "profile": "hinata", "cli": "vim"}]"#);
        assert!(cli.contains("members.a.cli"), "{cli}");

        let bare = r#"{"members": [{"id": "a", "action": "scan", "profile": "hinata", "model": "anthropic/claude-opus-5-5"}]}"#;
        validate(&named("t", bare), Cli::Claude).unwrap();
        assert!(
            validate(&named("t", bare), Cli::Kiro).is_err(),
            "the fallback cli applies"
        );
        let shared = r#"{"workers": {"cli": "claude"},
            "members": [{"id": "a", "action": "scan", "profile": "hinata", "model": "anthropic/claude-opus-5-5"}]}"#;
        validate(&named("t", shared), Cli::Kiro).unwrap();
    }

    #[test]
    fn a_team_holds_at_most_24_members() {
        let many = |n: usize| {
            let members: Vec<String> = (0..n)
                .map(|i| format!(r#"{{"id": "m{i}", "action": "scan", "profile": "hinata"}}"#))
                .collect();
            format!(r#"{{"members": [{}]}}"#, members.join(","))
        };
        validate(&named("t", &many(24)), Cli::Claude).unwrap();
        let why = problem("t", &many(25));
        assert!(why.contains("at most 24") && why.contains("25"), "{why}");
    }

    #[test]
    fn a_name_is_a_member_id_first_then_the_first_member_of_that_profile() {
        let team = named(
            "t",
            r#"{"members": [
                {"id": "first", "action": "execute", "profile": "naruto"},
                {"id": "naruto", "action": "execute", "profile": "lee"},
                {"id": "second", "action": "execute", "profile": "naruto"}
            ]}"#,
        );
        assert_eq!(team.member_for("naruto").unwrap().id, "naruto", "an id beats a profile");
        assert_eq!(team.member_for("first").unwrap().id, "first");
        assert_eq!(team.member_for("lee").unwrap().id, "naruto");
        let by_profile = named(
            "t",
            r#"{"members": [
                {"id": "x", "action": "execute", "profile": "naruto"},
                {"id": "y", "action": "execute", "profile": "naruto"}
            ]}"#,
        );
        assert_eq!(by_profile.member_for("naruto").unwrap().id, "x", "tree order");
        assert!(by_profile.member_for("sasuke").is_none());
        assert!(Team::default().member_for("naruto").is_none());
    }

    #[test]
    fn a_writers_verifier_is_its_first_verify_member_after_it() {
        let team = named(
            "t",
            r#"{"members": [
                {"id": "build", "action": "execute", "profile": "naruto"},
                {"id": "docs", "action": "scribe", "profile": "ino", "after": [{"from": "build", "auto": true}]},
                {"id": "check", "action": "verify", "profile": "sasuke", "parent": "build"},
                {"id": "recheck", "action": "verify", "profile": "sasuke", "after": [{"from": "build"}]},
                {"id": "other", "action": "execute", "profile": "naruto"},
                {"id": "test", "action": "run", "profile": "lee", "after": [{"from": "other"}, {"from": "build"}]}
            ]}"#,
        );
        validate(&team, Cli::Claude).unwrap();
        let ids = |id: &str| -> Vec<&str> { team.following(id).iter().map(|m| m.id.as_str()).collect() };
        assert_eq!(ids("build"), ["docs", "check", "recheck", "test"]);
        assert_eq!(ids("other"), ["test"]);
        assert_eq!(ids(ORCHESTRATOR), ["build", "other"]);
        let auto: Vec<&str> = team.automatic_after("build").iter().map(|m| m.id.as_str()).collect();
        assert_eq!(auto, ["docs"]);
        assert!(team.automatic_after("other").is_empty());
        assert_eq!(team.verifier_of("build").unwrap().id, "check");
        assert!(
            team.verifier_of("other").is_none(),
            "no verify Member after it means sasuke, decided by the caller"
        );
        assert!(team.verifier_of("nobody").is_none());
        assert!(Team::default().verifier_of("build").is_none());
    }

    #[test]
    fn check_profiles_names_the_member_whose_profile_is_unknown() {
        let team = named("t", TREE);
        check_profiles(&team, &["naruto", "sasuke", "ino"]).unwrap();
        check_profiles(&team, &["naruto".to_string(), "sasuke".to_string(), "ino".to_string()]).unwrap();
        let why = check_profiles(&team, &["naruto", "ino"]).unwrap_err().to_string();
        assert!(
            why.starts_with("members.check:") && why.contains("sasuke") && why.contains("naruto, ino"),
            "{why}"
        );
        check_profiles(&Team::default(), &[] as &[&str]).unwrap();
    }

    #[test]
    fn details_draw_the_tree_and_the_summary_counts_members() {
        let team = named("t", TREE);
        assert_eq!(
            details(&team),
            "workers.cli: claude\n\
             members:\n  \
             build  execute  naruto  claude-sonnet-5-5  high  after orchestrator\n  \
             check  verify  sasuke  low  after build\n  \
             docs  scribe  ino  after build (automatic)"
        );
        assert_eq!(
            summary(&team),
            "orchestrator: as set elsewhere; workers: claude, 3 Members"
        );
        let one = named(
            "t",
            r#"{"members": [{"id": "a", "action": "scan", "profile": "hinata"}]}"#,
        );
        assert_eq!(
            summary(&one),
            "orchestrator: as set elsewhere; workers: by their Profiles, 1 Member"
        );
        assert_eq!(
            summary(&named("t", "{}")),
            "orchestrator: as set elsewhere; workers: by their Profiles"
        );
        assert!(!details(&named("t", r#"{"description": "d"}"#)).contains("members"));
    }

    #[test]
    fn details_keep_a_member_whose_hand_offs_are_broken() {
        let team = named(
            "t",
            r#"{"members": [
                {"id": "a", "action": "scan", "profile": "hinata", "parent": "gone"},
                {"id": "b", "action": "scan", "profile": "hinata", "parent": "c"},
                {"id": "c", "action": "scan", "profile": "hinata", "after": []}
            ]}"#,
        );
        assert_eq!(
            details(&team),
            "members:\n  a  scan  hinata  after gone\n  b  scan  hinata  after c\n  c  scan  hinata  after nothing"
        );
    }

    /// A hub folder with naruto and sasuke as Echo's own Profiles, and no Teams.
    fn hub_with_profiles(root: &Path) -> PathBuf {
        let hub = root.join("hub");
        std::fs::create_dir_all(hub.join("profiles")).unwrap();
        for (name, writes) in [("naruto", true), ("sasuke", false)] {
            std::fs::write(
                hub.join(format!("profiles/{name}.md")),
                format!(
                    "---\nname: {name}\ndescription: {name} works\ncli: claude\nmodel: claude-sonnet-5-5\neffort: high\n\
                     tools: Bash, Read, Edit\nskills:\ncontext: AGENTS.md\nwrites: {writes}\n---\n\nYou are {name}.\n"
                ),
            )
            .unwrap();
        }
        hub
    }

    const OLD_TEAM: &str = r#"{
        "description": "from before",
        "workers": {"cli": "claude", "model": "claude-haiku-5-5",
            "profiles": {"naruto": {"model": "claude-opus-5-5", "effort": "max"}, "lee": {"effort": "low"}}},
        "members": [
            {"id": "build", "action": "execute", "profile": "naruto", "instructions": "Only touch src/api.",
             "tools": ["Read", "Grep"], "worktree": "new", "x": 40, "y": 80},
            {"id": "build-ui", "action": "execute", "profile": "naruto", "effort": "medium"},
            {"id": "check", "action": "verify", "profile": "sasuke", "parent": "build",
             "instructions": "Only run the suite.", "replaceRole": true, "lessons": false, "tools": []}
        ]
    }"#;

    #[test]
    fn a_user_teams_moved_fields_go_into_profiles_of_their_own_once() {
        let root = scratch("migrate");
        let hub = hub_with_profiles(&root);
        let (state, repo) = (root.join("state"), root.join("repo"));
        put(&state.join("teams"), "shop", OLD_TEAM);

        let team = load(&hub, &state, Some(&repo), "shop").unwrap();
        let by = |id: &str| team.members.iter().find(|m| m.id == id).unwrap();
        assert_eq!(by("build").profile, "shop-build");
        assert_eq!(by("check").profile, "shop-check");
        assert_eq!(
            by("build-ui").profile,
            "naruto",
            "nothing moved, so it keeps its Profile"
        );
        assert_eq!(
            (by("build").model.as_deref(), by("build").effort.as_deref()),
            (Some("claude-opus-5-5"), Some("max")),
            "the workers.profiles entry moved onto the Member"
        );
        assert_eq!(
            (by("build-ui").model.as_deref(), by("build-ui").effort.as_deref()),
            (Some("claude-opus-5-5"), Some("medium")),
            "a field the Member set is kept, the rest come from the entry"
        );
        assert_eq!((by("build").x, by("build").y), (Some(40), Some(80)));
        assert_eq!(by("check").after.as_ref().unwrap()[0].from, "build");

        let build = profile::load(&hub, &state, None, "shop-build").unwrap();
        assert_eq!(
            build.role,
            "You are naruto.\n\n# This Team's instructions for you\n\nOnly touch src/api."
        );
        assert_eq!(build.tools, ["Read", "Grep"]);
        assert_eq!(
            (build.worktree.as_deref(), build.writes, build.lessons),
            (Some("new"), true, true)
        );
        assert_eq!(
            (build.cli.as_deref(), build.model.as_deref()),
            (Some("claude"), Some("claude-sonnet-5-5"))
        );
        assert_eq!(build.description, "naruto works");
        let check = profile::load(&hub, &state, None, "shop-check").unwrap();
        assert_eq!(check.role, "Only run the suite.");
        assert_eq!(
            (check.lessons, check.tools.len()),
            (false, 3),
            "an empty list leaves the Profile's"
        );
        assert!(state.join("profiles/shop-build.md").exists() && !repo.join(".echo").exists());

        let text = std::fs::read_to_string(state.join("teams/shop.json")).unwrap();
        for key in MOVED.iter().chain(&["profiles", "parent"]) {
            assert!(!text.contains(&format!("\"{key}\"")), "{key}: {text}");
        }
        assert!(text.contains("\"description\": \"from before\""), "{text}");

        let profiles = std::fs::read_dir(state.join("profiles")).unwrap().count();
        let again = load(&hub, &state, Some(&repo), "shop").unwrap();
        assert_eq!(again, team, "a second read moves nothing");
        assert_eq!(std::fs::read_to_string(state.join("teams/shop.json")).unwrap(), text);
        assert_eq!(std::fs::read_dir(state.join("profiles")).unwrap().count(), profiles);
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn a_repo_teams_profiles_are_written_in_the_repo_and_names_never_clash() {
        let root = scratch("migrate-repo");
        let hub = hub_with_profiles(&root);
        let (state, repo) = (root.join("state"), root.join("repo"));
        std::fs::create_dir_all(state.join("profiles")).unwrap();
        std::fs::write(state.join("profiles/shop-build.md"), profile::blank("shop-build")).unwrap();
        put(
            &repo.join(".echo/teams"),
            "shop",
            r#"{"members": [{"id": "build", "action": "execute", "profile": "naruto", "writes": false}]}"#,
        );
        let team = load(&hub, &state, Some(&repo), "shop").unwrap();
        assert_eq!(team.members[0].profile, "shop-build-2");
        let made = profile::load(&hub, &state, Some(&repo), "shop-build-2").unwrap();
        assert!(!made.writes);
        assert!(repo.join(".echo/profiles/shop-build-2.md").exists());
        assert!(!state.join("profiles/shop-build-2.md").exists());
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn nothing_moves_while_a_members_profile_is_missing_and_a_shipped_team_is_never_written() {
        let root = scratch("migrate-missing");
        let hub = hub_with_profiles(&root);
        let state = root.join("state");
        let old = r#"{"members": [{"id": "a", "action": "execute", "profile": "naruto", "tools": ["Read"]},
            {"id": "b", "action": "execute", "profile": "gone", "tools": ["Read"]}]}"#;
        put(&state.join("teams"), "mine", old);
        put(&hub.join("teams"), "echo", old);
        list(&hub, &state, None);
        assert_eq!(std::fs::read_to_string(state.join("teams/mine.json")).unwrap(), old);
        assert_eq!(std::fs::read_to_string(hub.join("teams/echo.json")).unwrap(), old);
        assert!(!state.join("profiles").exists(), "no Profile is half moved");
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn a_moved_profiles_name_fits_32_characters_and_takes_the_next_free_number() {
        let taken = |names: &[&str]| names.iter().map(|n| n.to_string()).collect::<Vec<_>>();
        assert_eq!(unique_profile_name("shop-build", &[]), "shop-build");
        assert_eq!(
            unique_profile_name("shop-build", &taken(&["shop-build", "shop-build-2"])),
            "shop-build-3"
        );
        let long = format!("{}-{}", "t".repeat(30), "member");
        let name = unique_profile_name(&long, &[]);
        assert_eq!(name, "t".repeat(30) + "-m");
        let cut = unique_profile_name(&format!("{}-x", "t".repeat(31)), &[]);
        assert_eq!(cut, "t".repeat(31), "never ends in a dash");
        let again = unique_profile_name(&long, &[name.clone()]);
        assert!(again.len() <= 32 && again.ends_with("-2") && again != name, "{again}");
        assert!(profile::valid_name(&again));
    }
}

//! The human's settings for agents, in `settings.json` in the daemon's state (a repo may have its
//! own `.echo/settings.json` for `cli` and `model`): which CLI and model agents default to, and the
//! Orchestrator's rules where they differ from `orchestrator.md`.

use anyhow::{bail, Result};
use serde_json::{json, Map, Value};
use std::path::Path;

pub fn read(dir: &Path) -> Result<Map<String, Value>> {
    let path = dir.join("settings.json");
    let Ok(text) = std::fs::read_to_string(&path) else {
        return Ok(Map::new());
    };
    match serde_json::from_str(&text) {
        Ok(Value::Object(map)) => Ok(map),
        Ok(_) => bail!("{} is not a JSON object", path.display()),
        Err(e) => bail!("{}: {e}", path.display()),
    }
}

/// Sets each key of `patch`; a null or empty string removes it, back to its default.
pub fn update(dir: &Path, patch: &Map<String, Value>) -> Result<Map<String, Value>> {
    let mut all = read(dir)?;
    for (key, value) in patch {
        if value.is_null() || value.as_str() == Some("") {
            all.remove(key);
        } else {
            all.insert(key.clone(), value.clone());
        }
    }
    std::fs::create_dir_all(dir)?;
    std::fs::write(dir.join("settings.json"), serde_json::to_string_pretty(&all)? + "\n")?;
    Ok(all)
}

/// `forceCli` in a settings file: on makes its `cli` and `model` win over a Profile's own. None
/// when the file does not say; anything but true or false is an error, as it would silently force
/// nothing.
pub fn force_cli(settings: &Map<String, Value>, dir: &Path) -> Result<Option<bool>> {
    match settings.get("forceCli") {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Bool(force)) => Ok(Some(*force)),
        Some(_) => bail!(
            "{}: forceCli must be true or false",
            dir.join("settings.json").display()
        ),
    }
}

/// What an Orchestrator runs with when no setting names a model or effort for it.
pub const ORCHESTRATOR_MODEL: &str = "anthropic/claude-opus-5-5";
pub const ORCHESTRATOR_EFFORT: &str = "high";
/// The efforts Claude Code takes.
pub const EFFORTS: [&str; 5] = ["low", "medium", "high", "xhigh", "max"];

/// The model the human set for Orchestrators (`orchestratorModel`); none when they did not.
pub fn orchestrator_model(settings: &Map<String, Value>) -> Option<String> {
    settings
        .get("orchestratorModel")
        .and_then(Value::as_str)
        .filter(|model| !model.is_empty())
        .map(String::from)
}

/// The effort Orchestrators start with: the human's `orchestratorEffort`, else high.
pub fn orchestrator_effort(settings: &Map<String, Value>) -> String {
    settings
        .get("orchestratorEffort")
        .and_then(Value::as_str)
        .filter(|effort| EFFORTS.contains(effort))
        .unwrap_or(ORCHESTRATOR_EFFORT)
        .to_string()
}

/// The least context at which an idle Orchestrator may be renewed.
pub const MIN_ROTATE_AT: u64 = 100_000;

/// The context size (tokens) above which the daemon renews an idle Orchestrator's session: the
/// human's `orchestratorRotateAt`, never below `MIN_ROTATE_AT`; none (off) when it is absent or 0.
pub fn orchestrator_rotate_at(settings: &Map<String, Value>) -> Option<u64> {
    settings
        .get("orchestratorRotateAt")
        .and_then(Value::as_u64)
        .filter(|at| *at > 0)
        .map(|at| at.max(MIN_ROTATE_AT))
}

/// Whether an Orchestrator starts with the repo's Lessons in its prompt: the human's
/// `orchestratorLessons`, else yes. Workers get the Lessons either way.
pub fn orchestrator_lessons(settings: &Map<String, Value>) -> bool {
    settings
        .get("orchestratorLessons")
        .and_then(Value::as_bool)
        .unwrap_or(true)
}

/// How the Orchestrator works, as the human set it; the defaults are what `orchestrator.md` says.
#[derive(Debug, Clone, PartialEq)]
pub struct Rules {
    pub max_workers: u64,
    /// Wait for the human's "go" before a Task that writes code.
    pub plan_approval: bool,
    /// Have `sasuke` verify each writing Worker's commits.
    pub review: bool,
    /// Merge a verified branch without asking.
    pub merge_without_asking: bool,
}

impl Default for Rules {
    fn default() -> Self {
        Rules {
            max_workers: 4,
            plan_approval: true,
            review: true,
            merge_without_asking: false,
        }
    }
}

impl Rules {
    pub fn from(settings: &Map<String, Value>) -> Rules {
        let base = Rules::default();
        let flag = |key: &str, default: bool| settings.get(key).and_then(Value::as_bool).unwrap_or(default);
        Rules {
            max_workers: settings
                .get("maxWorkers")
                .and_then(Value::as_u64)
                .filter(|n| (1..=16).contains(n))
                .unwrap_or(base.max_workers),
            plan_approval: flag("planApproval", base.plan_approval),
            review: flag("review", base.review),
            merge_without_asking: flag("mergeWithoutAsking", base.merge_without_asking),
        }
    }

    pub fn view(&self) -> Value {
        json!({ "maxWorkers": self.max_workers, "planApproval": self.plan_approval, "review": self.review,
                "mergeWithoutAsking": self.merge_without_asking })
    }

    /// What the Orchestrator's prompt adds after `orchestrator.md`, one line per rule changed.
    pub fn overrides(&self) -> String {
        let base = Rules::default();
        let mut lines = Vec::new();
        if self.max_workers != base.max_workers {
            lines.push(format!(
                "- At most {} Workers run at once, not 4; queue the rest, and exceed {} only when the human says so for this Session.",
                self.max_workers, self.max_workers
            ));
        }
        if !self.plan_approval {
            lines.push("- Start a Task that writes code without waiting for a \"go\"; still show its one-line plan as you start it.".into());
        }
        if !self.review {
            lines.push("- Skip the sasuke verification after a writing Worker; check its Final Report against the acceptance yourself.".into());
        }
        if self.merge_without_asking {
            lines.push(
                "- Merge a verified branch into the human's branch without asking, then report it under Done.".into(),
            );
        }
        if lines.is_empty() {
            return String::new();
        }
        format!(
            "# The human's Settings\n\nThese replace the rules above where they differ.\n\n{}",
            lines.join("\n")
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn changed_rules_override_orchestrator_md_and_defaults_add_nothing() {
        assert_eq!(Rules::from(&Map::new()), Rules::default());
        assert_eq!(Rules::default().overrides(), "");
        let mut set = Map::new();
        set.insert("maxWorkers".into(), json!(6));
        set.insert("review".into(), json!(false));
        let rules = Rules::from(&set);
        let text = rules.overrides();
        assert!(text.contains("At most 6 Workers"));
        assert!(text.contains("Skip the sasuke verification"));
        assert!(!text.contains("Merge a verified branch"));
        set.insert("maxWorkers".into(), json!(99));
        assert_eq!(Rules::from(&set).max_workers, 4, "out of range falls back");
    }

    #[test]
    fn orchestrators_default_to_opus_at_high_effort_until_settings_say_otherwise() {
        let mut set = Map::new();
        assert_eq!(
            orchestrator_model(&set),
            None,
            "no setting leaves the built-in default to the daemon"
        );
        assert_eq!(ORCHESTRATOR_MODEL, "anthropic/claude-opus-5-5");
        assert_eq!(orchestrator_effort(&set), "high");
        set.insert("orchestratorModel".into(), json!("anthropic/claude-sonnet-5-5"));
        set.insert("orchestratorEffort".into(), json!("medium"));
        assert_eq!(orchestrator_model(&set).as_deref(), Some("anthropic/claude-sonnet-5-5"));
        assert_eq!(orchestrator_effort(&set), "medium");
        set.insert("orchestratorEffort".into(), json!("extreme"));
        assert_eq!(
            orchestrator_effort(&set),
            "high",
            "an effort Claude Code does not take falls back"
        );
        set.insert("orchestratorModel".into(), json!(""));
        assert_eq!(orchestrator_model(&set), None);
    }

    #[test]
    fn an_idle_orchestrator_is_renewed_only_when_the_human_sets_a_size() {
        let mut set = Map::new();
        assert_eq!(orchestrator_rotate_at(&set), None);
        set.insert("orchestratorRotateAt".into(), json!(0));
        assert_eq!(orchestrator_rotate_at(&set), None, "0 is off");
        set.insert("orchestratorRotateAt".into(), json!(150_000));
        assert_eq!(orchestrator_rotate_at(&set), Some(150_000));
        set.insert("orchestratorRotateAt".into(), json!(20_000));
        assert_eq!(
            orchestrator_rotate_at(&set),
            Some(MIN_ROTATE_AT),
            "a size below the floor is raised to it"
        );
        set.insert("orchestratorRotateAt".into(), json!("big"));
        assert_eq!(orchestrator_rotate_at(&set), None);
    }

    #[test]
    fn orchestrators_get_the_lessons_unless_the_human_turns_them_off() {
        let mut set = Map::new();
        assert!(orchestrator_lessons(&set));
        set.insert("orchestratorLessons".into(), json!(false));
        assert!(!orchestrator_lessons(&set));
        set.insert("orchestratorLessons".into(), json!("no"));
        assert!(orchestrator_lessons(&set), "not a boolean: the default stays");
    }

    #[test]
    fn update_sets_and_clears_keys() {
        let dir = std::env::temp_dir().join(format!("hub-settings-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut patch = Map::new();
        patch.insert("cli".into(), json!("codex"));
        patch.insert("maxWorkers".into(), json!(6));
        update(&dir, &patch).unwrap();
        let mut clear = Map::new();
        clear.insert("cli".into(), json!(""));
        let all = update(&dir, &clear).unwrap();
        assert_eq!(all.get("cli"), None);
        assert_eq!(read(&dir).unwrap().get("maxWorkers"), Some(&json!(6)));
    }
}

//! Actions: what a Member of a Team is for. Echo ships six as read-only `actions/<id>.json`
//! files in the echo repo; `custom` is the `action` of a Member built on a Profile of the
//! human's own, and has no file.

use std::path::Path;

use serde::{Deserialize, Serialize};

/// The shipped Action ids, in the order the palette and the Orchestrator list them.
pub const IDS: [&str; 6] = ["scan", "research", "execute", "verify", "run", "scribe"];

/// The `action` of a Member that is not one of the six.
pub const CUSTOM: &str = "custom";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Action {
    pub id: String,
    pub title: String,
    pub description: String,
    /// The Profile a Member of this Action starts from.
    pub profile: String,
    /// The sentence the Orchestrator reads to know what to send it.
    pub routing: String,
    pub writes: bool,
    /// `current` or `new`: a hint for where the Member works.
    pub worktree: String,
    /// The Action its Member must sit under; only `verify` has one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub under: Option<String>,
}

/// Whether `id` can be a Member's `action`: one of the six, or `custom`.
pub fn is_action(id: &str) -> bool {
    id == CUSTOM || IDS.contains(&id)
}

/// Echo's own Actions, in the order of `IDS`; a file that is missing or does not parse is left out.
pub fn list(hub: &Path) -> Vec<Action> {
    IDS.iter().filter_map(|id| get(hub, id)).collect()
}

/// One shipped Action; none for `custom` or an unknown id.
pub fn get(hub: &Path, id: &str) -> Option<Action> {
    if !IDS.contains(&id) {
        return None;
    }
    let text = std::fs::read_to_string(hub.join("actions").join(format!("{id}.json"))).ok()?;
    serde_json::from_str(&text).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hub() -> std::path::PathBuf {
        crate::paths::hub_dir()
    }

    #[test]
    fn every_shipped_file_parses_and_lists_in_order() {
        let ids: Vec<String> = list(&hub()).into_iter().map(|a| a.id).collect();
        assert_eq!(ids, IDS);
        for id in IDS {
            let text = std::fs::read_to_string(hub().join("actions").join(format!("{id}.json"))).unwrap();
            let action: Action = serde_json::from_str(&text).unwrap_or_else(|e| panic!("{id}: {e}"));
            assert_eq!(action.id, id);
            assert!(["current", "new"].contains(&action.worktree.as_str()), "{id}");
            assert!(!action.title.is_empty() && !action.description.is_empty() && !action.routing.is_empty());
            assert!(!text.contains('\u{2014}'), "{id}: no em dashes");
        }
    }

    #[test]
    fn the_default_profiles_are_fixed() {
        let defaults: Vec<(String, String)> = list(&hub()).into_iter().map(|a| (a.id, a.profile)).collect();
        let expected = [
            ("scan", "hinata"),
            ("research", "jiraiya"),
            ("execute", "naruto"),
            ("verify", "sasuke"),
            ("run", "lee"),
            ("scribe", "ino"),
        ];
        let expected: Vec<(String, String)> = expected.iter().map(|(a, p)| (a.to_string(), p.to_string())).collect();
        assert_eq!(defaults, expected);
    }

    #[test]
    fn every_default_profile_exists() {
        for action in list(&hub()) {
            assert!(
                hub().join("profiles").join(format!("{}.md", action.profile)).is_file(),
                "{}: profile {}",
                action.id,
                action.profile
            );
        }
    }

    #[test]
    fn only_execute_writes_and_only_verify_sits_under_another() {
        for action in list(&hub()) {
            assert_eq!(action.writes, action.id == "execute", "{}", action.id);
            let under = if action.id == "verify" { Some("execute") } else { None };
            assert_eq!(action.under.as_deref(), under, "{}", action.id);
        }
    }

    #[test]
    fn custom_is_an_action_but_has_no_file() {
        assert!(is_action("custom"));
        assert!(IDS.iter().all(|id| is_action(id)));
        assert!(get(&hub(), "custom").is_none());
    }

    #[test]
    fn an_unknown_id_is_refused() {
        for id in ["", "Scan", "deploy", "scan ", "../profiles/naruto"] {
            assert!(!is_action(id), "{id:?}");
            assert!(get(&hub(), id).is_none(), "{id:?}");
        }
    }
}

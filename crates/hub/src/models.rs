//! The models each agent CLI offers, for Settings' model pickers (decisions/features/0091), named
//! as Echo names them: `anthropic/<id>` for Claude Code, `openai/<slug>` for Codex, Kiro's own ids.
//! Codex and Kiro list theirs; Claude Code has no command for it, so its picker's models are
//! written here, with the extra ones its account cache adds.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde_json::{json, Value};

use crate::accounts;
use crate::cli::Cli;
use crate::paths;

/// The models Claude Code's own `/model` picker offers every account, best first, after Fable 5.2,
/// which it runs though no list names it yet (features/0102).
const CLAUDE: [(&str, &str); 4] = [
    ("anthropic/claude-fable-5-2", "Fable 5.2"),
    ("anthropic/claude-opus-5-5", "Opus 5.5"),
    ("anthropic/claude-sonnet-5-5", "Sonnet 5.5"),
    ("anthropic/claude-haiku-5-5", "Haiku 5.5"),
];

/// `cli`'s models as `{id, name}`, on Echo's own login while it is signed in. `program` is the
/// CLI to run (the test agent under test).
pub fn list(state: &Path, cli: Cli, program: &str) -> Result<Vec<Value>> {
    let home = accounts::home_var(cli)
        .filter(|_| accounts::own(state, cli))
        .map(|var| (var, accounts::dir(state, cli)));
    let home = home.as_ref().map(|(var, dir)| (*var, dir.as_path()));
    match cli {
        Cli::Claude => Ok(claude(&claude_config(home.map(|(_, dir)| dir)))),
        Cli::Codex => {
            let printed = printed(program, &["debug", "models"], home)?;
            Ok(codex(&printed))
        }
        Cli::Kiro => {
            let printed = printed(program, &["chat", "--list-models", "--format", "json"], home)?;
            Ok(kiro(&printed))
        }
    }
}

fn printed(program: &str, args: &[&str], home: Option<(&str, &Path)>) -> Result<Value> {
    let Some((_, out)) = accounts::run(program, args, home)? else {
        return Ok(Value::Null); // not installed: no models
    };
    serde_json::from_str(&out).with_context(|| format!("reading `{program} {}`", args.join(" ")))
}

/// Claude Code's global config: `.claude.json` in its config folder when one is set, else in home.
fn claude_config(echos: Option<&Path>) -> PathBuf {
    match echos.map(Path::to_path_buf).or_else(|| {
        std::env::var_os("CLAUDE_CONFIG_DIR")
            .filter(|dir| !dir.is_empty())
            .map(PathBuf::from)
    }) {
        Some(dir) => dir.join(".claude.json"),
        None => paths::home().join(".claude.json"),
    }
}

/// The picker's models, then the ones the account adds (`additionalModelOptionsCache`, as
/// `{"value": "claude-fable-5-1[1m]", "description": "Fable 5.1 · Most capable ..."}`).
fn claude(config: &Path) -> Vec<Value> {
    let mut out: Vec<Value> = CLAUDE
        .iter()
        .map(|(id, name)| json!({ "id": id, "name": name }))
        .collect();
    let config: Value = std::fs::read_to_string(config)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or(Value::Null);
    for option in config["additionalModelOptionsCache"].as_array().into_iter().flatten() {
        let Some(value) = option["value"].as_str().filter(|value| !value.is_empty()) else {
            continue;
        };
        let name = option["description"]
            .as_str()
            .and_then(|about| about.split(" · ").next())
            .or(option["label"].as_str())
            .unwrap_or(value);
        let id = format!("anthropic/{value}");
        if !out.iter().any(|model| model["id"] == id.as_str()) {
            out.insert(0, json!({ "id": id, "name": name }));
        }
    }
    out
}

/// `codex debug models`: the ones its own picker lists, in its order.
fn codex(printed: &Value) -> Vec<Value> {
    let mut models: Vec<&Value> = printed["models"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|model| model["visibility"] == "list" && model["slug"].is_string())
        .collect();
    models.sort_by_key(|model| model["priority"].as_i64().unwrap_or(i64::MAX));
    models
        .into_iter()
        .map(|model| {
            let slug = model["slug"].as_str().unwrap_or_default();
            json!({ "id": format!("openai/{slug}"), "name": model["display_name"].as_str().unwrap_or(slug) })
        })
        .collect()
}

/// `kiro-cli chat --list-models --format json`, in its order.
fn kiro(printed: &Value) -> Vec<Value> {
    printed["models"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|model| {
            let id = model["model_id"].as_str()?;
            Some(json!({ "id": id, "name": model["model_name"].as_str().unwrap_or(id) }))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn claude_lists_its_pickers_models_after_the_ones_the_account_adds() {
        let dir = std::env::temp_dir().join(format!("echo-models-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let config = dir.join(".claude.json");
        std::fs::write(
            &config,
            r#"{"additionalModelOptionsCache": [{"value": "claude-fable-5-1[1m]", "label": "Fable",
                "description": "Fable 5.1 · Most capable"}]}"#,
        )
        .unwrap();
        let ids: Vec<Value> = claude(&config).iter().map(|model| model["id"].clone()).collect();
        assert_eq!(
            ids,
            [
                "anthropic/claude-fable-5-1[1m]",
                "anthropic/claude-fable-5-2",
                "anthropic/claude-opus-5-5",
                "anthropic/claude-sonnet-5-5",
                "anthropic/claude-haiku-5-5"
            ]
        );
        assert_eq!(claude(&config)[0]["name"], "Fable 5.1");
        assert_eq!(claude(&dir.join("missing")).len(), 4);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn codex_lists_only_its_pickers_models_in_its_order_and_kiro_all_of_its_own() {
        let printed = json!({ "models": [
            { "slug": "gpt-5.6-luna", "display_name": "GPT-5.6-Luna", "visibility": "list", "priority": 5 },
            { "slug": "codex-auto-review", "display_name": "Codex Auto Review", "visibility": "hide", "priority": 1 },
            { "slug": "gpt-6-luna", "display_name": "GPT-6-Luna", "visibility": "list", "priority": 3 },
        ]});
        assert_eq!(
            codex(&printed),
            [
                json!({ "id": "openai/gpt-6-luna", "name": "GPT-6-Luna" }),
                json!({ "id": "openai/gpt-5.6-luna", "name": "GPT-5.6-Luna" })
            ]
        );
        let printed = json!({ "models": [
            { "model_name": "auto", "model_id": "auto" },
            { "model_name": "claude-sonnet-5.5", "model_id": "claude-sonnet-5.5" },
        ]});
        assert_eq!(kiro(&printed).len(), 2);
        assert_eq!(kiro(&printed)[1]["id"], "claude-sonnet-5.5");
        assert!(codex(&Value::Null).is_empty() && kiro(&Value::Null).is_empty());
    }
}

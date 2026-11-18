//! The skills each agent CLI can use, for Settings > Profiles' checklist (decisions/features/0099),
//! named as the CLI invokes them: Claude Code's from its config folder, its enabled plugins and the
//! repo; Codex's as `codex debug prompt-input` lists them to its model; Kiro has none.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde_json::{json, Map, Value};

use crate::accounts;
use crate::cli::Cli;

/// `cli`'s skills as `{name, description, source}`, `source` being "yours", "repo", "built-in" or
/// "plugin" (with `plugin` its name). `repo` is the checkout whose own skills count too; `program`
/// is the CLI to run (the test agent under test).
pub fn list(state: &Path, cli: Cli, program: &str, repo: Option<&Path>) -> Result<Vec<Value>> {
    match cli {
        Cli::Claude => Ok(claude(&accounts::source(cli).context("no config folder")?, repo)),
        Cli::Codex => {
            let home = accounts::home_var(cli)
                .filter(|_| accounts::own(state, cli))
                .map(|var| (var, accounts::dir(state, cli)));
            let home = home.as_ref().map(|(var, dir)| (*var, dir.as_path()));
            let dir = repo.map(Path::to_path_buf).unwrap_or_else(std::env::temp_dir);
            let Some((_, out)) = accounts::run_in(&dir, program, &["debug", "prompt-input"], home)? else {
                return Ok(Vec::new()); // not installed: no skills
            };
            let printed: Value = serde_json::from_str(&out).context("reading `codex debug prompt-input`")?;
            Ok(codex(&printed, repo))
        }
        Cli::Kiro => Ok(Vec::new()),
    }
}

/// One skill as the checklist shows it.
fn skill(name: &str, description: &str, source: &str, plugin: Option<&str>) -> Value {
    let mut out = json!({ "name": name, "description": description, "source": source });
    if let Some(plugin) = plugin {
        out["plugin"] = json!(plugin);
    }
    out
}

// MARK: Claude Code

/// Claude Code's skills: yours in `<config>/skills`, the repo's in `.claude/skills`, then each
/// enabled plugin's as `<plugin>:<skill>`. A skill only the human can invoke
/// (`disable-model-invocation: true`) is left out, since a Worker cannot use it.
fn claude(config: &Path, repo: Option<&Path>) -> Vec<Value> {
    let mut out = Vec::new();
    for (name, about) in folder(&config.join("skills")) {
        out.push(skill(&name, &about, "yours", None));
    }
    if let Some(repo) = repo {
        for (name, about) in folder(&repo.join(".claude").join("skills")) {
            out.push(skill(&name, &about, "repo", None));
        }
    }
    for (plugin, install) in plugins(config, repo) {
        let mut skills: Vec<(String, String)> = plugin_skill_dirs(&install, &plugin)
            .iter()
            .filter_map(|dir| read_skill(dir))
            .collect();
        skills.sort();
        skills.dedup_by(|a, b| a.0 == b.0);
        for (name, about) in skills {
            out.push(skill(&format!("{plugin}:{name}"), &about, "plugin", Some(&plugin)));
        }
    }
    // A name Claude Code already took from an earlier place is not listed twice.
    let mut seen = std::collections::HashSet::new();
    out.retain(|skill| seen.insert(skill["name"].as_str().unwrap_or_default().to_string()));
    out
}

/// The skills in `dir`, one per folder holding a `SKILL.md`, by name.
fn folder(dir: &Path) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| read_skill(&entry.path()))
        .collect();
    out.sort();
    out
}

/// A skill's name and one-line description from its `SKILL.md`; None when there is none, or when
/// the model may not invoke it.
fn read_skill(dir: &Path) -> Option<(String, String)> {
    let text = std::fs::read_to_string(dir.join("SKILL.md")).ok()?;
    let fields = frontmatter(&text);
    if fields
        .get("disable-model-invocation")
        .is_some_and(|value| value == "true")
    {
        return None;
    }
    let name = fields
        .get("name")
        .filter(|name| !name.is_empty())
        .cloned()
        .or_else(|| Some(dir.file_name()?.to_string_lossy().into_owned()))?;
    Some((name, fields.get("description").cloned().unwrap_or_default()))
}

/// The enabled plugins Claude Code loads here, as (name, install folder), by name: those
/// `plugins/installed_plugins.json` lists for you or for this repo, and `enabledPlugins` turns on
/// in your settings, the repo's, or the repo's local ones, the last that names one winning.
fn plugins(config: &Path, repo: Option<&Path>) -> Vec<(String, PathBuf)> {
    let mut enabled: Map<String, Value> = Map::new();
    let mut settings = vec![config.join("settings.json")];
    if let Some(repo) = repo {
        settings.push(repo.join(".claude").join("settings.json"));
        settings.push(repo.join(".claude").join("settings.local.json"));
    }
    for file in settings {
        if let Some(Value::Object(on)) = read_json(&file).map(|mut settings| settings["enabledPlugins"].take()) {
            enabled.extend(on);
        }
    }
    let installed = read_json(&config.join("plugins").join("installed_plugins.json")).unwrap_or(Value::Null);
    let mut out = Vec::new();
    for (key, installs) in installed["plugins"].as_object().into_iter().flatten() {
        if enabled.get(key) != Some(&Value::Bool(true)) {
            continue;
        }
        let here = installs.as_array().into_iter().flatten().find(|install| {
            install["scope"] == "user"
                || repo.is_some_and(|repo| {
                    install["projectPath"]
                        .as_str()
                        .is_some_and(|path| Path::new(path) == repo)
                })
        });
        let Some(path) = here.and_then(|install| install["installPath"].as_str()) else {
            continue;
        };
        let name = key.split('@').next().unwrap_or(key);
        out.push((name.to_string(), PathBuf::from(path)));
    }
    out.sort();
    out
}

/// The folders a plugin's skills are in: each folder in its `skills/` holding a `SKILL.md`, and
/// each path its manifest's `skills` names (`.claude-plugin/plugin.json`, else its entry in a
/// `marketplace.json` beside it), which is a skill's folder or a folder of them. So a plugin that
/// nests its skills (`skills/engineering/tdd`) exposes only the ones it names, not `in-progress/`.
fn plugin_skill_dirs(install: &Path, plugin: &str) -> Vec<PathBuf> {
    let manifests = install.join(".claude-plugin");
    let named = read_json(&manifests.join("plugin.json"))
        .map(|manifest| manifest["skills"].clone())
        .filter(|skills| !skills.is_null())
        .or_else(|| {
            let market = read_json(&manifests.join("marketplace.json"))?;
            let entry = market["plugins"]
                .as_array()?
                .iter()
                .find(|entry| entry["name"] == plugin)?;
            Some(entry["skills"].clone())
        })
        .unwrap_or(Value::Null);
    let named: Vec<&str> = match &named {
        Value::String(path) => vec![path.as_str()],
        Value::Array(paths) => paths.iter().filter_map(Value::as_str).collect(),
        _ => Vec::new(),
    };
    let mut roots = vec![install.join("skills")];
    roots.extend(named.iter().map(|path| install.join(path.trim_start_matches("./"))));
    let mut out = Vec::new();
    for root in roots {
        if root.join("SKILL.md").is_file() {
            out.push(root);
            continue;
        }
        for entry in std::fs::read_dir(&root).into_iter().flatten().flatten() {
            if entry.path().join("SKILL.md").is_file() {
                out.push(entry.path());
            }
        }
    }
    out
}

fn read_json(path: &Path) -> Option<Value> {
    serde_json::from_str(&std::fs::read_to_string(path).ok()?).ok()
}

/// The top-level fields of a Markdown file's YAML frontmatter, each as one line: a value folded
/// over indented lines (`>-`, `|`, or a plain or quoted value that wraps) is joined with spaces.
fn frontmatter(text: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    let mut lines = text.lines();
    if lines.next().map(str::trim_end) != Some("---") {
        return out;
    }
    let body: Vec<&str> = lines.take_while(|line| line.trim_end() != "---").collect();
    let mut at = 0;
    while at < body.len() {
        let line = body[at];
        at += 1;
        if line.starts_with([' ', '\t', '#']) {
            continue;
        }
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let mut parts = vec![value.trim().to_string()];
        while at < body.len() && (body[at].starts_with([' ', '\t']) || body[at].trim().is_empty()) {
            parts.push(body[at].trim().to_string());
            at += 1;
        }
        let first = parts[0].clone();
        if first.starts_with(['>', '|']) {
            parts.remove(0);
        }
        let joined = parts
            .iter()
            .filter(|part| !part.is_empty())
            .cloned()
            .collect::<Vec<_>>()
            .join(" ");
        out.insert(key.trim().to_string(), unquote(&joined));
    }
    out
}

/// A YAML scalar without its quotes.
fn unquote(value: &str) -> String {
    let value = value.trim();
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        return value[1..value.len() - 1].replace("\\\"", "\"").replace("\\\\", "\\");
    }
    if value.len() >= 2 && value.starts_with('\'') && value.ends_with('\'') {
        return value[1..value.len() - 1].replace("''", "'");
    }
    value.to_string()
}

// MARK: Codex

/// The skills Codex lists to its model in `codex debug prompt-input`, under "### Available
/// skills", as `- <name>: <description> (file: <root alias>/<path>)`. A plugin's are named
/// `<plugin>:<skill>`; Codex's own sit in `skills/.system`.
fn codex(printed: &Value, repo: Option<&Path>) -> Vec<Value> {
    let Some(text) = texts(printed)
        .into_iter()
        .find(|text| text.contains("### Available skills"))
    else {
        return Vec::new();
    };
    let mut roots: Vec<(String, String)> = Vec::new();
    let mut out = Vec::new();
    let mut section = "";
    for line in text.lines() {
        if line.starts_with("###") {
            section = line.trim();
            continue;
        }
        let Some(line) = line.strip_prefix("- ") else {
            continue;
        };
        match section {
            "### Skill roots" => {
                // - `r0` = `/Users/me/.agents/skills`
                let parts: Vec<&str> = line.split('`').collect();
                if parts.len() >= 4 {
                    roots.push((parts[1].to_string(), parts[3].to_string()));
                }
            }
            "### Available skills" => {
                let Some((name, rest)) = line.split_once(": ") else {
                    continue;
                };
                let (about, file) = match rest.rfind(" (file: ") {
                    Some(at) => (&rest[..at], rest[at + 8..].trim_end_matches(')')),
                    None => (rest, ""),
                };
                let file = match file.split_once('/') {
                    Some((alias, path)) => match roots.iter().find(|(root, _)| root == alias) {
                        Some((_, root)) => format!("{root}/{path}"),
                        None => file.to_string(),
                    },
                    None => file.to_string(),
                };
                let (source, plugin) = match name.split_once(':') {
                    Some((plugin, _)) => ("plugin", Some(plugin)),
                    None if file.contains("/skills/.system/") => ("built-in", None),
                    None if repo.is_some_and(|repo| within(Path::new(&file), repo)) => ("repo", None),
                    None => ("yours", None),
                };
                out.push(skill(name, about.trim(), source, plugin));
            }
            _ => {}
        }
    }
    out
}

/// `file` is inside `repo`, as given or with links such as `/tmp` resolved.
fn within(file: &Path, repo: &Path) -> bool {
    let real = |path: &Path| std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    file.starts_with(repo) || real(file).starts_with(real(repo))
}

/// Every text in the prompt input's messages.
fn texts(printed: &Value) -> Vec<&str> {
    printed
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|message| message["content"].as_array().into_iter().flatten())
        .filter_map(|part| part["text"].as_str())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("echo-skills-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write(path: &Path, text: &str) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn names(skills: &[Value]) -> Vec<&str> {
        skills.iter().map(|skill| skill["name"].as_str().unwrap()).collect()
    }

    #[test]
    fn frontmatter_folds_each_field_onto_one_line() {
        let fields = frontmatter(
            "---\nname: archify\ndescription: >-\n  Drives the GUI\n  of a window.\nlicense: MIT\nmetadata:\n  version: \"3.0\"\nquoted: \"Use \\\"it\\\" well\"\nsingle: 'it''s'\nwrapped: plain words\n  that wrap\n---\n\n# Body\nname: not this\n",
        );
        assert_eq!(fields["name"], "archify");
        assert_eq!(fields["description"], "Drives the GUI of a window.");
        assert_eq!(fields["quoted"], "Use \"it\" well");
        assert_eq!(fields["single"], "it's");
        assert_eq!(fields["wrapped"], "plain words that wrap");
        assert!(!fields.contains_key("version"));
        assert!(frontmatter("# no frontmatter\nname: x\n").is_empty());
    }

    #[test]
    fn claude_lists_yours_the_repos_and_each_enabled_plugins_as_it_names_them() {
        let dir = scratch("claude");
        let (config, repo) = (dir.join("config"), dir.join("repo"));
        write(
            &config.join("skills/graft/SKILL.md"),
            "---\nname: graft\ndescription: Find code.\n---\n",
        );
        // Named by its folder when its frontmatter has no name; one only the human may run is left out.
        write(
            &config.join("skills/optimize/SKILL.md"),
            "---\ndescription: Speed it up.\n---\n",
        );
        write(
            &config.join("skills/ship-pr/SKILL.md"),
            "---\nname: ship-pr\ndescription: x\ndisable-model-invocation: true\n---\n",
        );
        // A folder without a SKILL.md is not a skill.
        std::fs::create_dir_all(config.join("skills/learned")).unwrap();
        write(
            &repo.join(".claude/skills/release/SKILL.md"),
            "---\nname: release\ndescription: Ship it.\n---\n",
        );

        // A plugin that names nested skills in its manifest: only those, not its in-progress ones.
        let matt = dir.join("cache/matt");
        write(
            &matt.join(".claude-plugin/plugin.json"),
            r#"{"name": "matt", "skills": ["./skills/engineering/tdd", "./skills/productivity/grill-me"]}"#,
        );
        write(
            &matt.join("skills/engineering/tdd/SKILL.md"),
            "---\nname: tdd\ndescription: Red, green.\n---\n",
        );
        write(
            &matt.join("skills/productivity/grill-me/SKILL.md"),
            "---\nname: grill-me\ndescription: x\ndisable-model-invocation: true\n---\n",
        );
        write(
            &matt.join("skills/in-progress/loop/SKILL.md"),
            "---\nname: loop\ndescription: x\n---\n",
        );
        // One whose skills its marketplace entry names, under a name of the skill's own.
        let taste = dir.join("cache/taste");
        write(
            &taste.join(".claude-plugin/marketplace.json"),
            r#"{"plugins": [{"name": "taste", "skills": ["./skills/taste-skill"]}]}"#,
        );
        write(
            &taste.join("skills/taste-skill/SKILL.md"),
            "---\nname: design-taste\ndescription: Taste.\n---\n",
        );
        // Installed but off, and on but for another repo.
        let off = dir.join("cache/off");
        write(
            &off.join("skills/nope/SKILL.md"),
            "---\nname: nope\ndescription: x\n---\n",
        );
        let elsewhere = dir.join("cache/elsewhere");
        write(
            &elsewhere.join("skills/far/SKILL.md"),
            "---\nname: far\ndescription: x\n---\n",
        );
        // Turned on by the repo's own local settings.
        let local = dir.join("cache/local");
        write(
            &local.join("skills/near/SKILL.md"),
            "---\nname: near\ndescription: Near.\n---\n",
        );
        write(
            &config.join("plugins/installed_plugins.json"),
            &json!({ "version": 2, "plugins": {
                "matt@official": [{ "scope": "user", "installPath": matt }],
                "taste@taste": [{ "scope": "user", "installPath": taste }],
                "off@x": [{ "scope": "user", "installPath": off }],
                "elsewhere@x": [{ "scope": "project", "projectPath": "/somewhere/else", "installPath": elsewhere }],
                "local@x": [{ "scope": "local", "projectPath": repo, "installPath": local }],
            }})
            .to_string(),
        );
        write(
            &config.join("settings.json"),
            r#"{"enabledPlugins": {"matt@official": true, "taste@taste": true, "off@x": false, "elsewhere@x": true}}"#,
        );
        write(
            &repo.join(".claude/settings.local.json"),
            r#"{"enabledPlugins": {"local@x": true}}"#,
        );

        let listed = claude(&config, Some(&repo));
        assert_eq!(
            names(&listed),
            [
                "graft",
                "optimize",
                "release",
                "local:near",
                "matt:tdd",
                "taste:design-taste"
            ]
        );
        assert_eq!(
            listed[0],
            json!({ "name": "graft", "description": "Find code.", "source": "yours" })
        );
        assert_eq!(listed[2]["source"], "repo");
        assert_eq!(
            listed[4],
            json!({ "name": "matt:tdd", "description": "Red, green.", "source": "plugin", "plugin": "matt" })
        );
        // Without a repo, neither its skills nor the plugins it turns on.
        assert_eq!(
            names(&claude(&config, None)),
            ["graft", "optimize", "matt:tdd", "taste:design-taste"]
        );
        assert!(claude(&dir.join("missing"), None).is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn codex_lists_the_skills_it_shows_its_model_with_where_each_comes_from() {
        let text = "<skills_instructions>\n## Skills\n### Skill roots\n- `r0` = `/Users/me/.agents/skills`\n\
            - `r1` = `/Users/me/.codex/skills/.system`\n- `r2` = `/repo/.agents/skills`\n### Available skills\n\
            - imagegen: Generate images. (file: r1/imagegen/SKILL.md)\n\
            - archify: Draw diagrams (with SVG). (file: r0/archify/SKILL.md)\n\
            - release: Ship it. (file: r2/release/SKILL.md)\n\
            - pdf:pdf: Read PDFs. (file: /Users/me/.codex/plugins/cache/x/pdf/skills/pdf/SKILL.md)\n\
            ### How to use skills\n- Discovery: not a skill\n</skills_instructions>";
        let printed = json!([
            { "type": "message", "content": [{ "type": "input_text", "text": "# AGENTS.md" }] },
            { "type": "message", "content": [{ "type": "input_text", "text": text }] },
        ]);
        let listed = codex(&printed, Some(Path::new("/repo")));
        assert_eq!(names(&listed), ["imagegen", "archify", "release", "pdf:pdf"]);
        let sources: Vec<&str> = listed.iter().map(|skill| skill["source"].as_str().unwrap()).collect();
        assert_eq!(sources, ["built-in", "yours", "repo", "plugin"]);
        assert_eq!(listed[1]["description"], "Draw diagrams (with SVG).");
        assert_eq!(listed[3]["plugin"], "pdf");
        assert!(codex(&json!([]), None).is_empty());
    }
}

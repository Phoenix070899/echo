//! Drafting a Profile with an agent (features/0101): one headless call to a CLI the human picks,
//! with no tools, that returns the Profile's fields as JSON for Settings > Profiles to show unsaved.

use std::path::Path;

use anyhow::{bail, Context, Result};
use serde_json::{json, Map, Value};

use crate::cli::Cli;

/// The fields an agent may set; CLI, model and effort stay the human's.
pub const FIELDS: [&str; 6] = ["description", "tools", "skills", "context", "writes", "role"];

/// How long a draft may take before it is given up.
pub const TIMEOUT_SECS: u64 = 120;

/// What the drafting agent is shown.
pub struct Ask<'a> {
    /// What the human asked for, in their words.
    pub request: &'a str,
    /// The Profile as the form holds it now, unsaved edits included.
    pub form: &'a Map<String, Value>,
    /// The CLI the Profile runs on, whose skills it picks from.
    pub profile_cli: &'a str,
    /// The tools Echo's checklist offers.
    pub tools: &'a [String],
    /// The skills installed for `profile_cli`: name and description.
    pub skills: &'a [(String, String)],
    /// The other Profiles: name and description.
    pub others: &'a [(String, String)],
    /// The Worker Contract every Worker gets before its role.
    pub contract: &'a str,
    /// A role of Echo's own, as the shape to follow.
    pub example: &'a str,
}

const SYSTEM: &str = "You draft Agent Profiles for Echo, a Mac app that runs coding agents as Workers. \
Reply with one JSON object and nothing else: no prose, no code fence.";

/// The one message the drafting agent gets.
pub fn prompt(ask: &Ask) -> String {
    let list = |items: &[(String, String)]| -> String {
        if items.is_empty() {
            return "(none)".into();
        }
        items
            .iter()
            .map(|(name, about)| format!("- {name}: {}", one_line(about, 200)))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let form = serde_json::to_string_pretty(&Value::Object(ask.form.clone())).unwrap_or_default();
    format!(
        "{SYSTEM}

An Agent Profile is what a Worker starts as: which tools and skills it has, which files it reads first, \
whether it edits files, and its role, the Markdown that tells it what to be and how to work.

# Fields you set

- description: one line saying what the Worker is for; it is shown in lists.
- tools: some of {tools}. An empty list gives it every tool of its CLI. Give only what the role needs; \
a Worker that does not edit files gets no Edit or Write.
- skills: exact names from the installed skills below, only those that fit the role. Never invent one.
- context: files it reads before starting, relative to the repo, like CONTEXT.md.
- writes: true when it edits files, false when it only reads and reports.
- role: Markdown in the shape of the example role below: one line \"You are <Name>, <what it is>.\", \
numbered steps it follows, a paragraph on what its Final Report (sent with `echoctl done`) lists, then Rules. \
Do not repeat the Worker Contract: every Worker already gets it before its role.
- summary: one sentence for the human saying what you set or changed.

Change only what the request needs and keep every other field as it is. Use a plain hyphen, never an em dash.

# The Worker Contract (already given to every Worker)

{contract}

# Example role (hinata)

{example}

# Other Profiles (do not duplicate one)

{others}

# Skills installed for its CLI ({cli})

{skills}

# The Profile now

{form}

# The human asks

{request}

Reply with only the JSON object, with the keys description, tools, skills, context, writes, role and summary.",
        tools = ask.tools.join(", "),
        contract = ask.contract.trim(),
        example = ask.example.trim(),
        others = list(ask.others),
        cli = ask.profile_cli,
        skills = list(ask.skills),
        request = ask.request.trim(),
    )
}

/// The command line that runs `prompt` headless on `cli`, with no tools and no writes; the prompt
/// goes on stdin unless the CLI takes it as an argument (Kiro). `out` is where Codex writes its
/// last message.
pub fn args(cli: Cli, model: Option<&str>, prompt: &str, out: &Path) -> Result<Vec<String>> {
    let model = model.filter(|m| !m.is_empty()).map(|m| cli.model_arg(m)).transpose()?;
    let mut args: Vec<String> = Vec::new();
    match cli {
        Cli::Claude => {
            args.extend(
                [
                    "-p",
                    "--tools",
                    "",
                    "--strict-mcp-config",
                    "--disable-slash-commands",
                    "--no-session-persistence",
                    "--setting-sources",
                    "",
                    "--effort",
                    "medium",
                    "--system-prompt",
                    SYSTEM,
                ]
                .map(String::from),
            );
            if let Some(model) = model {
                args.extend(["--model".into(), model]);
            }
        }
        Cli::Codex => {
            args.extend(
                [
                    "exec",
                    "--sandbox",
                    "read-only",
                    "--skip-git-repo-check",
                    "--ephemeral",
                    "--color",
                    "never",
                    "-c",
                    "model_reasoning_effort=\"medium\"",
                ]
                .map(String::from),
            );
            if let Some(model) = model {
                args.extend(["-m".into(), model]);
            }
            args.extend(["-o".into(), out.display().to_string(), "-".into()]);
        }
        Cli::Kiro => {
            args.extend(["chat", "--no-interactive", "--trust-tools="].map(String::from));
            if let Some(model) = model {
                args.extend(["--model".into(), model]);
            }
            args.push(prompt.to_string());
        }
    }
    Ok(args)
}

/// Whether `cli` reads the prompt on stdin.
pub fn takes_stdin(cli: Cli) -> bool {
    cli != Cli::Kiro
}

/// The agent's reply as the form's new fields: what it left out stays as `form` has it, tools and
/// skills it names that Echo does not offer are dropped and listed, and the description is one line.
pub fn parse(text: &str, form: &Map<String, Value>, tools: &[String], skills: &[String]) -> Result<Value> {
    let reply = object(text).context("the agent did not reply with a Profile")?;
    let mut fields = Map::new();
    let mut dropped: Vec<String> = Vec::new();
    for key in FIELDS {
        let value = reply.get(key).filter(|v| !v.is_null()).or_else(|| form.get(key));
        let value = match key {
            "tools" | "skills" | "context" => {
                let names = names(value);
                let known: &[String] = match key {
                    "tools" => tools,
                    "skills" => skills,
                    _ => &[],
                };
                let (kept, gone): (Vec<String>, Vec<String>) = if key == "context" {
                    (names, Vec::new())
                } else {
                    names.into_iter().partition(|name| known.contains(name))
                };
                dropped.extend(gone);
                json!(kept)
            }
            "writes" => json!(value.and_then(Value::as_bool).unwrap_or(false)),
            "description" => json!(one_line(value.and_then(Value::as_str).unwrap_or(""), usize::MAX)),
            _ => json!(value.and_then(Value::as_str).unwrap_or("").trim_end()),
        };
        fields.insert(key.into(), value);
    }
    if fields["role"].as_str().is_none_or(|role| role.trim().is_empty()) {
        bail!("the agent returned no role");
    }
    let summary = reply.get("summary").and_then(Value::as_str).unwrap_or("").trim();
    Ok(json!({ "fields": fields, "summary": one_line(summary, usize::MAX), "dropped": dropped }))
}

/// The first JSON object in `text`, past any prose, code fence, or terminal colors around it.
fn object(text: &str) -> Option<Map<String, Value>> {
    let text = strip_ansi(text);
    let mut start = 0;
    while let Some(open) = text[start..].find('{').map(|at| at + start) {
        let mut stream = serde_json::Deserializer::from_str(&text[open..]).into_iter::<Value>();
        if let Some(Ok(Value::Object(map))) = stream.next() {
            return Some(map);
        }
        start = open + 1;
    }
    None
}

fn strip_ansi(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            if chars.peek() == Some(&'[') {
                chars.next();
                for c in chars.by_ref() {
                    if c.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
            continue;
        }
        out.push(c);
    }
    out
}

/// A list of names from an array of strings or one comma-separated string.
fn names(value: Option<&Value>) -> Vec<String> {
    let raw: Vec<String> = match value {
        Some(Value::Array(items)) => items.iter().filter_map(Value::as_str).map(String::from).collect(),
        Some(Value::String(text)) => text.split(',').map(String::from).collect(),
        _ => Vec::new(),
    };
    let mut out: Vec<String> = Vec::new();
    for name in raw.iter().map(|n| n.trim()).filter(|n| !n.is_empty()) {
        if !out.iter().any(|seen| seen == name) {
            out.push(name.to_string());
        }
    }
    out
}

/// `text` on one line, cut at `max` characters.
fn one_line(text: &str, max: usize) -> String {
    let line = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if line.chars().count() <= max {
        return line;
    }
    format!("{}…", line.chars().take(max).collect::<String>())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn form() -> Map<String, Value> {
        json!({
            "name": "sai", "description": "old", "tools": ["Read"], "skills": [], "context": ["CONTEXT.md"],
            "writes": false, "role": "You are Sai."
        })
        .as_object()
        .unwrap()
        .clone()
    }

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn a_reply_fills_the_fields_and_drops_what_echo_does_not_offer() {
        let reply = "Here it is:\n```json\n{\"description\": \"Designs\\nscreens\", \"tools\": [\"Read\", \"Edit\", \"Teleport\"], \
                     \"skills\": \"frontend-design, made-up\", \"writes\": true, \"role\": \"You are Sai, a designer.\\n\", \
                     \"summary\": \"Made it a designer.\"}\n```";
        let out = parse(reply, &form(), &names(&["Read", "Edit"]), &names(&["frontend-design"])).unwrap();
        assert_eq!(out["fields"]["description"], "Designs screens", "one line");
        assert_eq!(out["fields"]["tools"], json!(["Read", "Edit"]));
        assert_eq!(out["fields"]["skills"], json!(["frontend-design"]));
        assert_eq!(
            out["fields"]["context"],
            json!(["CONTEXT.md"]),
            "left out, the form's stays"
        );
        assert_eq!(out["fields"]["writes"], true);
        assert_eq!(out["fields"]["role"], "You are Sai, a designer.");
        assert_eq!(out["summary"], "Made it a designer.");
        assert_eq!(out["dropped"], json!(["Teleport", "made-up"]));
        assert!(out["fields"].get("name").is_none(), "only the fields an agent may set");
    }

    #[test]
    fn a_reply_without_a_profile_or_a_role_is_refused() {
        let tools = names(&["Read"]);
        assert!(parse("I cannot help with that.", &form(), &tools, &[]).is_err());
        assert!(parse("{\"role\": \"  \"}", &form(), &tools, &[]).is_err());
        let colored = "\u{1b}[32m> \u{1b}[0m{\"summary\": \"kept\"}";
        assert_eq!(
            parse(colored, &form(), &tools, &[]).unwrap()["fields"]["role"],
            "You are Sai."
        );
    }

    #[test]
    fn each_cli_drafts_headless_with_no_tools() {
        let out = Path::new("/tmp/last.txt");
        let claude = args(Cli::Claude, Some("anthropic/claude-sonnet-5-5"), "p", out).unwrap();
        assert_eq!(claude[..3], names(&["-p", "--tools", ""]));
        assert!(claude.ends_with(&names(&["--model", "claude-sonnet-5-5"])));
        let codex = args(Cli::Codex, Some("openai/gpt-test"), "p", out).unwrap();
        assert!(codex.windows(2).any(|w| w == names(&["--sandbox", "read-only"])));
        assert!(codex.ends_with(&names(&["-m", "gpt-test", "-o", "/tmp/last.txt", "-"])));
        let kiro = args(Cli::Kiro, None, "the prompt", out).unwrap();
        assert_eq!(
            kiro,
            names(&["chat", "--no-interactive", "--trust-tools=", "the prompt"])
        );
        assert!(!takes_stdin(Cli::Kiro) && takes_stdin(Cli::Codex));
        assert!(args(Cli::Claude, Some("openai/gpt-test"), "p", out).is_err());
    }

    #[test]
    fn the_prompt_carries_the_request_the_form_and_what_it_may_pick() {
        let ask = Ask {
            request: "a UX designer",
            form: &form(),
            profile_cli: "claude",
            tools: &names(&["Read", "Edit"]),
            skills: &[("frontend-design".into(), "Distinctive UI.".into())],
            others: &[("hinata".into(), "Codebase analyst.".into())],
            contract: "# Worker Contract",
            example: "You are Hinata.",
        };
        let text = prompt(&ask);
        for part in [
            "a UX designer",
            "\"name\": \"sai\"",
            "Read, Edit",
            "- frontend-design: Distinctive UI.",
            "- hinata: Codebase analyst.",
            "# Worker Contract",
            "You are Hinata.",
        ] {
            assert!(text.contains(part), "missing {part:?}");
        }
    }
}

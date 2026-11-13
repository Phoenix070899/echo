//! Agent CLIs: the one place that knows how each runs. The daemon says what an agent starts with
//! (a `Start`); a `Cli` turns that into its own program and flags, and says whether a session can
//! be resumed. Which CLI and model an agent gets is picked here too, from the levels in `pick`.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{bail, Context, Result};

use crate::{paths, screen};

/// An agent CLI Echo can run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cli {
    Claude,
    /// OpenAI's Codex CLI.
    Codex,
    /// AWS's Kiro CLI (`kiro-cli`), on its V3 harness.
    Kiro,
}

/// Names Echo knows but cannot run yet, so the error says so instead of "unknown".
const COMING: &[&str] = &["opencode", "gemini"];

impl Cli {
    pub fn parse(name: &str) -> Result<Cli> {
        match name {
            "claude" => Ok(Cli::Claude),
            "codex" => Ok(Cli::Codex),
            "kiro" => Ok(Cli::Kiro),
            other if COMING.contains(&other) => {
                bail!("cli {other:?} is not supported yet (only claude, codex and kiro)")
            }
            other => bail!("unknown cli {other:?}; Echo runs claude, codex and kiro"),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Cli::Claude => "claude",
            Cli::Codex => "codex",
            Cli::Kiro => "kiro",
        }
    }

    /// The binary that runs it; `name` is what Echo stores and shows.
    pub fn program(self) -> &'static str {
        match self {
            Cli::Kiro => "kiro-cli",
            other => other.name(),
        }
    }

    /// The CLI's own name for a `provider/model`; a bare name is passed as it is.
    pub fn model_arg(self, model: &str) -> Result<String> {
        match (self, model.split_once('/')) {
            (Cli::Claude, None) => Ok(model.to_string()),
            (Cli::Claude, Some(("anthropic", name))) => Ok(name.to_string()),
            (Cli::Claude, Some((provider, _))) => {
                bail!("claude runs only Anthropic models, not {provider}'s {model:?}; pick another cli for it")
            }
            (Cli::Codex, None) => Ok(model.to_string()),
            (Cli::Codex, Some(("openai", name))) => Ok(name.to_string()),
            (Cli::Codex, Some((provider, _))) => {
                bail!("codex runs OpenAI models here, not {provider}'s {model:?}; pick another cli for it")
            }
            (Cli::Kiro, None) => Ok(model.to_string()),
            (Cli::Kiro, Some(("kiro", name))) => Ok(name.to_string()),
            (Cli::Kiro, Some((provider, _))) => {
                bail!("kiro runs its own model ids here, not {provider}'s {model:?}; pick another cli for it")
            }
        }
    }

    /// Whether a session with this id has started, so it can be resumed instead of begun again.
    pub fn has_session(self, session_id: &str) -> bool {
        match self {
            Cli::Claude => paths::transcript_exists(session_id),
            Cli::Codex => codex_session_exists(session_id),
            Cli::Kiro => kiro_session_exists(&kiro_home(), session_id),
        }
    }

    /// What its screen shows now: a prompt, a turn under way, or its input box.
    pub fn look(self, screen: &str) -> screen::Look {
        match self {
            Cli::Claude => screen::look(screen),
            Cli::Codex => screen::codex_look(screen),
            // Placeholder until the screen reader for Kiro lands.
            Cli::Kiro => screen::Look::Idle,
        }
    }

    /// The lines of the permission prompt on screen, for the human to decide on.
    pub fn prompt_lines(self, screen: &str) -> String {
        match self {
            Cli::Claude => screen::prompt_lines(screen),
            Cli::Codex => screen::codex_prompt_lines(screen),
            Cli::Kiro => String::new(),
        }
    }

    /// Whether the screen shows a turn that finished at the input box.
    pub fn turn_ended(self, screen: &str) -> bool {
        match self {
            Cli::Claude => screen::turn_ended(screen),
            Cli::Codex => screen::codex_turn_ended(screen),
            Cli::Kiro => false,
        }
    }

    /// The keys that answer its folder-trust dialog with "trust".
    pub fn trust_keys(self) -> &'static [&'static [u8]] {
        match self {
            // Claude's dialog starts on "No, exit".
            Cli::Claude => &[b"\x1b[B", b"\r"],
            Cli::Codex => &[b"\r"],
            // Its dialog starts on "Trust, continue"; `--trust-workspace` normally skips it.
            Cli::Kiro => &[b"\r"],
        }
    }

    /// The arguments after `program()` for `start`.
    pub fn args(self, hub: &Path, start: &Start) -> Result<Vec<String>> {
        match self {
            Cli::Claude => claude(hub, start),
            Cli::Codex => codex(start),
            Cli::Kiro => kiro(&kiro_home(), start),
        }
    }
}

/// What an agent starts with, whatever its CLI.
#[derive(Debug, Default)]
pub struct Start {
    /// The session's title in the CLI's own session list.
    pub title: String,
    /// Put after the CLI's own system prompt; empty adds nothing.
    pub prompt: String,
    /// Folders beyond its working directory that it may read and edit.
    pub dirs: Vec<PathBuf>,
    /// Plugin folders (skills, hooks, views) to load.
    pub plugins: Vec<PathBuf>,
    pub model: Option<String>,
    pub effort: Option<String>,
    /// Only these tools; empty means the CLI's own set.
    pub tools: Vec<String>,
    /// A Worker: nobody watches it, so it runs unprompted, reports prompts, and never asks the
    /// human directly.
    pub worker: bool,
    /// The folder the agent works in; Kiro's permission rules name it.
    pub cwd: Option<PathBuf>,
    pub session_id: String,
    pub resume: bool,
    /// The first message: a Task, a request, or what to do after a restart.
    pub first: Option<String>,
    /// The human's own extra arguments, passed through.
    pub extra: Vec<String>,
}

fn claude(hub: &Path, start: &Start) -> Result<Vec<String>> {
    let mut args = vec!["-n".to_string(), start.title.clone()];
    if let Some(model) = &start.model {
        if !start.extra.iter().any(|arg| arg == "--model") {
            args.extend(["--model".into(), Cli::Claude.model_arg(model)?]);
        }
    }
    if start.worker {
        args.extend([
            "--permission-mode".into(),
            "auto".into(),
            "--settings".into(),
            hub.join("settings").join("worker.json").display().to_string(),
            "--disallowedTools".into(),
            "AskUserQuestion".into(),
        ]);
    }
    for plugin in &start.plugins {
        args.extend(["--plugin-dir".into(), plugin.display().to_string()]);
    }
    for dir in &start.dirs {
        args.extend(["--add-dir".into(), dir.display().to_string()]);
    }
    if let Some(effort) = &start.effort {
        args.extend(["--effort".into(), effort.clone()]);
    }
    if !start.tools.is_empty() {
        // Without ToolSearch every MCP tool loads in full instead of on demand: about 85k tokens
        // of connectors no Worker uses, re-read on every turn.
        let mut tools = start.tools.clone();
        if !tools.iter().any(|tool| tool == "ToolSearch") {
            tools.push("ToolSearch".into());
        }
        args.extend(["--tools".into(), tools.join(",")]);
    }
    if !start.prompt.is_empty() {
        args.extend(["--append-system-prompt".into(), start.prompt.clone()]);
    }
    args.extend(start.extra.iter().cloned());
    args.extend([
        if start.resume { "--resume" } else { "--session-id" }.into(),
        start.session_id.clone(),
    ]);
    // After `--`, so a first message starting with `-` is not taken for an option.
    if let Some(first) = &start.first {
        args.extend(["--".into(), first.clone()]);
    }
    Ok(args)
}

/// Codex keeps each session as `~/.codex/sessions/<y>/<m>/<d>/rollout-<time>-<id>.jsonl`.
fn codex_session_exists(session_id: &str) -> bool {
    fn find(dir: &Path, end: &str, depth: u8) -> bool {
        let Ok(read) = std::fs::read_dir(dir) else { return false };
        read.flatten().any(|entry| {
            let path = entry.path();
            match depth {
                0 => path.file_name().is_some_and(|n| n.to_string_lossy().ends_with(end)),
                _ => path.is_dir() && find(&path, end, depth - 1),
            }
        })
    }
    !session_id.is_empty()
        && find(
            &paths::home().join(".codex").join("sessions"),
            &format!("-{session_id}.jsonl"),
            3,
        )
}

/// A TOML basic string, for a `-c key=value` whose value must not be read as anything else.
fn toml_string(text: &str) -> String {
    let mut out = String::from("\"");
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c if c.is_control() => out.push_str(&format!("\\u{:04X}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Codex has no session id to set up front and no per-run settings file: Echo passes its hooks
/// inline and learns the session id from the SessionStart hook (`echoctl notify`).
fn codex(start: &Start) -> Result<Vec<String>> {
    let mut args = Vec::new();
    if start.resume {
        args.extend(["resume".to_string(), start.session_id.clone()]);
    }
    if let Some(model) = &start.model {
        if !start.extra.iter().any(|arg| arg == "-m" || arg == "--model") {
            args.extend(["-m".into(), Cli::Codex.model_arg(model)?]);
        }
    }
    let hook =
        |event: &str| format!("hooks.{event}=[{{hooks=[{{type=\"command\",command=\"echoctl notify\",timeout=10}}]}}]");
    args.extend([
        "--dangerously-bypass-hook-trust".into(),
        "-c".into(),
        hook("SessionStart"),
    ]);
    if start.worker {
        // Unwatched: work in the checkout with the network, and ask (a blocker) only to leave it.
        args.extend([
            "-a".into(),
            "on-request".into(),
            "-s".into(),
            "workspace-write".into(),
            "-c".into(),
            "sandbox_workspace_write.network_access=true".into(),
            // Not PermissionRequest: it fires before Codex's own reviewer decides, so most never
            // reach the screen. Prompts are read from the screen, as for claude.
            "-c".into(),
            hook("Stop"),
        ]);
    }
    for dir in &start.dirs {
        args.extend(["--add-dir".into(), dir.display().to_string()]);
    }
    if let Some(effort) = &start.effort {
        args.extend(["-c".into(), format!("model_reasoning_effort={}", toml_string(effort))]);
    }
    if !start.prompt.is_empty() {
        args.extend([
            "-c".into(),
            format!("developer_instructions={}", toml_string(&start.prompt)),
        ]);
    }
    args.extend(start.extra.iter().cloned());
    if let Some(first) = &start.first {
        args.extend(["--".into(), first.clone()]);
    }
    Ok(args)
}

/// Kiro's own folder (sign-in, sessions, agents): `$KIRO_HOME`, else `~/.kiro`.
fn kiro_home() -> PathBuf {
    std::env::var_os("KIRO_HOME")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| paths::home().join(".kiro"))
}

/// Kiro keeps each session as `<home>/sessions/<workspace hash>/sess_<uuid>/`; a hook reports the
/// id with its `sess_` prefix and `--resume-id` takes it with or without, so either spelling counts.
fn kiro_session_exists(home: &Path, session_id: &str) -> bool {
    let plain_id = |c: char| c.is_ascii_alphanumeric() || c == '-' || c == '_';
    if session_id.is_empty() || !session_id.chars().all(plain_id) {
        return false;
    }
    let bare = session_id.strip_prefix("sess_").unwrap_or(session_id);
    let names = [bare.to_string(), format!("sess_{bare}")];
    let Ok(buckets) = std::fs::read_dir(home.join("sessions")) else {
        return false;
    };
    buckets
        .flatten()
        .any(|bucket| names.iter().any(|name| bucket.path().join(name).is_dir()))
}

/// FNV-1a, 64 bit: the same text hashes the same on every run and build, which `DefaultHasher`
/// does not promise, and the agent file's name must not change between two starts.
fn fnv1a(text: &str) -> u64 {
    text.bytes().fold(0xcbf2_9ce4_8422_2325, |hash, byte| {
        (hash ^ u64::from(byte)).wrapping_mul(0x0100_0000_01b3)
    })
}

/// A string as a YAML double-quoted scalar (JSON strings are one).
fn yaml_string(text: &str) -> String {
    serde_json::Value::String(text.to_string()).to_string()
}

/// Kiro's tool names for Claude's (`Start::tools` is a list of Claude's); the others have no
/// Kiro counterpart and are left out. Nothing left means Kiro's whole set.
fn kiro_tools(tools: &[String]) -> Vec<&'static str> {
    let mut out: Vec<&'static str> = Vec::new();
    for tool in tools {
        let mapped = match tool.as_str() {
            "Bash" => "shell",
            "Read" => "read",
            "Edit" | "Write" | "NotebookEdit" => "write",
            "WebFetch" | "WebSearch" => "web",
            _ => continue,
        };
        if !out.contains(&mapped) {
            out.push(mapped);
        }
    }
    if out.is_empty() {
        out.push("*");
    }
    out
}

/// One permission rule of a Kiro agent file.
struct KiroRule {
    capability: &'static str,
    globs: Vec<String>,
    effect: &'static str,
}

impl KiroRule {
    fn allow(capability: &'static str, globs: Vec<String>) -> KiroRule {
        KiroRule {
            capability,
            globs,
            effect: "allow",
        }
    }
}

/// Commands a Worker may never run, the same ones `settings/worker.json` asks about for Claude.
const KIRO_DENIED_COMMANDS: &[&str] = &[
    "rm -rf *",
    "rm -fr *",
    "git reset --hard*",
    "sudo *",
    "curl * | sh",
    "curl * | bash",
    "wget * | sh",
    "wget * | bash",
];

/// What the agent may do without asking. A Worker works unwatched: it reads anywhere, writes in
/// its checkout and the folders Echo gives it, and runs shell commands except the destructive
/// ones (a shell rule matches the command text, never a folder, so the deny list is its guard;
/// `fs_read` anywhere also stops the second prompt a shell command raises for its folder).
/// Anyone else is only spared the prompts for the folders Echo gave it; the rest reaches the human.
fn kiro_rules(start: &Start) -> Vec<KiroRule> {
    let folders =
        |roots: &[&Path]| -> Vec<String> { roots.iter().map(|root| root.join("**").display().to_string()).collect() };
    let mut roots: Vec<&Path> = start.cwd.iter().map(PathBuf::as_path).collect();
    roots.extend(start.dirs.iter().map(PathBuf::as_path));
    if !start.worker {
        let dirs: Vec<&Path> = start.dirs.iter().map(PathBuf::as_path).collect();
        if dirs.is_empty() {
            return Vec::new();
        }
        return vec![
            KiroRule::allow("fs_read", folders(&dirs)),
            KiroRule::allow("fs_write", folders(&dirs)),
        ];
    }
    let mut rules = vec![KiroRule::allow("fs_read", vec!["**".into()])];
    if !roots.is_empty() {
        rules.push(KiroRule::allow("fs_write", folders(&roots)));
    }
    rules.push(KiroRule::allow("shell", vec!["*".into(), "**".into()]));
    rules.push(KiroRule {
        capability: "shell",
        globs: KIRO_DENIED_COMMANDS.iter().map(|c| c.to_string()).collect(),
        effect: "deny",
    });
    rules
}

/// The agent file for `start` under `name`: Markdown, its front matter holding everything but the
/// prompt, which is the body.
fn kiro_agent_text(start: &Start, name: &str) -> Result<String> {
    let kind = match (start.worker, start.prompt.is_empty()) {
        (true, _) => "worker",
        (false, false) => "orchestrator",
        (false, true) => "session",
    };
    let list = |items: Vec<String>| format!("[{}]", items.join(", "));
    let mut text = format!("---\nname: {name}\ndescription: Echo {kind}\n");
    if let Some(model) = &start.model {
        text.push_str(&format!("model: {}\n", yaml_string(&Cli::Kiro.model_arg(model)?)));
    }
    text.push_str(&format!(
        "tools: {}\n",
        list(kiro_tools(&start.tools).iter().map(|t| yaml_string(t)).collect())
    ));
    let rules = kiro_rules(start);
    if !rules.is_empty() {
        text.push_str("permissions:\n  rules:\n");
        for rule in rules {
            text.push_str(&format!(
                "    - capability: {}\n      match: {}\n      effect: {}\n",
                rule.capability,
                list(rule.globs.iter().map(|g| yaml_string(g)).collect()),
                rule.effect
            ));
        }
    }
    // Both run `echoctl notify`, which finds the agent from the HUB_WORKER and HUB_AGENT that
    // Kiro's hooks inherit. SessionStart fires on the first prompt and carries the session id.
    let mut hooks = vec![("echo-session-start", "SessionStart")];
    if start.worker {
        hooks.push(("echo-stop", "Stop"));
    }
    text.push_str("hooks:\n");
    for (hook, trigger) in hooks {
        text.push_str(&format!(
            "  - name: {hook}\n    trigger: {trigger}\n    action:\n      type: command\n      command: \"echoctl notify\"\n"
        ));
    }
    text.push_str("---\n\n");
    text.push_str(&start.prompt);
    if !start.prompt.ends_with('\n') {
        text.push('\n');
    }
    Ok(text)
}

/// Writes the agent file for `start` into `<home>/agents/` unless it is there, and returns the
/// agent's name. The name is `echo-` and a hash of the file's content, so a file is never
/// rewritten with other content and two starts at once cannot read each other's prompt.
fn write_kiro_agent(home: &Path, start: &Start) -> Result<String> {
    static TEMPS: AtomicU64 = AtomicU64::new(0);
    let hash = fnv1a(&kiro_agent_text(start, "echo-0")?);
    let name = format!("echo-{hash:016x}");
    let dir = home.join("agents");
    let path = dir.join(format!("{name}.md"));
    if path.exists() {
        return Ok(name);
    }
    std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
    let temp = dir.join(format!(
        ".{name}.{}.{}.tmp",
        std::process::id(),
        TEMPS.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::write(&temp, kiro_agent_text(start, &name)?).with_context(|| format!("writing {}", temp.display()))?;
    std::fs::rename(&temp, &path).map_err(|e| {
        let _ = std::fs::remove_file(&temp);
        anyhow::anyhow!("writing {}: {e}", path.display())
    })?;
    Ok(name)
}

/// Kiro has no flag for a system prompt, folders or a session id: the prompt, tools, rules and
/// hooks go in an agent file (`write_kiro_agent`), and the session id comes from its SessionStart
/// hook (`echoctl notify`). `--trust-workspace` answers the folder-trust dialog.
fn kiro(home: &Path, start: &Start) -> Result<Vec<String>> {
    let agent = write_kiro_agent(home, start)?;
    let mut args: Vec<String> = ["chat", "--v3", "--agent"].map(String::from).into();
    args.push(agent);
    let given = |flag: &str| start.extra.iter().any(|arg| arg == flag);
    if let Some(model) = &start.model {
        if !given("--model") {
            args.extend(["--model".into(), Cli::Kiro.model_arg(model)?]);
        }
    }
    if let Some(effort) = &start.effort {
        if !given("--effort") {
            args.extend(["--effort".into(), effort.clone()]);
        }
    }
    args.push("--trust-workspace".into());
    if start.resume {
        args.extend(["--resume-id".into(), start.session_id.clone()]);
    }
    args.extend(start.extra.iter().cloned());
    if let Some(first) = &start.first {
        // The message goes last as the positional INPUT. `--` cannot guard it: headless it works,
        // but in the interactive TUI the message is lost. Unguarded, a leading `-` is read as an
        // option (`-d <id>` deletes a session). The spike proved only that a non-dash start is
        // safe, so a message starting with `-` gets a plain-word prefix that survives trimming.
        args.push(if first.starts_with('-') {
            format!("Message: {first}")
        } else {
            first.clone()
        });
    }
    Ok(args)
}

/// A CLI and a model, as one level names them; either may be left to the level below.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Choice {
    pub cli: Option<String>,
    pub model: Option<String>,
}

impl Choice {
    /// `settings.json` in a folder: `{"cli": "claude", "model": "anthropic/claude-sonnet-5-5"}`.
    pub fn read(dir: &Path) -> Result<Choice> {
        let value = crate::settings::read(dir)?;
        let field = |key: &str| {
            value
                .get(key)
                .and_then(|v| v.as_str())
                .map(String::from)
                .filter(|v| !v.is_empty())
        };
        Ok(Choice {
            cli: field("cli"),
            model: field("model"),
        })
    }
}

/// The CLI and model an agent runs with: the choice made at its start, else its Profile's, else
/// the repo's (`.echo/settings.json`), else the human's (`settings.json` in the state), else
/// claude with its own default model.
pub fn pick(state: &Path, repo: Option<&Path>, levels: &[&Choice]) -> Result<(Cli, Option<String>)> {
    let mut all = vec![Choice::read(state)?];
    if let Some(repo) = repo {
        all.push(Choice::read(&repo.join(".echo"))?);
    }
    all.extend(levels.iter().map(|c| (*c).clone()));
    let cli = all.iter().rev().find_map(|c| c.cli.clone());
    let model = all.iter().rev().find_map(|c| c.model.clone());
    let cli = Cli::parse(cli.as_deref().unwrap_or("claude"))?;
    if let Some(model) = &model {
        cli.model_arg(model)?;
    }
    Ok((cli, model))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("hub-cli-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn claude_takes_anthropic_models_by_either_name() {
        assert_eq!(
            Cli::Claude.model_arg("anthropic/claude-opus-5-5").unwrap(),
            "claude-opus-5-5"
        );
        assert_eq!(Cli::Claude.model_arg("claude-opus-5-5").unwrap(), "claude-opus-5-5");
        assert!(Cli::Claude
            .model_arg("openai/gpt-5")
            .unwrap_err()
            .to_string()
            .contains("only Anthropic"));
        assert!(Cli::parse("opencode")
            .unwrap_err()
            .to_string()
            .contains("not supported yet"));
        assert!(Cli::parse("vim").unwrap_err().to_string().contains("unknown cli"));
    }

    #[test]
    fn each_level_overrides_the_one_before() {
        let state = scratch("state");
        let repo = scratch("repo");
        assert_eq!(pick(&state, Some(&repo), &[]).unwrap(), (Cli::Claude, None));
        std::fs::write(
            state.join("settings.json"),
            r#"{"model": "anthropic/claude-haiku-5-5"}"#,
        )
        .unwrap();
        std::fs::create_dir_all(repo.join(".echo")).unwrap();
        std::fs::write(repo.join(".echo/settings.json"), r#"{"model": "claude-sonnet-5-5"}"#).unwrap();
        assert_eq!(
            pick(&state, None, &[]).unwrap().1.as_deref(),
            Some("anthropic/claude-haiku-5-5")
        );
        assert_eq!(
            pick(&state, Some(&repo), &[]).unwrap().1.as_deref(),
            Some("claude-sonnet-5-5")
        );
        let profile = Choice {
            cli: Some("claude".into()),
            model: Some("claude-opus-5-5".into()),
        };
        let start = Choice {
            cli: None,
            model: Some("anthropic/claude-fable-5-1".into()),
        };
        assert_eq!(
            pick(&state, Some(&repo), &[&profile]).unwrap().1.as_deref(),
            Some("claude-opus-5-5")
        );
        assert_eq!(
            pick(&state, Some(&repo), &[&profile, &start]).unwrap().1.as_deref(),
            Some("anthropic/claude-fable-5-1")
        );
        let wrong = Choice {
            cli: None,
            model: Some("openai/gpt-5".into()),
        };
        assert!(
            pick(&state, Some(&repo), &[&wrong]).is_err(),
            "a model the cli cannot run fails at start"
        );
    }

    #[test]
    fn an_orchestrator_starts_with_its_own_model_and_effort_and_keeps_them_on_resume() {
        let hub = Path::new("/echo");
        let start = Start {
            title: "echo: repo".into(),
            model: Some("anthropic/claude-opus-5-5".into()),
            effort: Some("high".into()),
            session_id: "s1".into(),
            ..Start::default()
        };
        let args = Cli::Claude.args(hub, &start).unwrap().join(" ");
        assert!(args.contains("--model claude-opus-5-5"), "{args}");
        assert!(args.contains("--effort high"), "{args}");
        let resumed = Cli::Claude
            .args(hub, &Start { resume: true, ..start })
            .unwrap()
            .join(" ");
        assert!(
            resumed.contains("--effort high") && resumed.contains("--model claude-opus-5-5"),
            "{resumed}"
        );
    }

    #[test]
    fn a_worker_runs_unprompted_with_its_hooks_and_resumes_by_id() {
        let hub = Path::new("/echo");
        let start = Start {
            title: "lee: run tests".into(),
            prompt: "contract".into(),
            dirs: vec![PathBuf::from("/echo"), PathBuf::from("/state/memory")],
            model: Some("anthropic/claude-haiku-5-5".into()),
            effort: Some("low".into()),
            tools: vec!["Bash".into(), "Read".into()],
            worker: true,
            session_id: "s1".into(),
            first: Some("-run the tests".into()),
            ..Start::default()
        };
        let args = Cli::Claude.args(hub, &start).unwrap().join(" ");
        assert_eq!(
            args,
            "-n lee: run tests --model claude-haiku-5-5 --permission-mode auto --settings /echo/settings/worker.json \
             --disallowedTools AskUserQuestion --add-dir /echo --add-dir /state/memory --effort low --tools Bash,Read,ToolSearch \
             --append-system-prompt contract --session-id s1 -- -run the tests"
        );
        let resumed = Start {
            resume: true,
            first: None,
            extra: vec!["--model".into(), "x".into()],
            ..start
        };
        let args = Cli::Claude.args(hub, &resumed).unwrap();
        assert_eq!(
            args.iter().filter(|a| *a == "--model").count(),
            1,
            "the human's --model wins"
        );
        assert!(args.ends_with(&["--resume".to_string(), "s1".to_string()]));
    }

    #[test]
    fn codex_gets_its_prompt_and_hooks_inline_and_resumes_by_its_own_id() {
        let start = Start {
            title: "lee: run tests".into(),
            prompt: "Say \"done\"\nthen stop".into(),
            dirs: vec![PathBuf::from("/echo")],
            model: Some("openai/gpt-5.6-terra".into()),
            effort: Some("low".into()),
            worker: true,
            session_id: "s1".into(),
            first: Some("run the tests".into()),
            ..Start::default()
        };
        let args = Cli::Codex.args(Path::new("/echo"), &start).unwrap();
        let has = |a: &str| args.iter().any(|arg| arg == a);
        assert_eq!(args[..2], ["-m", "gpt-5.6-terra"]);
        assert!(has("--dangerously-bypass-hook-trust") && has("workspace-write") && has("on-request"));
        assert!(has(
            r#"hooks.SessionStart=[{hooks=[{type="command",command="echoctl notify",timeout=10}]}]"#
        ));
        assert!(has(
            r#"hooks.Stop=[{hooks=[{type="command",command="echoctl notify",timeout=10}]}]"#
        ));
        assert!(
            !args.iter().any(|a| a.contains("PermissionRequest")),
            "prompts are read from the screen"
        );
        assert!(has(r#"developer_instructions="Say \"done\"\nthen stop""#));
        assert!(has(r#"model_reasoning_effort="low""#));
        assert!(args.ends_with(&["--".to_string(), "run the tests".to_string()]));
        let resumed = Cli::Codex
            .args(
                Path::new("/echo"),
                &Start {
                    resume: true,
                    first: None,
                    ..start
                },
            )
            .unwrap();
        assert_eq!(resumed[..2], ["resume", "s1"]);
    }

    fn kiro_worker() -> Start {
        Start {
            prompt: "Contract: report with \"echoctl done\"\nthen stop".into(),
            dirs: vec![PathBuf::from("/echo"), PathBuf::from("/state/memory/")],
            cwd: Some(PathBuf::from("/work/checkout")),
            model: Some("kiro/claude-haiku-5.5".into()),
            effort: Some("low".into()),
            tools: vec![
                "Bash".into(),
                "Read".into(),
                "Edit".into(),
                "Write".into(),
                "ToolSearch".into(),
                "Task".into(),
            ],
            worker: true,
            session_id: "sess_1".into(),
            first: Some("run the tests".into()),
            ..Start::default()
        }
    }

    fn agent_file(home: &Path, args: &[String]) -> String {
        let at = args.iter().position(|a| a == "--agent").unwrap();
        std::fs::read_to_string(home.join("agents").join(format!("{}.md", args[at + 1]))).unwrap()
    }

    #[test]
    fn kiro_is_named_kiro_and_run_as_kiro_cli() {
        assert_eq!(Cli::parse("kiro").unwrap(), Cli::Kiro);
        assert_eq!(Cli::Kiro.name(), "kiro");
        assert_eq!(Cli::Kiro.program(), "kiro-cli");
        assert_eq!(Cli::Codex.program(), "codex");
        let err = Cli::parse("vim").unwrap_err().to_string();
        assert!(err.contains("claude, codex and kiro"), "{err}");
        let err = Cli::parse("gemini").unwrap_err().to_string();
        assert!(err.contains("claude, codex and kiro"), "{err}");
    }

    #[test]
    fn kiro_takes_its_own_model_ids_bare_or_prefixed_and_refuses_other_providers() {
        assert_eq!(Cli::Kiro.model_arg("claude-sonnet-5.5").unwrap(), "claude-sonnet-5.5");
        assert_eq!(
            Cli::Kiro.model_arg("kiro/claude-sonnet-5.5").unwrap(),
            "claude-sonnet-5.5"
        );
        let err = Cli::Kiro.model_arg("openai/gpt-5").unwrap_err().to_string();
        assert!(
            err.contains("openai") && err.contains("\"openai/gpt-5\"") && err.contains("pick another cli"),
            "{err}"
        );
    }

    #[test]
    fn a_kiro_session_exists_under_either_spelling_of_its_id() {
        let home = scratch("kiro-sessions");
        let bucket = home.join("sessions").join("a44897a43362370a");
        std::fs::create_dir_all(bucket.join("sess_6a2fda8e-84a4")).unwrap();
        std::fs::create_dir_all(home.join("sessions").join("cli")).unwrap();
        std::fs::write(home.join("sessions/cli/sess_old.history"), "").unwrap();
        assert!(kiro_session_exists(&home, "sess_6a2fda8e-84a4"));
        assert!(kiro_session_exists(&home, "6a2fda8e-84a4"));
        assert!(!kiro_session_exists(&home, "sess_other"));
        assert!(!kiro_session_exists(&home, "sess_old.history"));
        assert!(!kiro_session_exists(&home, ""));
        assert!(!kiro_session_exists(&home, "../sessions"));
        assert!(!kiro_session_exists(&scratch("kiro-none"), "sess_6a2fda8e-84a4"));
    }

    #[test]
    fn a_new_kiro_orchestrator_gets_an_agent_file_with_only_its_folders_and_the_session_hook() {
        let home = scratch("kiro-orchestrator");
        let start = Start {
            prompt: "You are the Orchestrator.".into(),
            dirs: vec![PathBuf::from("/echo"), PathBuf::from("/state/memory")],
            cwd: Some(PathBuf::from("/work/repo")),
            model: Some("claude-opus-5.5".into()),
            effort: Some("high".into()),
            plugins: vec![PathBuf::from("/echo/mod")],
            title: "echo: repo".into(),
            first: Some("plan the work".into()),
            ..Start::default()
        };
        let args = kiro(&home, &start).unwrap();
        assert_eq!(args[..4], ["chat", "--v3", "--agent", args[3].as_str()]);
        assert!(
            args[3].starts_with("echo-") && args[3].len() == "echo-".len() + 16,
            "{args:?}"
        );
        assert_eq!(
            args[4..],
            [
                "--model",
                "claude-opus-5.5",
                "--effort",
                "high",
                "--trust-workspace",
                "plan the work"
            ]
        );
        let file = agent_file(&home, &args);
        assert!(
            file.starts_with(&format!("---\nname: {}\ndescription: Echo orchestrator\n", args[3])),
            "{file}"
        );
        assert!(
            file.contains("model: \"claude-opus-5.5\"\n") && file.contains("tools: [\"*\"]\n"),
            "{file}"
        );
        assert!(file.contains(
            "    - capability: fs_read\n      match: [\"/echo/**\", \"/state/memory/**\"]\n      effect: allow\n"
        ));
        assert!(file.contains("    - capability: fs_write\n      match: [\"/echo/**\", \"/state/memory/**\"]\n"));
        assert!(
            !file.contains("shell") && !file.contains("deny") && !file.contains("trigger: Stop"),
            "{file}"
        );
        assert!(file
            .contains("trigger: SessionStart\n    action:\n      type: command\n      command: \"echoctl notify\"\n"));
        assert!(file.ends_with("---\n\nYou are the Orchestrator.\n"), "{file}");
        assert!(
            !file.contains("/echo/mod") && !file.contains("echo: repo"),
            "plugins and title are ignored"
        );
    }

    #[test]
    fn a_kiro_worker_works_in_its_checkout_and_may_not_do_the_destructive_things() {
        let home = scratch("kiro-worker");
        let args = kiro(&home, &kiro_worker()).unwrap();
        let file = agent_file(&home, &args);
        assert!(
            file.contains("description: Echo worker\n") && file.contains("model: \"claude-haiku-5.5\"\n"),
            "{file}"
        );
        assert!(
            file.contains("tools: [\"shell\", \"read\", \"write\"]\n"),
            "ToolSearch and Task have no Kiro tool: {file}"
        );
        assert!(file.contains("    - capability: fs_read\n      match: [\"**\"]\n      effect: allow\n"));
        assert!(file.contains(
            "    - capability: fs_write\n      match: [\"/work/checkout/**\", \"/echo/**\", \"/state/memory/**\"]\n      effect: allow\n"
        ));
        assert!(file.contains("    - capability: shell\n      match: [\"*\", \"**\"]\n      effect: allow\n"));
        for denied in [
            "rm -rf *",
            "rm -fr *",
            "git reset --hard*",
            "sudo *",
            "curl * | sh",
            "curl * | bash",
            "wget * | sh",
            "wget * | bash",
        ] {
            assert!(file.contains(&format!("\"{denied}\"")), "{denied}: {file}");
        }
        assert!(file.contains("effect: deny\n"));
        for trigger in ["SessionStart", "Stop"] {
            assert!(
                file.contains(&format!(
                    "trigger: {trigger}\n    action:\n      type: command\n      command: \"echoctl notify\""
                )),
                "{trigger}: {file}"
            );
        }
        assert!(
            !file.contains("HUB_WORKER"),
            "Kiro's hooks inherit HUB_WORKER and HUB_AGENT"
        );
        assert!(
            file.ends_with("---\n\nContract: report with \"echoctl done\"\nthen stop\n"),
            "{file}"
        );
        assert_eq!(
            args[4..],
            [
                "--model",
                "claude-haiku-5.5",
                "--effort",
                "low",
                "--trust-workspace",
                "run the tests"
            ]
        );
    }

    #[test]
    fn a_kiro_session_without_a_prompt_or_folders_gets_no_rules() {
        let home = scratch("kiro-plain");
        let args = kiro(&home, &Start::default()).unwrap();
        let file = agent_file(&home, &args);
        assert!(
            file.contains("description: Echo session\n") && !file.contains("permissions") && !file.contains("model:"),
            "{file}"
        );
        assert_eq!(args[4..], ["--trust-workspace"]);
    }

    #[test]
    fn a_kiro_resume_names_the_session_and_puts_the_humans_arguments_before_the_message() {
        let home = scratch("kiro-resume");
        let start = Start {
            resume: true,
            first: Some("carry on".into()),
            extra: vec!["--model".into(), "auto".into()],
            ..kiro_worker()
        };
        let args = kiro(&home, &start).unwrap();
        assert_eq!(
            args[4..],
            [
                "--effort",
                "low",
                "--trust-workspace",
                "--resume-id",
                "sess_1",
                "--model",
                "auto",
                "carry on"
            ],
            "the human's --model wins"
        );
    }

    #[test]
    fn a_first_message_starting_with_a_dash_is_not_left_to_be_read_as_an_option() {
        let home = scratch("kiro-dash");
        let start = Start {
            first: Some("-d sess_1: delete it".into()),
            ..Start::default()
        };
        let args = kiro(&home, &start).unwrap();
        assert_eq!(args.last().unwrap(), "Message: -d sess_1: delete it");
        assert!(
            !args.contains(&"--".to_string()),
            "-- loses the message in the interactive TUI"
        );
        let plain = kiro(
            &home,
            &Start {
                first: Some("go -fast".into()),
                ..Start::default()
            },
        )
        .unwrap();
        assert_eq!(plain.last().unwrap(), "go -fast");
    }

    #[test]
    fn the_same_kiro_start_names_and_keeps_one_agent_file_and_another_prompt_gets_another() {
        let home = scratch("kiro-names");
        let first = kiro(&home, &kiro_worker()).unwrap();
        let path = home.join("agents").join(format!("{}.md", first[3]));
        let marker = "kept as it was\n";
        std::fs::write(&path, marker).unwrap();
        let again = kiro(&home, &kiro_worker()).unwrap();
        assert_eq!(first[3], again[3]);
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            marker,
            "an existing file is not rewritten"
        );
        let other = kiro(
            &home,
            &Start {
                prompt: "another contract".into(),
                ..kiro_worker()
            },
        )
        .unwrap();
        assert_ne!(first[3], other[3]);
        let mut names: Vec<_> = std::fs::read_dir(home.join("agents"))
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        assert_eq!(names.len(), 2, "no temp file is left: {names:?}");
        assert!(
            names.iter().all(|n| n.starts_with("echo-") && n.ends_with(".md")),
            "{names:?}"
        );
        assert_eq!(
            fnv1a("hello"),
            0xa430_d846_80aa_bd0b,
            "the hash is FNV-1a, stable across builds"
        );
    }

    #[test]
    fn a_kiro_model_of_another_provider_fails_the_start_and_writes_nothing() {
        let home = scratch("kiro-badmodel");
        let start = Start {
            model: Some("openai/gpt-5".into()),
            ..Start::default()
        };
        assert!(kiro(&home, &start)
            .unwrap_err()
            .to_string()
            .contains("pick another cli"));
        assert!(!home.join("agents").exists());
    }
}

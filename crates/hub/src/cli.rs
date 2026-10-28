//! Agent CLIs: the one place that knows how each runs. The daemon says what an agent starts with
//! (a `Start`); a `Cli` turns that into its own program and flags, and says whether a session can
//! be resumed. Which CLI and model an agent gets is picked here too, from the levels in `pick`.

use std::path::{Path, PathBuf};

use anyhow::{bail, Result};

use crate::paths;

/// An agent CLI Echo can run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cli {
    Claude,
}

/// Names Echo knows but cannot run yet, so the error says so instead of "unknown".
const COMING: &[&str] = &["opencode", "codex", "gemini"];

impl Cli {
    pub fn parse(name: &str) -> Result<Cli> {
        match name {
            "claude" => Ok(Cli::Claude),
            other if COMING.contains(&other) => bail!("cli {other:?} is not supported yet (only claude)"),
            other => bail!("unknown cli {other:?}; Echo runs claude"),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Cli::Claude => "claude",
        }
    }

    pub fn program(self) -> &'static str {
        self.name()
    }

    /// The CLI's own name for a `provider/model`; a bare name is passed as it is.
    pub fn model_arg(self, model: &str) -> Result<String> {
        match (self, model.split_once('/')) {
            (Cli::Claude, None) => Ok(model.to_string()),
            (Cli::Claude, Some(("anthropic", name))) => Ok(name.to_string()),
            (Cli::Claude, Some((provider, _))) => {
                bail!("claude runs only Anthropic models, not {provider}'s {model:?}; pick another cli for it")
            }
        }
    }

    /// Whether a session with this id has started, so it can be resumed instead of begun again.
    pub fn has_session(self, session_id: &str) -> bool {
        match self {
            Cli::Claude => paths::transcript_exists(session_id),
        }
    }

    /// The arguments after `program()` for `start`.
    pub fn args(self, hub: &Path, start: &Start) -> Result<Vec<String>> {
        match self {
            Cli::Claude => claude(hub, start),
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
        args.extend(["--tools".into(), start.tools.join(",")]);
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

/// A CLI and a model, as one level names them; either may be left to the level below.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Choice {
    pub cli: Option<String>,
    pub model: Option<String>,
}

impl Choice {
    /// `settings.json` in a folder: `{"cli": "claude", "model": "anthropic/claude-sonnet-5-5"}`.
    pub fn read(dir: &Path) -> Result<Choice> {
        let path = dir.join("settings.json");
        let Ok(text) = std::fs::read_to_string(&path) else {
            return Ok(Choice::default());
        };
        let value: serde_json::Value =
            serde_json::from_str(&text).map_err(|e| anyhow::anyhow!("{}: {e}", path.display()))?;
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
             --disallowedTools AskUserQuestion --add-dir /echo --add-dir /state/memory --effort low --tools Bash,Read \
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
}

# Agent CLIs sit behind one adapter, and the CLI and model come from four levels

Decided: 2026-10-28
Status: accepted

The daemon says what an agent starts with in CLI-neutral terms (a `Start` in `crates/hub/src/cli.rs`: title, prompt, folders, plugins, model, effort, tools, Worker or not, session, first message); a `Cli` turns it into its own program and flags and says whether a session can be resumed.
Only `claude` runs today; `opencode`, `codex`, and `gemini` are known names that fail with "not supported yet", and anything else as an unknown CLI.
Which CLI and model an agent runs with is picked in this order, each level over the ones before: `settings.json` in the daemon's state (`{"cli": ..., "model": ...}`), the repo's `.echo/settings.json`, the Profile's `cli` and `model`, then what `echoctl worker start --cli --model` or the agent's start picked, kept with the Worker or agent for its resumes.
Models are named `provider/model`, like `anthropic/claude-opus-5-5`; claude also takes a bare name, and refuses another provider's model with a message naming it.
A CLI or model that cannot run fails the start before a worktree is made; `echoctl profile list` shows what each Profile runs with here.
Reading the screen for prompts, the Worker hooks in `settings/worker.json`, and the account usage stay Claude Code's for now: each later adapter brings its own, or Echo shows it as missing.
Why: the human wants people to pick their model provider, and every later CLI to slot in without touching the daemon's launch code again.
Rejected: a trait with one implementation, which an enum with one arm covers until a second CLI exists.

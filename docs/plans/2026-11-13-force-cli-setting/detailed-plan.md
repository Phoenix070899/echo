# Detailed plan: forceCli

base_commit: 81fff6b
branch: chat-and-astryx
plan folder: docs/plans/2026-11-13-force-cli-setting/ (workers must not touch it)
Read first: big-picture.md, `docs/decisions/features/0036-*.md`, `0068-*.md`, `0075-*.md`, `CLAUDE.md`.

## Shared context
- Today `cli::pick(state, repo, levels)` in `crates/hub/src/cli.rs` (~L641-690) builds one list: state `settings.json`, the repo's `.echo/settings.json`, then `levels` (callers pass the Profile's `Choice`, then the explicit pick), and the last level with a cli, and the last with a model, win. Callers: `daemon.rs` `open_agent` (levels: the orchestratorModel choice, then the agent's own), `spawn_for` and `start_worker` (levels: `profile.choice()`, then the Worker's picked). `Choice::read(dir)` reads `cli` and `model` from a folder's `settings.json` (`settings::read`).
- Settings keys the daemon accepts are listed in `daemon.rs` `settings.get`/`settings.set` (~L1494-1534). `echoctl profile list` is built near `daemon.rs` L1381 from `pick`; Swift shows it as "Runs with" in `app/Sources/HubApp/AgentSettings.swift`.
- Swift: `AgentSettingsModel`/`AgentsSettings` in `AgentSettings.swift`; `agents.set(key, value)` sends a setting.

## T01 The daemon applies forceCli
- id: T01
- agent: naruto
- depends_on: none
- files: `crates/hub/src/cli.rs`, `crates/hub/src/daemon.rs`, `crates/hub/src/settings.rs` (if needed), `README.md`
- goal: implement decision 0075. `pick` must know which level is the Profile's: change its signature so the Profile level is separate (for example `pick(state, repo, profile: Option<&Choice>, picked: &[&Choice])`) and update every caller; with `forceCli` true in the state or repo settings (repo over state, as for the other keys) AND a `cli` set at those levels, drop the Profile level's cli and model. Everything else unchanged: explicit picks win, `orchestratorModel` still applies, the model must still pass `Cli::model_arg` so a bad pair fails before a worktree is made. `forceCli` with no `cli` forces nothing. Accept `forceCli` (bool) in `settings.set`/`settings.get` and in the repo settings; reject non-bool. `echoctl profile list` must show the forced cli and model. README: one sentence under the CLI paragraph.
- tests (in `cli.rs`): off by default (a Profile's cli wins as today); on with state cli+model (Profile ignored for both); on with cli only (model is none, not the Profile's); on with no cli (Profile applies); explicit pick beats the force; repo overrides state; `orchestratorModel` still applies to an Orchestrator under force. A `tests/daemon.rs` case: with `forceCli` and `cli: kiro`, `echoctl profile list` shows kiro for naruto (no real Kiro runs).
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED' `
- commit: `Daemon: forceCli makes the chosen CLI and model win over a Profile's own (features/0075)`

## T02 Settings has the switch
- id: T02
- agent: naruto
- depends_on: T01
- files: `app/Sources/HubApp/AgentSettings.swift`, `app/Sources/HubCore/*` (settings model), `app/Tests/`
- goal: a switch "Use for every agent" under the CLI and Model fields in `AgentsSettings`, bound to `forceCli` through the same path as the CLI picker; its explanation replaces the sentence that says a Profile's own CLI and model come first with: when off, a Profile's own CLI and model come first; when on, every agent runs this CLI and model. The Profile section's "Runs with" shows the daemon's resolved value. Follow the existing look (ui-ux decisions, Claude's design language, no new view). Write a short `docs/decisions/ui-ux/NNNN-*.md` only if the switch's placement or wording is a choice a later session could undo by accident (next number after the latest in `docs/decisions/ui-ux/`).
- tests: decode of the settings reply with and without `forceCli` in `app/Tests`; keep all existing tests green.
- verify: `make -C app test 2>&1 | tail -3 && make -C app app 2>&1 | grep -E 'error|Built'`
- commit: `Echo: Settings has a switch to run every agent on the chosen CLI`

## T03 Smoke on real Kiro, then final check
- id: T03
- agent: naruto
- depends_on: T02
- files: none (fixes only, each with a test and a `docs/bugs/` file)
- goal: prove goal 4 in an isolated daemon (`HUB_STATE=/tmp/hubk`, throwaway repo `/tmp/hubk-repo-eta`, `target/debug` first on PATH): write `/tmp/hubk/settings.json` `{"cli":"kiro","model":"claude-haiku-5.5","forceCli":true}`; note the `~/.kiro/agents/echo-*.md` list before; `echoctl worker start --repo /tmp/hubk-repo-eta --profile naruto --spec "Create hi.txt containing hi, commit it, then finish with echoctl done."` with no `--cli`; confirm the Worker runs on Kiro (its row's cli, the process `kiro-cli` in its tmux pane) and ends done; then set `forceCli` false and show the next Worker would pick naruto's Profile cli (claude): check with `echoctl profile list`, do not start a real Claude. Clean up in this order: kill tmux sessions whose start command contains `/tmp/hubk`, `echoctl shutdown --force` with the test env, delete `/tmp/hubk*`, delete the `echo-*.md` agent files that were not in the before list. Then from the repo root run the full Rust and Swift suites and confirm `git status` is clean.
- verify: `! ls /tmp | grep -q '^hubk' && ! tmux ls 2>/dev/null | grep -q hubk && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result' && make -C app test 2>&1 | tail -2 && [ -z "$(git status --short)" ]`
- commit: only if fixes were made.

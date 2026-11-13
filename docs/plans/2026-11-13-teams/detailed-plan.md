# Detailed plan: Teams

base_commit: 5a0875f
branch: chat-and-astryx
plan folder: docs/plans/2026-11-13-teams/ (workers must not touch it)
Read first: big-picture.md, decision features/0081, `0036`, `0053`, `0061`, `0068`, `0075`, `CLAUDE.md`, `CONTEXT.md`.

## Shared context
- Profiles: `crates/hub/src/profile.rs` (`dirs()` three levels, `load`, `parse`, `blank`, `start`, `Profile::choice`). Settings: `crates/hub/src/settings.rs` (`read`, `update`, `Rules`, `ORCHESTRATOR_MODEL`, `orchestrator_effort`, `orchestrator_rotate_at`, `force_cli`). Pick order: `cli.rs` `Choice`, `pick` (after forceCli it takes the Profile level separately). Orchestrator launch: `launch.rs::orchestrator_start` (rules via `Rules::from(&human).overrides()`), `daemon.rs::open_agent` (~L659-815), `renew_if_due` (~L817), `spawn_for`/`start_worker` for Workers (`worker.agent` is the starting Orchestrator's id), verifiers and fan-out start through `start_worker` too. DB: `crates/hub/src/db.rs` (`agents` columns added by `alter table` migrations guarded by `has_column`; `AGENT_COLUMNS`; `Agent` struct decoded by the app in `app/Sources/HubCore/Models.swift`).
- Swift: `app/Sources/HubApp/NewSession.swift` (`NewSessionModal`, `NewSessionForm`), `AgentSettings.swift` (`AgentSettingsModel`, `AgentsSettings`, Profile editor `ProfileModelField`), `SettingsPage.swift`/`SettingsView.swift` (how pages are listed), `ContentView.swift` (`AgentLine` tooltip, `AgentPanel` header), `app/Sources/HubCore/Models.swift`.
- The daemon's request handler lives in `daemon.rs` (`"settings.get"`, `"settings.set"`, `"profile.list"`, `"profile.set"` style methods ~L1380-1540: follow how Profiles are listed and saved).

## T01 Team files
- id: T01
- agent: naruto
- depends_on: none
- files: `crates/hub/src/team.rs` (new), `main.rs` (mod), `<repo root>/teams/claude-opus.json`, `claude-lean.json`, `kiro-lean.json` (shipped seeds, exactly as big-picture.md lists them)
- goal: `Team` struct and the three-level loader exactly as decision 0081 specifies (same folder rules and replace-whole as `profile::dirs`/`load`), `list(hub, state, repo)` returning each Team with its `origin` (shipped, user, repo) and any `problem` (a Team with an invalid field is listed with its problem and cannot be used, like Profiles), `load(...)`, `save(state_or_repo_dir, &Team)` (atomic write of pretty JSON, name checked: lowercase letters, digits, `-`, 1 to 40 chars, not a path), `delete(...)` (only the user and repo levels), and `validate(&Team)`: each `cli` is known, each `model` passes `Cli::model_arg` for its cli (a model with no cli is checked against the CLI that would apply: the Team's own `orchestrator.cli`/`workers.cli`, else the settings' `cli`, else claude), `effort` in the set the CLI takes (`settings::EFFORTS`), `rotateAt` 0 or at least 10000, `maxWorkers` 1..=16, `profiles` keys non-empty. Unknown fields are kept out of the model but not an error (forward compatibility); wrong types are errors with the file path in the message.
- tests: parse of each seed; the three levels and replace-whole; validation failures (bad cli, `anthropic/…` model under kiro, bad effort, bad name, `maxWorkers` 0); save then load round trip; delete refuses a shipped Team; every shipped seed validates.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl team:: 2>&1 | grep -E '^test result|FAILED'`
- commit: `Daemon: Teams, named setups for an Orchestrator, its Workers and its rules (features/0081)`

## T02 The Orchestrator starts with its Team
- id: T02
- agent: naruto
- depends_on: T01
- files: `crates/hub/src/db.rs`, `crates/hub/src/daemon.rs`, `crates/hub/src/launch.rs`, `crates/hub/src/settings.rs`, `crates/hub/src/main.rs` (`echoctl agent open --team`), tests
- goal: `agents.team` (nullable text) with a guarded migration and in `AGENT_COLUMNS`/`Agent`; `agent.open` takes `team` (validated: it must exist and validate, before anything is created), kept on the agent like `model`/`cli`, and an agent with no `team` behaves exactly as today. In `open_agent`, for an Orchestrator with a Team: CLI, model, effort come from the Team's `orchestrator` at the level decision 0081 gives (below what was picked for that agent, above `orchestratorModel`/`orchestratorEffort`/general settings); `rotateAt` replaces `orchestrator_rotate_at(settings)` in `renew_if_due`; `launch::orchestrator_start` gets the Team's `rules` merged over the human's (`Rules::from(settings)` with the Team's present keys replacing) and appends the Team's `instructions` after the rules block and before the "Repo for this Hub Session" line, under a heading `# Team instructions`. The Team is re-read at every start and resume (including `renew_agent`). A Normal session or Terminal given a `team` is refused with a clear message. `echoctl agent open --team <name>` passes it (find the command in `main.rs`).
- tests: Orchestrator with a Team uses the Team's cli/model/effort; an explicit pick wins; no Team unchanged (existing tests green); rules merge (Team `review:false` over settings `review:true`, absent keys fall through); instructions land in the prompt in the right place; editing the Team file then resuming changes the next start; migration on a database created without the column; bad Team name refused before creating an agent or worktree.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED'`
- commit: `Daemon: an Orchestrator starts and resumes with its Team (features/0081)`

## T03 Workers follow their Orchestrator's Team
- id: T03
- agent: naruto
- depends_on: T02
- files: `crates/hub/src/daemon.rs`, `crates/hub/src/cli.rs`, `crates/hub/src/profile.rs`, tests
- goal: in `start_worker`, `spawn_for` and the places that compute a Worker's CLI/model/effort for display (the Worker row from T04 of the Kiro fixes plan, `profile.list`), resolve in decision 0081's order: explicit pick > Team `workers.profiles.<Profile>` > Team `workers` > Profile > repo > state (with `forceCli` applying only where the Team names nothing and the agent has no Team entry for it). `worker.agent` finds the Orchestrator and its Team; a Worker with no agent or an agent with no Team is unchanged. Effort: a Team's `workers.effort` / profile entry wins over the Profile's `effort`. Verifiers and fan-out tries resolve the same way (they are Workers of the same agent; check that each passes `agent`). A start fails before any worktree when the Team's pair cannot run. `profile.list` accepts an optional `team` and shows the resolved cli/model/effort; `echoctl profile list --team <name>` passes it.
- tests: every step of the order, table-driven; forceCli interplay (Team entry beats force; no Team entry falls to force); a resumed Worker re-resolves with the edited Team; a Worker of an agent without a Team is byte-for-byte as before; the Worker row's resolved model/effort reflect the Team.
- verify: same cargo command
- commit: `Daemon: Workers follow their Orchestrator's Team (features/0081)`

## T04 Team requests and the CLI
- id: T04
- agent: naruto
- depends_on: T03
- files: `crates/hub/src/daemon.rs`, `crates/hub/src/main.rs`, `crates/hub/tests/daemon.rs`, `README.md`
- goal: daemon methods `team.list` (with origin, problem, and each Team's fields), `team.get`, `team.save` (level: `user` or the repo path; validates; refuses a shipped name's overwrite by writing the user-level copy), `team.delete`; `echoctl team list` and `echoctl team show <name>` print readably (follow `echoctl profile list`). Echo Remote needs nothing. README: a short section on Teams (the file format, where they live, `echoctl team list`, how a Team differs from a Profile, that a Team applies at start/resume).
- tests: `tests/daemon.rs` case: save a Team through the socket, list it, open an Orchestrator with it using the fake agent (`HUB_TEST_AGENT`) and see the agent's stored team; delete it; saving an invalid Team returns the validation message.
- verify: same cargo command
- commit: `Daemon: team.list, team.get, team.save, team.delete and echoctl team`

## T05 The app: pick a Team, see a Team
- id: T05
- agent: naruto
- depends_on: T04
- files: `app/Sources/HubCore/Models.swift` (or a new `Teams.swift` in HubCore: `Team` decode, tolerant of unknown fields), `app/Sources/HubApp/AppModel.swift`, `NewSession.swift`, `ContentView.swift`, `app/Tests/`
- goal: the New session sheet, in Orchestrator mode, has a "Team" picker (compact, in the Name/Model row or a row of its own: keep the dialog short for small windows) listing the Teams by name with a one-line summary of the chosen one under it ("Orchestrator: claude-sonnet-5.5, medium. Workers: by their Profiles."); default is the last Team used (kept in UserDefaults) else `claude-opus`; the model picker beside Name is replaced by the Team in Orchestrator mode (a model picked for an Orchestrator would override the Team, so hide it there; Normal mode keeps it). `agent.open` is sent with `team`. The agent row's tooltip and the agent panel header name the Team. Keep to the repo's look decisions (Claude's design language, `Ledger` tokens, 30 pt rows, no lines); write a short ui-ux decision for the picker and where the Team shows.
- tests: `Team` decode with and without optional fields and with unknown ones; the form builds the `agent.open` parameters with a Team and without; remembered choice. Existing tests stay green.
- verify: `make -C app test 2>&1 | tail -3 && (cd app && swift build --product HubApp 2>&1 | tail -2)`
- commit: `Echo: the New session sheet picks a Team, and an Orchestrator shows which one it runs`

## T06 The app: Teams in Settings
- id: T06
- agent: naruto
- depends_on: T05
- files: `app/Sources/HubApp/AgentSettings.swift` (or a new `TeamSettings.swift`), `SettingsPage.swift`/`SettingsView.swift`, `app/Tests/`
- goal: a Teams page in Settings next to Agents: a list of Teams with origin labels and a problem line where there is one; New, Duplicate and Delete (Delete only for user and repo Teams); an editor for the picked Team: description; Orchestrator (CLI picker from `agentCLIs`, model field with a hint matching the CLI, effort picker, "Renew at" tokens field with a note when the CLI is kiro that renewal is not supported there yet); Workers (CLI, model, effort for all); a per-Profile overrides list (add a row: Profile picker from `profile.list`, CLI, model, effort; remove a row); Rules (max Workers stepper 1 to 16, toggles for plan approval, review, merge without asking); Instructions (multi-line text). A shipped Team is read-only with a Duplicate button. Saving sends `team.save` and shows the daemon's validation message inline on failure (do not duplicate validation in Swift beyond required fields). Same look rules as the Agents page; write a ui-ux decision only for choices a later session could undo (page order, shipped Teams read-only).
- tests: a pure form-state type tested in `app/Tests`: building the save payload from the form (omits unset fields), loading a Team into the form, adding and removing an override, duplicate naming (`name-copy`, `name-copy-2`).
- verify: same as T05
- commit: `Echo: Settings has a Teams page to create, duplicate and edit Teams`

## T07 CONTEXT and docs
- id: T07
- agent: naruto
- depends_on: T06
- files: `CONTEXT.md`, `README.md` (only if T04 left gaps), `docs/decisions/` (only for choices not yet recorded)
- goal: CONTEXT.md gets the term **Team** next to Agent Profile (what it is, that it applies at start/resume, that it is not a Profile and not a Hub Session); anything a later session could undo by accident and has no decision yet becomes a numbered decision file (do not edit committed ones).
- verify: `grep -q '\*\*Team\*\*' CONTEXT.md && git diff --stat HEAD~1 | tail -1`
- commit: `Docs: Team in the glossary`

## T08 Smoke on real Kiro, then final check
- id: T08
- agent: naruto
- depends_on: T07
- files: none (fixes only, each with a test and a `docs/bugs/` file)
- goal: in an isolated daemon (`HUB_STATE=/tmp/hubk`, throwaway repo `/tmp/hubk-repo-kappa`, `target/debug` first on PATH, no `forceCli`): (a) `echoctl team list` shows the three shipped Teams; (b) open an Orchestrator with `--team kiro-lean`: show its process arguments (`kiro-cli chat --v3 --agent echo-… --model claude-sonnet-5.5 --effort medium`) and that the generated agent file contains the Team's rules/instructions text; (c) from that Orchestrator (or with `echoctl worker start` carrying its `HUB_AGENT`) start a `naruto` Worker without `--cli`/`--model`: it runs on Kiro with `claude-sonnet-5.5` (naruto's Team override) and a `lee`/`ino` Worker runs with `claude-haiku-5.5`; give each a one-line Task so they finish; (d) edit the Team file (change naruto's model), resume the Worker, and show the new model in the process arguments; (e) open an Orchestrator with `--team claude-lean` without starting a real Claude (use `HUB_TEST_AGENT` for this one) and show the args the daemon would have built, or the stored agent row; (f) `swift build --product HubApp` and `make -C app test`; run a test copy of the app (own bundle id `dev.agenthub.Echo.test`) against the isolated daemon and capture the New session sheet and the Teams page with `screencapture -l <window id>` without stealing focus; if that cannot be done here, say so. Clean up in this order: tmux sessions whose start command contains `/tmp/hubk`, `echoctl shutdown --force` with the test env, the test app copy, `/tmp/hubk*`, then the `echo-*.md` agent files not present before (note any other files Kiro wrote under `~/.kiro`). Then run the full Rust and Swift suites and confirm `git status` is clean apart from this plan's `status.md`.
- verify: `! ls /tmp | grep -q '^hubk' && ! tmux ls 2>/dev/null | grep -q hubk && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result' && make -C app test 2>&1 | tail -2 && [ -z "$(git status --short | grep -v 'docs/plans/2026-11-13-teams/status.md')" ]`
- commit: only if fixes were made.

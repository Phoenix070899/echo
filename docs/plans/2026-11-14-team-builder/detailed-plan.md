# Detailed plan: Team builder (one Teams section, Members in a tree)

base_commit: 05c92fc35f332741bb0b2f55e1f5caec71b58506
branch: plan/team-builder
plan folder: docs/plans/2026-11-14-team-builder/ (workers must not touch it)
Read first: big-picture.md (goals, words, design), CLAUDE.md, CONTEXT.md, decisions features/0081, 0082, 0075, 0055, 0036, 0068 and ui-ux/0035, 0043, 0044, 0045, 0099, 0100, 0008, 0013, 0006.

## Shared context (every task gets this)

### Words and rules fixed by the human's approval ("execute team builder plan first")
- **Team** = a named setup (what the human called a "profile"). **Profile** = one Worker's role (naruto). **Member** = a node of a Team's tree: a Worker slot. **Action** = what a Member is for.
- Shipped Actions, fixed (no user-defined ones; "custom" is a Member whose `action` is `"custom"`): `scan` (hinata), `research` (jiraiya), `execute` (naruto), `verify` (sasuke), `run` (lee), `scribe` (ino).
- The tree is a plan of hand-offs run by the Orchestrator and the daemon. It is NOT nested delegation: Workers still only talk to their Orchestrator.
- Team file gets `members`, a flat array in tree order; `parent` is another Member's `id`, absent at level 1. Fields of a Member (all camelCase, all optional except `id`, `action`, `profile`): `id`, `action`, `profile`, `parent`, `instructions`, `replaceRole` (bool), `cli`, `model`, `effort`, `tools` (list), `skills` (list), `context` (list), `lessons` (bool), `writes` (bool), `worktree` (`"current"` | `"new"`; only a hint printed to the Orchestrator).
- `id` must satisfy `profile::valid_name` (lowercase letters, digits, `-`, at most 32, not starting with `-`); ids are unique in a Team. Validation: `parent` names an existing Member, no cycles, depth at most 3 (level 1 is depth 1), a `verify` Member's parent must be an `execute` Member, `action` is a shipped Action id or `custom`, cli/model/effort checked with the existing `check_pick` under the field label `members.<id>`, at most 24 Members.
- Lookup of the name in `echoctl worker start <name>`: a Member `id` first; else the FIRST Member (tree order) whose `profile` equals `<name>`; else the bare Profile (today's behaviour). A Team without `members` behaves exactly as today.
- Resolution order for a Worker's CLI, model, effort: explicit pick (`--cli`/`--model`) > the Member > Team `workers.profiles.<profile>` > Team `workers` > Profile > repo `.echo/settings.json` > state `settings.json`. `forceCli` (0075) treats a Member entry like any Team entry: where the Team (Member included) names a field it wins over `forceCli`; elsewhere `forceCli` applies as before.
- Overlay of a Member on its Profile when its Worker starts: `instructions` are appended after the Profile's role (or replace the role when `replaceRole`); `tools`, `skills`, `context` REPLACE the Profile's list when the Member's list is non-empty; `lessons: false` leaves the Lessons out of that Worker's prompt (default true, today's behaviour); `writes` is informational.
- A Worker whose Member is gone from an edited Team (on resume, in the ledger rows) falls back to the Profile-level resolution of its stored `profile`; it never errors for that.
- Verification: the daemon's verifier for a writer is the writer Member's `verify` child (its Profile and overlay); with no such child it is `sasuke` as today. The retry message names the verifier it used, not "sasuke". The Team's `rules.review`, when set, decides whether `--verify` verifies (today only the human's setting does; this is a deliberate fix, record it in `docs/bugs/`).
- Shipped Teams (`teams/claude-opus.json`, `claude-lean.json`, `kiro-lean.json`) keep their names, orchestrator and `workers` all-level exactly and gain a tree of Members (see T09); every Worker resolves to the same CLI, model and effort as before.

### Code map (from the code analysis; paths relative to `crates/hub/` unless noted; line numbers drift, search by name)
- `src/team.rs`: `Team`, `OrchestratorSetup`, `Choice`, `WorkersSetup`, `RulesSetup`; `Team::worker_levels`; `validate` (:~422), `check_pick`, `save`, `delete`, `list`/`Entry` (a parse error gives `team=None` plus `problem`, a validate error gives `team=Some` plus `problem`), `summary`, `details`, `valid_name` (40 chars). Structs use `rename_all="camelCase", default`, no `deny_unknown_fields`; every optional field is `skip_serializing_if`, so a Team without members serializes unchanged. Tests there: see the list in the module (`each_shipped_seed_parses_to_what_the_plan_lists`, `every_shipped_seed_validates_under_any_default_cli`, `validation_refuses_what_cannot_run`, ...); helpers `scratch`, `put`, `named`, `problem`.
- `src/daemon.rs`: `team_json` (flattens the Team's fields into `{name, origin, path, replaces, problem, ...}`), `team.list`/`team.get`/`team_save`/`team_delete`; `start_worker` (loads the Profile BEFORE it knows the agent and Team: the order must change), `worker_team`, `pick_for`, `spawn_for`, `worker_choices`, `resume_worker`, `rows`, `profiles.list`, `start_verifier`/`verified`/`verify`, `fan_out` (passes params through, so a `member` param passes), `SECTIONS` allow-list for `echoctl ui settings` (~:3043; it lacks `teams` today).
- `src/profile.rs`: `Profile`, `parse`, `system_prompt` (order: worker-contract, Preferences, Lessons, role, skills, context), `resolve`, `start`, `valid_name`, tests with `NARUTO`, `resolved(...)`, `runs(...)`, `every_step_of_the_order_for_a_worker`.
- `src/cli.rs`: Claude args (`--tools`, `--append-system-prompt`), Codex (ignores `tools`), Kiro (`kiro_tools` maps Bash/Read/Edit/Write/WebFetch/WebSearch; an empty or unmappable list becomes `"*"`; the agent file name is a content hash).
- `src/launch.rs`: `start_in`, prompt order: orchestrator.md, Preferences, Lessons, rules overrides (`Rules::from(human).with_team(...)`), `# Team instructions`, `Repo for this Hub Session: ...` last (a test pins that end). A generated "Your Workers" section goes after the rules and before `# Team instructions`.
- `src/db.rs`: `has_column` + `alter table ... add column` migrations (see `agents.team`), `WORKER_COLUMNS`, `worker_row`, `NewWorker`, `insert_worker`; test `a_database_from_before_teams_gains_the_column_and_keeps_its_agents` is the model for a migration test. `NewWorker`/`Worker` literals also appear in tests in `db.rs` and `daemon.rs`.
- `src/main.rs`: `TeamCommand`/`team_command`, `profile list --team`, `worker start` args and its output line, `worker list`, `status`; `ui settings` doc comment and `default_value = "agents"`.
- `tests/daemon.rs`: real `echoctl` against `HUB_STATE=/tmp/hubt-...` with `HUB_TEST_AGENT=tests/fake-agent.sh`; helpers `Hub::{new,run,ok,call,...}`, team helpers `put_team`, `open_orchestrator`, `start_under`, `row_of`, `runs_of`. With the test agent, prompt assembly is skipped, so overlay and "Your Workers" text are only unit-testable (`profile.rs`, `launch.rs`). A verifier spec still must start "Verify the work of" (fake-agent keys on it).
- Swift (`app/`): `Sources/HubCore/Teams.swift` (Team decoder, `TeamChoice`, `openAgentParams`), `HubCore/TeamForm.swift` (form, `saveParams`, `blocker`), `HubCore/Models.swift` (`WorkerProfile`, `AgentSettings`), `HubCore/DaemonClient.swift` (`teams`, `saveTeam`, `deleteTeam`, `profiles`, `profile(...)`, `agentSettings`, `setAgentSettings`); `Sources/HubApp/SettingsPage.swift` (`SettingsSection`, rows, keys, 680 pt cap), `SettingsView.swift` (`page {}`, `.agents`/`.teams` cases, `refreshAgents/Teams`), `AgentSettings.swift` (`AgentSettingsModel`, `AgentsSettings`, `ProfileModelField`, `OrchestratorSettings`), `TeamSettings.swift` (`TeamSettingsModel`, `TeamsSettings`, `TeamRow`, `TeamAbout`, `TeamOrchestrator`, `TeamWorkers`, `TeamRules`, `TeamInstructions`, `TeamSave`, `CliPicker`, `EffortPicker`), `NewSession.swift` (modal pattern, `NewSessionForm`, `TeamPicker`), `ContentView.swift` (modal overlays ~:42-52), `AppModel.swift` (`settingsSection`, `showSettings`, `modalShown`, `echoctl ui settings` handling ~:1067), `Theme.swift` (`Ledger` tokens, `LedgerButtonStyle`, `LedgerSegmented`, `.ledgerField()`, `.ledgerSheet()`), `FilePreview.swift` ~:513-533 (the only working `.draggable`/`.dropDestination(for: String.self)` pattern).
- Swift tests exist only for `HubCore` (`app/Tests/HubCoreTests`, Swift Testing: `@Test`, `#expect`, `@testable import HubCore`, inline JSON). `HubApp` has no tests, so every state machine (tree operations, drop validation, templates, form state) is a pure function or struct in `HubCore`.

### Hazards found in the analysis (must be handled by the task named)
- `team.save` replaces the file with whatever `team` the client sends and drops unknown fields: a client that does not carry `members` through erases them. The Swift form must carry them before any new daemon save path is used (T11 before T13).
- `echoctl ui settings teams` is refused today, and a removed Swift section falls back to `.agents` (`AppModel` ~:1067). T10 and T13 fix both; `agents` stays accepted and means `teams`.
- The settings page's plain Up/Down keys switch sections (`SettingsPage.swift` ~:84-99). A focused tree must handle Up/Down first; T15 must prove it with a test or a documented check, and fix the page's handler if the inner handler does not win.
- `SettingsView` recreates its models when the section changes (`.id(section)`), and picking another Team discards edits silently. T13 adds an "unsaved changes" ask.
- `TeamForm` equality includes `nextOverrideID`; use a stable equality (exclude generated counters) so "changed" is exact.
- ⌘N and ⌘D are menu bindings: the tree never uses them.
- `LedgerSegmented` uses a shadow against ui-ux/0013: new controls use fills only.
- Only add Kiro agent files named `echo-*.md` under `~/.kiro/agents`; never touch other files in `~/.kiro`.

### Constraints for every task
Obey decisions in force; never edit a committed decision file (supersede with a new numbered file in the same folder; `docs/decisions/README.md` has the format). A bug found or fixed gets a `docs/bugs/` file in the same change (`docs/bugs/README.md`). Use CONTEXT.md words in code, copy and commits. Rust: `~/.cargo/bin/cargo fmt --check` and `~/.cargo/bin/cargo test -p echoctl` must stay green. Swift: `make -C app test` must stay green and `cd app && swift build --product HubApp` must build; do NOT run `make -C app app`; do not delete `target/` or `app/.build/`; no `@State` (Command Line Tools only): use `ObservableObject` + `@StateObject`. Tests that run a daemon use `HUB_STATE=/tmp/hubk...` (short) and never touch the human's daemon, Echo, tmux or Kiro. UI: `Ledger` tokens only, no shadows, plain copy (ui-ux/0007), keyboard-first (ui-ux/0008). Commit on the current branch with the prefix `Daemon:`, `Echo:` or `Docs:`; plain message, no attribution, no em dashes; never push, amend, rebase, stash or switch branches. Do not touch the plan folder. Delete generated files that are not part of the task before committing.

---

## T01 Decisions and glossary
- id: T01
- agent: naruto
- depends_on: none
- files: `docs/decisions/features/0084-*.md` to `0087-*.md`, `docs/decisions/ui-ux/0101-*.md` to `0103-*.md`, `CONTEXT.md`
- goal: write these decision files (next free numbers if these are taken; each in the README's format, `Decided: 2026-11-14`, `Status: accepted`, one decision per file, one sentence per line, with Why and Rejected): features/0084 "A Team has Members, each started from a Profile for an Action" (the file format, id rules, validation list, start-name lookup, overlay semantics, the fallback for a missing Member, `workers.profiles` still honoured); features/0085 "A Member's own choices come before the Team's Workers entries" (the resolution order and the `forceCli` interplay; Supersedes nothing, it extends 0081's order); features/0086 "A Team's tree is a plan of hand-offs, and a verify Member replaces sasuke" (no nested delegation and why, the verifier child and its fallback, the retry text, the Team's `rules.review` over the human's setting for the daemon, "Your Workers" in the Orchestrator's prompt); features/0087 "Echo's own Actions are six, plus custom" (list, default Profiles, no user-defined Actions in v1); ui-ux/0101 "Settings has one Teams section in place of Agents and Teams" (`Supersedes: ui-ux/0043` and `ui-ux/0099`; the section's content: Teams list, a Defaults entry holding the default CLI/model/`forceCli` and the Orchestrators' default rules, the tree, the inspector, the palette; `agents` stays an accepted alias in `echoctl ui settings`; the section uses the whole window width and `Supersedes: ui-ux/0044` and `0045` for this section only); ui-ux/0102 "A Team's tree is edited by dragging and by keys" (drag rules: onto a Member makes a child, between rows reorders, to the left edge promotes, invalid drops show why and do nothing; keys with the tree focused and no field being edited: Up/Down select, Option+Up/Down move among siblings, Option+Right indent, Option+Left outdent, Return opens the name, Delete removes (asks when it has children), `a` adds a Member, `d` duplicates; never Command+N/D); ui-ux/0103 "Unsaved Team edits ask before they are lost" (switching Team or section, closing Settings: Save, Discard, Cancel). Add `Member` and `Action` to CONTEXT.md in the existing style (with `_Avoid_`), and add to the `Team` entry that it holds a tree of Members.
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub && ls docs/decisions/features | tail -4 && ls docs/decisions/ui-ux | tail -3 && grep -c "^\*\*Member\*\*\|^\*\*Action\*\*" CONTEXT.md && grep -rn "Supersedes" docs/decisions/ui-ux/01*.md | head` -> new files listed, count 2, the Supersedes lines present
- commit: `Docs: decisions for Team Members, Actions and the Teams section`

## T02 Actions
- id: T02
- agent: naruto
- depends_on: T01
- files: `actions/scan.json`, `research.json`, `execute.json`, `verify.json`, `run.json`, `scribe.json` (new, repo root), `crates/hub/src/action.rs` (new), `crates/hub/src/main.rs` (mod), `crates/hub/src/paths.rs` only if the hub dir helper lives there
- goal: shipped Actions as read-only JSON files in the echo repo (found through the same `hub` dir the Profiles use). Fields: `id`, `title` (one or two words, e.g. "Scan code"), `description` (one plain sentence for the palette), `profile` (default Profile: hinata, jiraiya, naruto, sasuke, lee, ino), `routing` (one sentence the Orchestrator reads, e.g. "Send questions about how existing code works here"), `writes` (bool), `worktree` (`"current"` or `"new"`), `under` (for `verify` only: `"execute"`, the Action its Member must sit under). `action.rs`: `Action` struct (serde, camelCase), `list(hub) -> Vec<Action>` sorted in the order scan, research, execute, verify, run, scribe, `get(hub, id)`, and `is_action(id)` accepting these ids and `custom`.
- tests: each shipped file parses; the six ids and their default Profiles; every default Profile exists in `profiles/`; `verify.under == "execute"`; `is_action("custom")`; an unknown id is refused.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl action:: 2>&1 | grep -E '^test result|FAILED'` -> `ok`, no FAILED
- commit: `Daemon: Echo's own Actions (features/0087)`

## T03 Members in a Team file
- id: T03
- agent: naruto
- depends_on: T01, T02
- files: `crates/hub/src/team.rs`
- goal: `Member` struct and `members: Vec<Member>` on `Team` (`default`, `skip_serializing_if = "Vec::is_empty"`), exactly the fields and validation of "Shared context". Validation lives in `validate` and returns messages that name the Member (`members.build: parent "x" is not a Member`). Add `Team::member_for(name) -> Option<&Member>` (id first, else the first Member whose `profile` equals `name`), `Team::children(id)`, `Team::verifier_of(id) -> Option<&Member>` (the first child whose `action` is `verify`), and `team::check_profiles(team, known_profiles) -> Result<()>` (every Member's `profile` is known; used by the daemon, not by `validate`). Extend `summary` (append `, N Members` only when there are some, keeping it one line) and `details` (an indented tree, one line per Member: `build  execute  naruto  claude-sonnet-5-5  high`, children indented, each overridden field named).
- tests: parse and round trip of a Team with Members; a Team without `members` serializes byte-identical to before (assert on the shipped seeds' text); every validation failure (duplicate id, bad id, missing parent, cycle, depth 4, verify not under execute, unknown action, bad model for the CLI, 25 Members); `member_for` precedence; `verifier_of`; unknown Member fields ignored; `details` output for a three-Member tree.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl team:: 2>&1 | grep -E '^test result|FAILED'` -> `ok`, no FAILED
- commit: `Daemon: a Team holds Members in a tree (features/0084)`

## T04 A Worker records its Member
- id: T04
- agent: naruto
- depends_on: T01
- files: `crates/hub/src/db.rs`, `crates/hub/src/daemon.rs` (only the row/view/message JSON and test literals), `crates/hub/src/main.rs` (only output lines), `crates/hub/src/brief.rs`, tests
- goal: a nullable `workers.member` column with a guarded migration (the `agents.team` pattern), in `WORKER_COLUMNS`, `worker_row`, `Worker`, `NewWorker` (`member: Option<String>`), `insert_worker`; update every `NewWorker`/`Worker` literal in tests. Show it without removing `profile`: add `member` (null when absent) beside `profile` in `view` (`worker.list`), `rows` (`echoctl status` and Echo's ledger), the `done`/`wait` message JSON, `worker.start`'s response, and print it in `echoctl worker list` and `status` as `profile` alone when null, else `member (profile)`; `brief.rs` likewise. Echo Remote reads only `profile`, so it stays untouched. Nothing sets `member` yet.
- tests: migration on a database created without the column (drop it, reopen, re-added, idempotent); insert and read back a Worker with and without a Member; rows/view JSON have `member: null` for today's Workers; existing daemon tests unchanged and green.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED'` -> all `ok`, no FAILED
- commit: `Daemon: a Worker records the Member it started as`

## T05 Workers start and resume as a Member
- id: T05
- agent: naruto
- depends_on: T03, T04
- files: `crates/hub/src/profile.rs`, `crates/hub/src/daemon.rs`, `crates/hub/src/cli.rs` (only if `Choice` plumbing needs it), `crates/hub/src/main.rs` (help text), `tests/daemon.rs`
- goal: implement the lookup and the resolution order of "Shared context". `profile::resolve` takes the Worker's Member (`Option<&Member>`) beside the Team; the Member sits between `picked` and `workers.profiles.<profile>`, for cli, model and effort, with the `forceCli` rule unchanged. In `start_worker`, find the agent and its Team BEFORE loading the Profile, turn the requested name into `(profile_name, member)` with `Team::member_for` (else the bare Profile), load that Profile, resolve, and store `member` on the Worker. A Member's id or Profile that cannot run is refused before any worktree exists, like a bad Team today. `pick_for`, `worker_choices`, `rows`, `chat_cli`/recovery and `resume_worker` re-resolve from the stored `member` against the Team read NOW; a Member that is gone falls back to the Profile-level resolution with no error. `profiles.list` and `echoctl profile list --team` keep resolving per Profile (they gain nothing here). `worker start`'s argument is documented as `<member-or-profile>`; its success line prints the Member when there is one. A `fan_out` passes the name through unchanged.
- tests: table-driven unit tests of every step of the order, modelled on `every_step_of_the_order_for_a_worker`, including `forceCli` (Member beats it; no Member falls to it) and effort; daemon integration (fake agent): start by Member id; start by Profile name picks the first Member using it; a two-naruto Team resolves each Member to its own model (read from the row JSON); a Team without Members and an unknown name behave as today; editing the Team file to change a Member's model changes the Worker's row after a resume; removing the Member falls back without error; a Member whose model cannot run stops the start before the worktree exists.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED'` -> all `ok`, no FAILED
- commit: `Daemon: Workers start and resume as a Team's Member (features/0085)`

## T06 A Member's overlay reaches its Worker
- id: T06
- agent: naruto
- depends_on: T05
- files: `crates/hub/src/profile.rs`, `crates/hub/src/daemon.rs` (`pick_for` only), `crates/hub/src/cli.rs` (only if a test seam is needed)
- goal: apply the overlay of "Shared context" in `pick_for` (the seam that already returns a mutated Profile clone): `instructions` appended after the role as a `# This Team's instructions for you` paragraph (or replacing the role when `replaceRole`), non-empty `tools`/`skills`/`context` replacing the Profile's, `writes` into `Profile.writes`, and a new `Profile.lessons: bool` (default true when parsed from a file) that `system_prompt` honours (no Lessons block when false). Preferences stay in every prompt.
- tests (unit, since the test agent skips prompt assembly): `system_prompt` with each overlay field; `lessons: false` drops only the Lessons; Claude `Start` carries the Member's `--tools` list; the Kiro agent file lists the mapped tools and a different overlay gives a different `echo-<hash>` name; Codex ignores `tools` without error; a Member with no overlay gives byte-identical prompts to today's for the same Profile (golden comparison against the Profile alone).
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl profile:: cli:: 2>&1 | grep -E '^test result|FAILED'` -> `ok`, no FAILED, then the full crate green
- commit: `Daemon: a Member's instructions, tools, skills and context reach its Worker`

## T07 The Orchestrator is told its Workers
- id: T07
- agent: naruto
- depends_on: T03, T02
- files: `crates/hub/src/launch.rs`, `orchestrator.md`, `crates/hub/src/settings.rs` (only the wording at the "Skip the sasuke verification" line), `crates/hub/src/main.rs` (the `--verify` help text)
- goal: for a Team with Members, a generated `# Your Workers` section goes after the rules overrides and before `# Team instructions`: one line per Member (id, Action title, the Action's `routing` sentence, the Profile's description, the model it will run, `worktree` hint), the tree's hand-offs as sentences ("when `scan` reports, give its report to `build` with `--from-report`"; a `verify` child: "`check` verifies `build` automatically; start `build` with `--verify`"), the start command `echoctl worker start <id> ...`, and "start Workers by these ids". Without Members nothing is added (byte-identical prompt). `orchestrator.md`: where it says to start by `<profile>` and to run `echoctl profile list`, add that a "Your Workers" list, when present, names the ids to use and replaces the profile list; the Verification section names "the verifier" with sasuke as the default; `settings.rs` wording likewise. Keep the final `Repo for this Hub Session:` line last.
- tests: prompt for a three-Member Team contains the section in the right place, in tree order, with each model; prompt for a Team without Members is byte-identical to today's (compare with a stored expectation from before the change); the existing order tests still pass; a `verify` child produces the `--verify` sentence.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl launch:: settings:: 2>&1 | grep -E '^test result|FAILED'` -> `ok`, no FAILED, then the full crate green
- commit: `Daemon: an Orchestrator is told its Team's Workers and their hand-offs (features/0086)`

## T08 The verifier Member and the Team's review rule
- id: T08
- agent: naruto
- depends_on: T05
- files: `crates/hub/src/daemon.rs` (`start_worker` role setup, `start_verifier`, `verified`), `crates/hub/src/db.rs` only if needed, `tests/daemon.rs`, `docs/bugs/<next>-a-teams-review-rule-did-not-reach-the-daemon.md`
- goal: `start_verifier` reads the writer's Team now, takes `verifier_of(writer.member)` and starts that Member (`member` param to `start_worker`, so its Profile, model and overlay apply); with none (no Team, no Members, no `verify` child, or the writer's Member is gone) it starts `sasuke` exactly as today. The retry text and the Orchestrator note name the verifier actually used. `start_worker` decides `verifies` from the Team's `rules.review` when the writer's agent has a Team that sets it, else from the human's setting. The spec still begins "Verify the work of" and keeps the Verdict instruction. Write the bug file (the Team's review rule only shaped the prompt while the daemon read the human's setting alone).
- tests (fake agent): a Team with `build` > `check` (profile `sasuke`, model override) verifies with `check` (row shows its member and model); no `verify` child uses sasuke; a Team with `rules.review: false` over a human `review: true` starts a `--verify` writer without verification and the reverse verifies; the retry message names the verifier; `FAILME`, `ALWAYSFAIL`, `NOVERDICT` flows still pass; the existing verify tests stay green.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED'` -> all `ok`, no FAILED
- commit: `Daemon: a Team's verify Member verifies its writers, and its review rule is the daemon's too (features/0086)`

## T09 Shipped Teams as trees
- id: T09
- agent: naruto
- depends_on: T05, T02, T03
- files: `teams/claude-opus.json`, `teams/claude-lean.json`, `teams/kiro-lean.json`, tests in `crates/hub/src/team.rs` and `crates/hub/tests/daemon.rs`
- goal: each shipped Team gains the same tree of Members: `scan` (scan, hinata), `research` (research, jiraiya), `build` (execute, naruto) with child `check` (verify, sasuke), `run` (run, lee), `scribe` (scribe, ino); `scan` and `research` may sit at level 1. Move kiro-lean's per-Profile overrides into the Members (`build`: model `claude-sonnet-5.5`, effort high; `check`: `claude-sonnet-5.5`, medium) and drop its `workers.profiles`, keeping its `workers` all-level and orchestrator as they are; claude-opus and claude-lean get Members with no overrides. Names, orchestrator, rules and descriptions do not change. Update the two assertions that pin the seeds (`each_shipped_seed_parses_to_what_the_plan_lists`, the shipped-list assertion in `tests/daemon.rs`) deliberately.
- tests: every seed validates; for each seed and each of the six Profiles, the CLI, model and effort a Worker started by Profile name resolves to (through the new Member lookup) equal what the OLD seed gave (store the old expectations in the test as literals); a Worker started by Member id resolves the same as by its Profile name.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED'` -> all `ok`, no FAILED
- commit: `Daemon: Echo's own Teams are trees of Members`

## T10 What the app needs from the daemon
- id: T10
- agent: naruto
- depends_on: T03, T02, T06
- files: `crates/hub/src/daemon.rs`, `crates/hub/src/main.rs`, `skills/skills/echo/SKILL.md` (the `ui settings` line), `tests/daemon.rs`
- goal: (1) `team.actions` returns `{actions:[...]}` from `action::list`; `echoctl team actions` prints them. (2) `profiles.list` adds `tools`, `skills`, `context` (arrays), `role` (the Profile's body text), `ownEffort` stays, so the Member inspector can show what a field would be without a Member's override. (3) `team_save` rejects a Team whose Members name an unknown Profile (use `check_profiles`) with a message naming the Member, before anything is written. (4) `echoctl team show` prints the tree (T03's `details`). (5) the `SECTIONS` allow-list of `ui.settings` gains `teams`; `agents` stays accepted and is mapped to `teams`; `echoctl ui settings`'s doc comment and default become `teams`; the SKILL.md text matches.
- tests: `team.actions` over the socket; `profiles.list` JSON carries the new fields for a shipped Profile; `team.save` with a Member on an unknown Profile fails and writes nothing; saving a Team with Members then `team.get` returns them back unchanged (a Team round trip through the socket keeps `members` in order); `ui.settings` accepts `teams` and `agents`.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED'` -> all `ok`, no FAILED
- commit: `Daemon: team.actions, Profile details for the Member inspector, and the teams settings section`

## T11 HubCore: Members, Actions and a form that keeps them
- id: T11
- agent: naruto
- depends_on: T10
- files: `app/Sources/HubCore/Teams.swift`, `app/Sources/HubCore/TeamForm.swift`, `app/Sources/HubCore/Models.swift` (`WorkerProfile` gains tools, skills, context, role), `app/Sources/HubCore/DaemonClient.swift` (`actions()`), `app/Tests/HubCoreTests/` (extend `TeamTests.swift`, `TeamFormTests.swift`)
- goal: `Team.Member` (Decodable, Equatable, Identifiable, Sendable, all fields of "Shared context", defaults so the memberwise init stays source compatible) and `Team.members` (decoded with `?? []`); `Action` model; `DaemonClient.actions()`; `WorkerProfile` new optional fields. `TeamForm` carries `members` through `init(team:)`, `init(copying:taking:)`, `fields`/`saveParams(repo:)` (members serialized in order, only the fields that are set), `blocker` (the same structural checks as the daemon, so the app refuses before the daemon does), and equality that ignores generated counters. A form built from a Team and saved without edits sends back every Member field it received (round-trip test with all fields set).
- tests: decode a Team with Members and without; round trip; `saveParams` contains `members` in order and omits unset fields; blocker cases (duplicate id, missing parent, cycle, depth, verify not under execute, 25 Members); `changed` is false after a pure round trip; `Action` and `WorkerProfile` decode with and without the new keys.
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub && make -C app test 2>&1 | tail -15` -> tests pass, no failures
- commit: `Echo: Teams carry Members and Actions in the app's models`

## T12 HubCore: the tree's operations and the New Team starting points
- id: T12
- agent: naruto
- depends_on: T11
- files: `app/Sources/HubCore/TeamTree.swift` (new), `app/Sources/HubCore/TeamTemplates.swift` (new), `app/Tests/HubCoreTests/TeamTreeTests.swift` (new), `TeamTemplatesTests.swift` (new)
- goal: pure functions on a `[Team.Member]` (flat, tree order): `rows(members) -> [(member, depth)]`; `add(action:under:)` (id from the Action, made unique; Profile from the Action's default; inherits nothing else); `remove(id)` (with its descendants; returns them so the UI can ask); `duplicate(id)` (with descendants, new unique ids); `move(id, by: ±1)` among siblings; `indent(id)` (under the previous sibling); `outdent(id)`; `drop(id, onto: target, as: .child | .before | .after)`; `canDrop(...) -> DropVerdict` (`ok` or a plain-language reason: would create a cycle, too deep (max 3), a verify Member needs an execute parent, moving a Member into its own subtree; dropping it where it already is). Every operation returns a tree that passes the same structural rules as `TeamForm.blocker`; an invalid operation returns `nil` and changes nothing. Starting points: `TeamTemplate` cases `blank`, `solo` (build > check), `standard` (scan, build > check, run), `researchHeavy` (research, scan, build > check, run), each producing `members` from the Actions' default Profiles; `ProviderPreset` cases `claude`, `kiro`, `codex` giving the orchestrator and worker CLI, model and effort to fill in (use the models in the shipped Teams: Claude `anthropic/claude-opus-5-5` high for the Orchestrator and the Profiles' own models for Workers; Kiro `claude-sonnet-5.5` medium and `claude-haiku-5.5` low with naruto/sasuke on `claude-sonnet-5.5`; Codex `openai/` models only if the shipped Profiles already name one, else leave the model empty), and `TeamForm.starting(template:preset:name:level:)`.
- tests: every operation's result tree, order and ids; each rejected drop with its reason; depth and cycle edges; a randomized property check (a fixed seed loop of 500 random operations never yields an invalid tree); each template validates under each preset with `TeamForm.blocker` == nil.
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub && make -C app test 2>&1 | tail -15` -> tests pass, no failures
- commit: `Echo: the Team tree's operations and starting points as pure functions`

## T13 One Teams section
- id: T13
- agent: naruto
- depends_on: T11, T10
- files: `app/Sources/HubApp/SettingsPage.swift`, `SettingsView.swift`, `AgentSettings.swift`, `TeamSettings.swift` (reworked, may be split into `TeamsSection.swift`, `TeamDefaults.swift`, `TeamInspector.swift`), `AppModel.swift` (the `ui settings` fallback and `lastSettingsSection`), `ContentView.swift` only if needed
- goal: `SettingsSection` loses `.agents` and keeps `.teams`, titled "Teams" (icon `person.3`); `SettingsSection(rawValue: "agents")` maps to `.teams` (also for `echoctl ui settings agents` and the AppModel fallback). The section uses the whole content width (no 680 pt cap for it). Layout: left a Teams list (shipped, yours, repo's, with New, Duplicate, Delete as today) with a "Defaults" entry at the top; the right shows the picked entry. "Defaults" holds everything the old Agents page held at human level: default CLI and model, "Use for every agent" (`forceCli`), and the Orchestrators' default rules (max Workers, plan approval, review, merge without asking) with the existing `agents.set` calls. A picked Team shows, for now, its Team-level form: description, level, the Orchestrator's CLI, model, effort, renew-at, Workers' default CLI/model/effort (and the older "by Profile" overrides, kept, editable), rules, instructions (reuse the existing editor views), and the Save/Revert/Duplicate bar. Nothing from the old Agents page is lost except the single-Profile editor, which T14 re-homes into the Member inspector (until T14 the Profile editor stays reachable as a "Profiles" entry below Defaults, so the app is never missing a feature between tasks). "Unsaved changes" ask (Save, Discard, Cancel) when picking another entry, switching section or closing Settings with a changed form (ui-ux/0103). The New session sheet and the agent header keep working.
- tests: `HubCore`-level where a pure piece exists (section alias mapping can be a `HubCore` helper tested there); otherwise the app must build and the existing tests stay green.
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub/app && swift build --product HubApp 2>&1 | tail -3 && cd .. && make -C app test 2>&1 | tail -8` -> `Compiling`/`Build complete`, tests pass
- commit: `Echo: Settings has one Teams section in place of Agents and Teams (ui-ux/0101)`

## T14 The Member inspector
- id: T14
- agent: naruto
- depends_on: T13
- files: `app/Sources/HubApp/TeamInspector.swift` (or the file T13 created), `AgentSettings.swift` (remove what is re-homed), `app/Sources/HubCore/TeamForm.swift` (member edit helpers, tested), `app/Tests/HubCoreTests/`
- goal: selecting a Member (T15 adds the tree; until then a simple indented list of Members under the Team form selects it) shows its inspector: Name (id; edit renames and updates children's `parent`), Action (picker), Profile (picker; changing the Action offers its default Profile), Instruction (multi-line, with the "Replace the role" switch), CLI/model/effort (the `CliPicker`/`EffortPicker` and model hint of the Team form), Tools (checklist of Read, Grep, Glob, Edit, Write, Bash, WebFetch, WebSearch; a note when the effective CLI ignores them: Codex, or Kiro for a tool it cannot map), Skills and Context (comma separated), Lessons switch, Writes and Worktree. Every field shows where its value comes from ("from naruto", "this Team", "your defaults") using `WorkerProfile` and the Team form, and has a Reset that clears the Member's own value. Buttons: "Edit shared role…" (opens the Profile's file, copying Echo's own into yours first, with a one-line note that it changes every Team), "New custom Worker…" (asks a name, creates the Profile with `profile.new`, adds a `custom` Member on it, selects it). The old single-Profile editor is removed from the Settings once nothing is lost (the Profile's own CLI/model/effort stay editable through "Edit shared role…" and the Profile file). Member edits only touch the draft until Save.
- tests: `TeamForm` member helpers (rename updates children, change action keeps valid, clear field) in HubCore tests.
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub/app && swift build --product HubApp 2>&1 | tail -3 && cd .. && make -C app test 2>&1 | tail -8` -> build complete, tests pass
- commit: `Echo: a Member's instruction, model, tools, skills and context are edited in an inspector`

## T15 The tree, with keys and buttons
- id: T15
- agent: naruto
- depends_on: T12, T14
- files: `app/Sources/HubApp/TeamTreeView.swift` (new), the Teams section file(s) of T13
- goal: the tree view: the Orchestrator as root (selecting it shows the Team-level form of T13), Members indented by depth with the Action's icon (SF Symbols) and title, the Member's id, its Profile and the model it runs on; selection; "+" button on a node and a "Add Member" menu (the six Actions and "Custom"); duplicate and delete buttons; keyboard with the tree focused and no field being edited, exactly ui-ux/0102: Up/Down select, Option+Up/Down move among siblings, Option+Right indent, Option+Left outdent, Return opens the name field, Delete removes (asks when it has children), `a` adds, `d` duplicates, all through `TeamTree` and the form draft. A rejected operation shows its reason in a one-line caption under the tree. Use a custom recursive view, not `List`/`OutlineGroup`. The tree handles Up/Down before the settings page does; prove it (a note in the task report with how it was checked, e.g. the page's handler guarded by a "tree has focus" flag) and fix the page's handler if needed. No mouse drag yet. State lives in an `ObservableObject`.
- tests: the operations are covered in T12; here the build and a written check of the key handling in the report.
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub/app && swift build --product HubApp 2>&1 | tail -3 && cd .. && make -C app test 2>&1 | tail -8` -> build complete, tests pass
- commit: `Echo: a Team is a tree of Members with keys and buttons (ui-ux/0102)`

## T16 Drag and drop, and the palette
- id: T16
- agent: naruto
- depends_on: T15
- files: `app/Sources/HubApp/TeamTreeView.swift`, `app/Sources/HubApp/TeamPalette.swift` (new)
- goal: drag a Member row with `.draggable(String)` (payload `member:<id>`) and drop with `.dropDestination(for: String.self)`, the pattern proven in `FilePreview.swift`; each row has three drop zones (top quarter: before, middle: as child, bottom quarter: after); a thin insertion line or a highlighted row (Ledger tokens, no shadow) shows the target; a drop is judged by `TeamTree.canDrop` as the pointer enters and an invalid one shows the reason in the caption and does nothing; dropping at the left edge of the tree promotes to level 1. The palette strip above the tree has chips for the six Actions and the six shipped Workers (naruto, sasuke, hinata, jiraiya, lee, ino) and "Custom"; dragging a chip onto a Member adds a child, between rows inserts, onto empty space adds at level 1 (payload `chip:<action>:<profile>`). Highlight state lives in an `ObservableObject` (no `@State`). If a drop kind cannot be made to work in the CLT build, the keyboard path (T15) and a "Move to…" menu per Member (list of valid new parents from `canDrop`) must cover it; say so in the report. Real mouse dragging cannot be driven automatically: report what was compiled and what was exercised by calling the same drop handler with synthetic payloads in a HubCore-level test of the payload parsing (`member:`/`chip:` strings into `TeamTree` calls), and mark real dragging as a check for the human.
- tests: a HubCore function `DropPayload.parse(String)` and the mapping from payload plus zone to a `TeamTree` operation, tested for each payload kind and zone.
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub/app && swift build --product HubApp 2>&1 | tail -3 && cd .. && make -C app test 2>&1 | tail -8` -> build complete, tests pass
- commit: `Echo: Members are dragged to reorder and reparent, and added from a palette`

## T17 The New Team sheet
- id: T17
- agent: naruto
- depends_on: T12, T13
- files: `app/Sources/HubApp/NewTeam.swift` (new), `ContentView.swift` (overlay), `AppModel.swift` (`modalShown` and the flag), the Teams section file(s)
- goal: "New Team" opens a sheet in the modal style of `NewSession.swift` (ui-ux/0006: fixed width, `Ledger.paper`, hairline, no shadow, Esc closes, `.isModal`, wired into `modalShown`): Name (validated live with `TeamForm.blocker` rules), "Keep in" (yours or the repo's, only with a repo), Starting point (Blank, Solo, Standard, Research-heavy, Copy of an existing Team) as cards with one plain line each, Provider (Claude, Kiro, Codex) as a segmented control. Create builds the form with `TeamForm.starting(...)`, closes the sheet, selects the new unsaved Team in the Teams section with its tree showing and the Orchestrator selected. It is one sheet from click to a saved Team after Save; Duplicate in the list keeps working.
- tests: none new beyond T12's; the app must build and tests stay green.
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub/app && swift build --product HubApp 2>&1 | tail -3 && cd .. && make -C app test 2>&1 | tail -8` -> build complete, tests pass
- commit: `Echo: New Team starts from a template and a provider`

## T18 Docs, cleanup, bug files
- id: T18
- agent: naruto
- depends_on: T09, T16, T17, T08
- files: `README.md` (Agent Profiles and Teams sections, the `echoctl team`/`profile` lines, the Layout table `actions/`), `skills/skills/echo/SKILL.md`, `docs/bugs/` (one file per bug found while building, if any not yet written), dead code removed from `AgentSettings.swift`/`TeamSettings.swift`/`SettingsView.swift`
- goal: README describes Members, Actions, the tree, `worker start <member>`, and the one Teams section (replace the "Agents" tab mentions); remove code and strings nothing uses any more (the old Agents page, unused model fields) without removing any behaviour a test covers; the repo has no references to the removed `.agents` Swift case; `grep -rn "SettingsSection.agents" app` finds nothing. No em dashes in new text.
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED'; make -C app test 2>&1 | tail -6; grep -rn "SettingsSection.agents\|case .agents" app/Sources | head` -> tests pass, grep prints nothing
- commit: `Docs: Members, Actions and the Teams section in the README and the echo skill`

## T19 Smoke runs
- id: T19
- agent: naruto
- depends_on: T18
- files: `crates/hub/tests/daemon.rs` (one end-to-end test), `docs/research/team-builder-smoke.md` (new, the report)
- goal: (1) an integration test with the fake agent: a Team with `scan`, `build` > `check` and `run` Members is saved over the socket, an Orchestrator is opened with it, Workers are started by Member id and by Profile name, a writer started with `--verify` is verified by the `check` Member, the Team file is edited (a Member's model changed, one Member removed) and the Workers resume without error, and `echoctl team show` prints the tree. (2) Real run, short, on Kiro with `HUB_STATE=/tmp/hubk`, a throwaway git repo whose folder name differs from any real one, `claude-haiku-5.5` for every Member (and the Orchestrator `claude-sonnet-5.5`), `KIRO_HOME` untouched except `echo-*.md` agent files: save a three-Member Team (`scan` > ... any valid), open an Orchestrator on it, start the `scan` Member on a one-line question, confirm the Worker's row shows its Member and model and a Final Report arrives; quote the commands and output in the report. If `kiro-cli` is not signed in or the run fails for a reason outside the code, record that and what was tried and mark the run "not done", do not retry beyond twice. (3) Visual check, best effort and only per CLAUDE.md "Testing Echo end to end" (a test bundle id, `screencapture -l`, posted keys, no focus stealing, never the human's Echo or daemon): capture the Teams section of a test copy of the app against the test daemon with `echoctl ui settings teams` and save PNGs to `docs/screenshots/teams-tree.png` and `teams-inspector.png`; if it cannot be done without disturbing the human's Mac or Echo, skip it and say so. Clean up in the order CLAUDE.md lists (tmux sessions, then the test daemon with `echoctl shutdown --force`, then the test folders).
- verify: `cd /Users/dung.nguyen/Documents/Projects/agent-hub && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED'; test -s docs/research/team-builder-smoke.md && git status --porcelain | grep -v "docs/plans/2026-11-14-team-builder" | head` -> tests pass, report exists, no stray files
- commit: `Docs: Team builder smoke runs`

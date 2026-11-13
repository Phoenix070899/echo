# Detailed plan: Kiro fixes

base_commit: 7882ad7
branch: chat-and-astryx
plan folder: docs/plans/2026-11-13-kiro-fixes/ (workers must not touch it)
Read first: big-picture.md; `../2026-11-13-kiro-parity/status.md` (the findings, with file and line); decisions `features/0076`, `0077`, `0078`, `ui-ux/0097`; `CLAUDE.md`.

## T01 Resume carries the current Task
- id: T01
- agent: naruto
- depends_on: none
- files: `crates/hub/src/profile.rs`, `crates/hub/src/launch.rs`, `crates/hub/src/daemon.rs`, `crates/hub/src/db.rs`, tests, `docs/bugs/`, a decision file if the rule needs one
- goal: find where a resumed Kiro Worker gets its Task (decision 0076, commit 9b3ab87) and make it the Task the Worker is working on now. `worker next` (`Launch::Next`) and a verifier sending a writer back with feedback give a Worker a later Task; the DB keeps inputs (`db::inputs`, `insert_input`) as well as `workers.spec`. Decide from the code which record is the current one, use it, keep the length bound, and keep Claude's and Codex's resume messages byte-for-byte. Write the rule as a decision if it is a choice (for example "the latest input from the Orchestrator or Echo that is a Task, not a chat line the human typed").
- tests: a Worker with a first spec and a later Task resumes with the later one; a Worker with one spec as before; other CLIs unchanged.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED'`
- commit: `Daemon: a resumed Kiro Worker is re-sent the Task it is on now`

## T02 One error line per failed Kiro turn
- id: T02
- agent: naruto
- depends_on: T01
- files: `crates/hub/src/kiro_chat.rs`, tests with fixtures, `docs/bugs/`
- goal: a failed turn writes `session_metadata displayError` and a `turn_end` with `stopReason: error` as two lines. If a poll sees only the `turn_end`, the reader emits a generic "the turn failed" line, and the next poll adds the real message, so both show. Make the output depend only on the file's content, not on where a page boundary or a poll fell: for example look ahead within the same turn id (bounded) or drop the generic line when the message arrives, and keep paging offsets consistent. Check the app-side dedupe in `app/Sources/HubCore/Chat.swift` too (an `after` poll appends items; the generic line is already in the list), and fix whichever side is right with the least change.
- tests: the two lines in one read, split across two reads with `after`, and read from the tail with `before`; the same visible result each time.
- verify: same cargo command; if Swift changed also `make -C app test 2>&1 | tail -2`
- commit: `Daemon: a failed Kiro turn shows one error line`

## T03 Credits round, and the scratch home is not optional
- id: T03
- agent: naruto
- depends_on: T02
- files: the Kiro usage code from commit 705b31b (`crates/hub/src/daemon.rs` or `kiro_usage.rs`), tests, `docs/bugs/`
- goal: round the percent to the nearest integer (580 of 2000 is 29, not 28; check 0 and 100 edge cases); when the scratch KIRO_HOME for the `kiro-cli acp` child cannot be created, skip that reading (keep the last good value, no error shown, one line to stderr) instead of falling back to the human's `~/.kiro`, as decision 0078 states.
- tests: rounding table; a failing scratch dir creation (point the scratch parent at a file or a read-only dir) runs no child and keeps the last value.
- verify: same cargo command
- commit: `Daemon: Kiro credits round, and the reader never falls back to the human's Kiro home`

## T04 A Worker's header names what it ran with
- id: T04
- agent: naruto
- depends_on: T03
- files: `crates/hub/src/daemon.rs` (where `WorkerRow` model and effort are filled, check with `grep -n "modelLine\|effort" crates/hub/src/daemon.rs app/Sources/HubCore/Models.swift`), `app/Sources/HubApp/ContentView.swift` (`WorkerHeader`), tests, `docs/bugs/`
- goal: with `forceCli` and Kiro the header of a Worker shows the Profile's model and effort (Sonnet, high) while it ran Haiku. Make the row carry the resolved CLI, model and effort: the model and CLI `cli::pick` returned for that Worker (`spawn_for` computes them; the Worker row stores only an explicit pick), and the effort the CLI actually got (a Profile's effort still applies under force, decision 0075). Show the CLI's name next to the model when it is not claude. Do not store anything new in the DB unless needed; computing it when the snapshot is built is fine if cheap (it reads settings files: cache per snapshot or reuse what `profile list` does). Keep the snapshot unchanged for an unforced Claude Worker, byte for byte (the unchanged-snapshot check avoids redraws).
- tests: a forced-Kiro Worker's row shows the forced model and effort; an unforced Claude Worker's row is identical to before; Swift decode test if a field is added.
- verify: `~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result|FAILED' && make -C app test 2>&1 | tail -2`
- commit: `Daemon: a Worker's row names the CLI, model and effort it ran with`

## T05 Final check
- id: T05
- agent: naruto
- depends_on: T04
- files: none expected
- goal: run the full Rust and Swift suites, `make -C app app` is NOT to be run (it replaces the running Echo; use `swift build --product HubApp` in `app/` instead), confirm the tree is clean, and give a short real-Kiro check only for T01 if it can be done in under five minutes in an isolated daemon (`/tmp/hubk`, `claude-haiku-5.5`): give a Worker a second Task with `worker next`, interrupt, `worker resume`, and read which Task the resumed session received from its `messages.jsonl`. Clean up as before.
- verify: `! ls /tmp | grep -q '^hubk' && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo test -p echoctl 2>&1 | grep -E '^test result' && make -C app test 2>&1 | tail -2 && [ -z "$(git status --short | grep -v 'docs/plans/2026-11-13-kiro-fixes/status.md')" ]`
- commit: only if fixes were made.

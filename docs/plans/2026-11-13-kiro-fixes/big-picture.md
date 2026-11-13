# Big picture: the review findings left after Kiro parity

Status: approved by the human ("yes"), 2026-11-13. Source: the open findings in `../2026-11-13-kiro-parity/status.md` and its final report. Standing constraints are those of `../2026-11-13-kiro-parity/big-picture.md` (decisions are never edited, only superseded by a new file; a bug fixed gets a `docs/bugs/` file; isolated `HUB_STATE=/tmp/hubk`; `~/.kiro` is the human's: only `echo-*.md` agent files may be added and removed; real Kiro runs on `claude-haiku-5.5`, short; do not touch the daemon pid that is not yours or the running Echo; do not delete `target/` or `app/.build/`; commit prefixes `Daemon:`/`Echo:`/`Docs:`, no attribution, no em dashes, never push, amend or rebase).

## Goals
1. A resumed Kiro Worker is re-sent the Task it is on now, not always its original one (after `worker next` or verify feedback).
2. A failed Kiro turn shows one error line in the chat, never two.
3. Kiro credits round to the nearest percent.
4. The Kiro credits reader does exactly what decision 0078 says when it cannot make its scratch KIRO_HOME: it skips the reading, with no error shown and no fallback to the human's `~/.kiro`.
5. A Worker's header shows the CLI, model and effort it actually ran with (forced or picked), not its Profile's.

## Non-goals
Stats for Kiro, Orchestrator renewal on Kiro, a CLI picker per session, anything for Claude or Codex beyond not changing them.

## Acceptance
fmt, `~/.cargo/bin/cargo test -p echoctl` and `make -C app test` pass; each fix has a test that fails without it; each has a bug file in `docs/bugs/` (goals 1, 2, 5 certainly; 3 and 4 may share one); decisions are added only where a later session could undo a choice (goal 1's rule for which Task a resume carries); the tree is clean at the end; the report says what was and was not checked on a real Kiro.

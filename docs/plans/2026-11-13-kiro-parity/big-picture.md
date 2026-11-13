# Big picture: Kiro agents get a chat tab, a credits reading, and a resume that keeps the Task

Status: approved by the human ("go all"), 2026-11-13. Follows `../2026-11-13-kiro-cli-provider/` (milestone 1, shipped) and `../2026-11-13-force-cli-setting/`. Read their big-picture.md for the standing constraints; they apply here unchanged, including: obey the decisions in force and never edit a committed decision file, bugs found get a `docs/bugs/` file, `HUB_STATE=/tmp/hubk` and throwaway repos for any daemon run, `~/.kiro` is the human's (only `echo-*.md` agent files may be added, and removed again), real Kiro runs use `claude-haiku-5.5` and stay short, commit prefixes `Daemon:`/`Echo:`/`Docs:`, no attribution lines, no em dashes, never push, amend or rebase.

## Goals
1. **Resume keeps the Task.** After `echoctl worker resume` (and after a daemon restart that resumes), a Kiro Worker continues its original Task instead of answering "Task not in this session" and finishing blocked (found in the milestone 1 smoke run). Root cause first, then the fix, with a real-Kiro reproduction before and after.
2. **Chat tab for Kiro.** An Orchestrator, Normal session or Worker on Kiro shows its conversation in the chat tab as Claude's do, read from `~/.kiro/sessions/*/<session id>/messages.jsonl` (entry types are in `docs/research/kiro-cli-spike.md` Q10): the human's messages, replies, tool calls and results, errors and interrupts, paging back through the history, and the Working row and prompt state as now. `chat.read` stops answering `supported: false` for Kiro.
3. **Credits on the usage bar.** The top bar keeps Claude's Session and Week exactly as today and adds Kiro's credits (used of plan, percent, reset date) when `kiro-cli` is signed in. The source is whichever of these the spike (T03) proves reliable, in this order: Kiro's account usage over its ACP server (`_kiro/account/getUsage`, found in the bundled server, not yet run), else the per-turn `usage_summary` credits summed over Echo's own Kiro sessions this billing period, labelled as Echo's share. A failed reading shows nothing and keeps the last good value, as for Claude.

## Non-goals
Stats and the "Worker start" figure for Kiro (stay "not counted"); Orchestrator renewal by context size on Kiro; Kiro cloud sessions; changing how Claude's or Codex's chat, usage or resume work; a per-session CLI picker.

## Acceptance
- `~/.cargo/bin/cargo fmt --check`, `~/.cargo/bin/cargo test -p echoctl` and `make -C app test` pass; new unit tests cover the Kiro transcript reader (fixture JSONL built from Q10's examples, including a failed turn, a cancelled turn, a denied tool call, a multi-turn session and paging), the credits parsing, and the resume message.
- A real smoke run (T06) on `claude-haiku-5.5` in an isolated daemon shows, as evidence in the report: (a) a Kiro Worker's `chat.read` returns user, reply and tool items with `supported: true`; (b) after `worker resume` the Worker continues its Task and ends done; (c) the `usage` reply carries Claude's limits unchanged plus a Kiro credits entry (or, if the spike found no way to read it, the reply is unchanged and the report says why).
- New decisions are written where a later session could undo a choice by accident (the Kiro chat mapping, the credits source and how the bar shows it, the resume message); the tree is clean at the end.

## Constraints specific to this plan
- The Claude chat reader (`crates/hub/src/chat.rs`) and Claude usage code keep their behaviour and tests; put Kiro's reader in its own module (for example `kiro_chat.rs`) and share only what is genuinely shared.
- Large transcripts: a Kiro `messages.jsonl` can be tens of MB (the human's own current session is 84 MB). Read by byte offset from the tail as `chat::read` does; never load the whole file.
- The disk can fill: do not delete `target/` or `app/.build/`, create no large files, report "no space" failures.
- The ACP call (if used) is a short-lived `kiro-cli acp` child with a hard timeout (60 s), killed on exit, never left running; it must not start a chat session or spend credits.

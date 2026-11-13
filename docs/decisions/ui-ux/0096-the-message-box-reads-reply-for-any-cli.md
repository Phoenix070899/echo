# The message box says "Reply…" because the agent may run on any CLI

Decided: 2026-11-13
Status: accepted

Supersedes: ui-ux/0085, only where it sets the message box's placeholder to "Reply to Claude…"; the rest of 0085 stands.
The message box of an Orchestrator or a Normal session reads "Reply…", and a Worker's box keeps its Intervention line.
The snapshot does not say which CLI an agent runs on, and an agent can run on Claude Code, Codex or Kiro (features/0068), so the box names none.
Why: "Reply to Claude…" was wrong for a Kiro session and the app cannot tell which one it is talking to.
Rejected: adding a `cli` field to the snapshot just for a placeholder; naming the CLI can come with the chat tab for Kiro, when the snapshot needs the field anyway.

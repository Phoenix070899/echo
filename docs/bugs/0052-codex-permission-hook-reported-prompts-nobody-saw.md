# Codex Workers reported permission prompts that never showed, because the hook fires before Codex's reviewer

Found: 2026-10-28
Where: crates/hub/src/cli.rs (codex), crates/hub/src/main.rs (notify)
Fixed in: the change that adds this file

A Codex Worker asked to run a command outside its sandbox reported "Blocked: permission_prompt" to the Orchestrator, while its screen showed the command already run and the turn going on.
Cause: Codex runs the PermissionRequest hook when it is about to ask, before its own reviewer (`approvals_reviewer = "auto_review"` in the human's config) approves; most requests never reach a prompt.
Fix: Codex gets no PermissionRequest hook; its prompts are read from the screen, which shows only what really waits on the human.
Lesson: report a prompt only from what the human would see; a CLI's "about to ask" event is not a prompt.

# A resumed Kiro Worker is sent the latest Task it was given, not a line typed into its chat

Decided: 2026-11-13
Status: accepted

Supersedes: features/0076's "the Worker's Task from the database", only for which Task that is; the rest of 0076 stands.
The Task a resume repeats is the Worker's latest input that gave it a Task: its first (from `worker start` or a fan-out), a next one from `worker next`, or a verifier's feedback sent back to a writer. Each is stored with a `task` mark in `worker_inputs`, whoever sent it (the Orchestrator, Echo, or the human through a fan-out).
An input typed into a Worker's chat is never a Task: not `worker send`, not the human's text, not a review, not Echo's own resume message. A Worker with no marked input, such as one stored before the mark existed, is sent `workers.spec`.
`workers.spec` is not changed by a next Task: it stays the Task the Worker started with, which the verifier reads for what the writer was asked.
The 4000-character cut and Claude's and Codex's `RESUMED` message are as 0076 has them.
Why: a Worker that took `worker next` or feedback was resumed on its first Task, which it had finished, and the session that lacked the history had no word of the one it was on. Origin alone cannot tell a Task from a chat line, since the Orchestrator's `worker send` and `worker next` share one origin, so the Task is marked when it is given.
Rejected: updating `workers.spec` on each next Task, which gives the verifier a retry's feedback as "the Task it was given" instead of the original; taking the latest input from the Orchestrator or Echo, which would pick a `worker send` nudge or Echo's own resume message.

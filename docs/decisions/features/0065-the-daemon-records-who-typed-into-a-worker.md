# The daemon records who typed each text into a Worker

Decided: 2026-11-12
Status: accepted

`worker_inputs` keeps each text the daemon types into a Worker with its origin: `orchestrator` for `worker start`, `worker send` and `worker task`; `human` for a fan-out from Echo, a review sent to the Worker, and `chat.send`; `echo` for a resumed session's note and the verifier's Task and retry.
`chat.read` marks each `user` item whose text matches a recorded one (whitespace squashed) with `from`, and turns Echo's into events; an Orchestrator's or session's chat turns Echo's resume and renew notes into events the same way.
A text nobody recorded was typed into the terminal, so the chat shows it as the human's.
`chat.read`, `chat.send` and `chat.interrupt` take `worker` (its number) in place of `agent`.
Why: Claude Code's transcript says only that the user typed something; the daemon is the one place that knows who did.

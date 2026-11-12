# `echoctl wait` prints a next step only for a question

Decided: 2026-11-11
Status: accepted

A message from `echoctl wait` ends with `-> echoctl reply <id> "<answer>"` when it is a question, because that command needs the message's id.
`done`, `blocker`, `exited`, `lost`, and `human` messages end with nothing: `orchestrator.md` already says what to do with each kind, and the Worker's id is in the message's first line.
Why: the line repeated the prompt's rules in every message the Orchestrator received, so they were paid for in its context each time.

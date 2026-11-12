# The Orchestrator hands planning reads to a hinata Worker

Decided: 2026-11-11
Status: accepted

`orchestrator.md` says planning that needs more than a few reads (tracing a flow, finding where a change goes) is a `hinata` Task, and the Orchestrator plans from its Final Report; the Orchestrator reads itself only the few files it needs to write a precise spec, each once.
This changes the line "You read code to plan" and keeps the rule that the Orchestrator never edits files.
Why: what the Orchestrator reads stays in its context and is paid for on every later wake; a Worker's reads are paid for once, on a cheaper model.
Rejected: forbidding reads entirely, which makes small Tasks slower than doing them.

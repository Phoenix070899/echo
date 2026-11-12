# A Worker with no branch of its own closes when its Final Report is delivered, unless started with --keep

Decided: 2026-11-11
Status: accepted

When `echoctl wait` hands the Orchestrator a `done` from a settled Worker that has no branch of its own and was not started with `--keep`, the daemon closes that Worker; the message says it was closed.
A Worker with a branch is kept, as in features/0042. `--keep` on `worker start` keeps a branchless Worker for its next Task.
Why: the Orchestrator's only step after a Final Report was `echoctl worker close`, one more tool call and one more wake-up of the model for nothing.
Rejected: closing at the moment of `echoctl done`, before the Orchestrator has read the report.

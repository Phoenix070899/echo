# The daemon verifies a writer started with --verify and the Orchestrator hears only the outcome

Decided: 2026-11-11
Status: accepted

`echoctl worker start --verify` marks a Worker whose Final Report, when its state is done, starts a `sasuke` Worker in the same worktree (`worker:<writer>`) with the writer's Task and Final Report; the Orchestrator is not told the writer is done yet.
The `sasuke` Worker begins its report with `Verdict: pass` or `Verdict: fail`; the daemon reads the first such line.
On `pass`, the Orchestrator gets one `done` message: the writer's Final Report and the verifier's. On `fail`, the writer gets one retry as its next Task, carrying the verifier's report verbatim; a second `fail`, a report with no verdict, or a verifier that did not finish is delivered to the Orchestrator with that outcome stated.
A writer that reports `blocked` is delivered at once, unverified. The verifier is closed when its verdict is in, and the Orchestrator never hears of it.
Why: each of those hops was a wake of the Orchestrator that only relayed text between two Workers.
Rejected: the Orchestrator starting `sasuke` by hand, which stays possible for a Worker started without `--verify`.

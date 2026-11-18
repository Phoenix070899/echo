# An Orchestrator's inbox showed other Orchestrators' questions

Found: 2026-11-18
Where: crates/hub/src/daemon.rs (`inbox`), crates/hub/src/main.rs (`echoctl inbox`, `echoctl brief`)
Fixed in: the change that adds this file

With several Orchestrators in one repo, `echoctl inbox` and the "Open questions" of `echoctl brief` listed the unanswered questions of every Orchestrator's Workers, so one Orchestrator could answer a question meant for another.
Cause: the `inbox` call took only the repo, while `wait` and `worker.list` were already scoped to the caller's `HUB_AGENT` (ADR 0006).
Fix: `inbox` takes an optional `agent` and keeps only that Orchestrator's Workers; `echoctl inbox` and `echoctl brief` pass `HUB_AGENT`.
Lesson: every daemon call an Orchestrator makes about Workers takes its `agent` and filters by it, the same way `list_workers` does.

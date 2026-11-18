# A Task spec names when the Worker must ask

Decided: 2026-11-18
Status: accepted

`orchestrator.md` has every Task spec carry an "Ask when" part, before "Start from".
It lists the concrete moments the Worker must stop and `echoctl ask` the Orchestrator instead of deciding: a file outside its ownership needs a change, a test fails for a reason the spec does not explain, code is not where the spec says, and any other risk this Task has.
The Orchestrator stays the planner for the whole Task: it answers these questions from its plan, as the listener already lets it.
Why: a Worker on a small model (Haiku) rarely asks on its own judgment and does the wrong thing confidently when the plan misses a case; a concrete rule makes it ask, so the planner fills the gap the plan left.
Verification (`--verify`) stays the net for what the Worker gets wrong without asking.
Rejected: relying on the worker contract's general "ask when blocked", which small models seldom act on; running every Worker on a large model, which costs several times more for Tasks a full spec already covers.

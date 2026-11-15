# An automatic Hand-off starts the next Member when a Task ends done

Decided: 2026-11-15
Status: accepted

This extends features/0086, which kept every Hand-off but the verifier a hint; it supersedes only its "neither is enforced for any Action except `verify`".
When a Worker started from a Member ends `done`, the daemon starts a Worker for each Member that Member has an automatic Hand-off to, as it starts a verifier (features/0055).
The new Worker belongs to the same Orchestrator, reports only to it, and is started with its Member's Profile and overlay (features/0084).
Its Task is the first Task of the chain, the Final Report of the Worker just before it, and its Member's own instructions; the daemon stores the chain's first Task with each Worker it starts this way, so a long chain does not grow its Task.
It works in the previous Worker's worktree when its Member's `worktree` is `"current"`, and in a new one otherwise.
A Worker that ends `blocked`, or that was started from a bare Profile or by the human, starts nothing.
When the Orchestrator already has `maxWorkers` Workers, the start is skipped and the Orchestrator is told which Member did not start after which Worker and why; nothing is queued.
The Orchestrator's "Your Workers" section writes a hint as "After `build`, consider `review`." and an automatic Hand-off as "After `build` ends done, the daemon starts `review` itself: do not start it for that Task."
Why: the human wants the drawn workflow to run as drawn where they say so, and the verifier already shows the daemon can carry out one Hand-off by itself; keeping the rest as hints leaves the Orchestrator's judgment where it was.
Rejected: making every Hand-off automatic, which turns the Orchestrator into a pipeline runner (features/0086); waiting for several incoming Workers before starting, which has no meaning when they had different Tasks; queuing starts over `maxWorkers`, which adds state the Orchestrator can hold instead; passing the whole previous Task down a chain, which grows with every step.

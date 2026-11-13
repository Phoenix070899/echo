# A Team's `rotateAt` is used as written, 0 turns renewal off, and the human's 100000 floor does not apply to it

Decided: 2026-11-13
Status: accepted

When an Orchestrator's Team sets `orchestrator.rotateAt`, that number is the context size at which the idle Orchestrator is renewed, exactly as written; the human's `orchestratorRotateAt` is then not read for that Orchestrator.
`rotateAt` of 0 in a Team turns renewal off for that Orchestrator, even when the human's setting has a number.
A Team that leaves `rotateAt` out leaves the human's `orchestratorRotateAt` in force, with its own floor of 100000 (`settings::MIN_ROTATE_AT`) as before.
A Team's `rotateAt` is valid when it is 0 or at least 10000; anything between is refused when the Team is saved and when it is used. The floor of 100000 stays on the human's setting only.
Why: a lean Team exists to renew early (`claude-lean` renews at 150000, and a faster setup may want less), which a floor meant to keep the human from renewing too often would silently undo; and "off" has to be sayable per Team, since a Team is the whole setup.
Rejected: clamping a Team's value up to 100000, which hides what the Team file says; reading 0 as "use the human's", which leaves no way for a Team to switch renewal off; a lower floor for the human's setting, which this does not change.

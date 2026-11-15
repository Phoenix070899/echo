# A Team's Members form a graph of Hand-offs hanging from its one Orchestrator

Decided: 2026-11-15
Status: accepted

Supersedes: features/0084's `parent` field, its depth limit of 3 and its rule that a `verify` Member's parent is an `execute` Member; features/0086's "first child whose Action is `verify`" and its reading of the Team as a tree. Everything else in both stands.
A Team is one Orchestrator and up to 24 Members joined by Hand-offs; a Hand-off runs from the Orchestrator or a Member to another Member and says what follows.
A Member's `parent` becomes `after`, a list of its incoming Hand-offs: `"after": [{"from": "build"}, {"from": "plan", "auto": true}]`.
`from` is a Member's `id`, or `"orchestrator"`, an id no Member may take; a Member without `after` hangs from the Orchestrator.
`auto: true` makes the Hand-off automatic (features/0093); it is absent or false for a hint.
A Member gains `x` and `y`, its place on the canvas in points, both optional; a Team without them is laid out by Echo.
A file that still has `parent` is read as `after: [{"from": <parent>}]`, and Echo writes `after` when that Team is next saved; Echo's own Teams in `teams/` are rewritten in the new form.
A Team is refused, when saved and again when used, if a `from` names no Member, if the Hand-offs form a loop, if a Member cannot be reached from the Orchestrator, if a Member has more than one automatic Hand-off coming in, if a Hand-off into a `verify` Member comes from a Member that is not `execute`, or if a Hand-off into a `verify` Member is automatic; the other refusals of features/0084 stand.
A Hand-off into a `verify` Member keeps the behaviour of features/0055 and 0086: a writer's verifier is the target of its first Hand-off, in file order, whose Member's Action is `verify`.
Removing a Member removes its Hand-offs; a Member left with none coming in is shown as unreachable and the Team cannot be saved until it has one.
Why: the human wants to draw Workers and the lines between them on a canvas, where one Member can follow two others (two writers feeding one runner), which a tree cannot hold; one node per Member keeps every line meaning one thing, what follows.
Rejected: separate Action and Profile nodes joined by lines, which would give lines two meanings; loops for retries, which the verifier's retry already covers; keeping the depth limit, which only fit the indented tree.

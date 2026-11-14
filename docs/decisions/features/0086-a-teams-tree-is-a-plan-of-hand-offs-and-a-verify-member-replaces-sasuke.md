# A Team's tree is a plan of hand-offs, and a verify Member replaces sasuke

Decided: 2026-11-14
Status: accepted

Supersedes: features/0055's "starts a `sasuke` Worker" and its retry message naming sasuke, when the Team has a verifier for that writer; with none, features/0055 stands as written.
A Team's tree is a plan that the Orchestrator and the daemon carry out; it is not nested delegation, so a Member never starts another Member and Workers still talk only to their Orchestrator.
A child of a Member says what follows it, and sibling order is the order the Orchestrator is told to prefer; neither is enforced for any Action except `verify`.
For a writer started with `--verify`, the verifier is the writer Member's first child whose Action is `verify`, started with its Profile and its overlay (features/0084), in the writer's worktree, as features/0055 says.
A writer with no such child, a writer that was not started from a Member, and a Team without Members keep `sasuke`, as today.
The retry message to the writer names the verifier that ran, by its Member id, and not "sasuke".
The Team's `rules.review`, when it is set, decides whether `--verify` verifies for that Orchestrator's Workers; when the Team leaves it out, the human's setting decides. Before this, only the human's setting did, and a Team's `review` shaped the Orchestrator's prompt only; the daemon now follows the prompt, and this is recorded as a bug in `docs/bugs/`.
For a Team with Members, the Orchestrator's prompt gets a generated "Your Workers" section after the rules and before the Team's `instructions`: one line per Member (id, Action, the Profile's description, the model), the hand-offs of the tree as sentences, the start command, and the rule to start Workers by these ids. A Member's role text is not copied into it.
A Team without Members adds nothing to the prompt.
Why: the Worker Contract and CONTEXT.md say a Worker hears only from its own Orchestrator, and nested delegation would need a new message path, a new concurrency story and a new ADR; a plan the Orchestrator reads gets the human's tree without any of that, and the verifier is the one hand-off the daemon already runs by itself.
Rejected: Members starting Members, which can be built later on the same file format; making every child an enforced step, which would turn the Orchestrator's judgment into a fixed pipeline; keeping the hard-wired sasuke, which leaves a `verify` Member in the tree that does nothing; keeping the human's setting alone for `--verify`, which makes a Team's `review: false` verify anyway.

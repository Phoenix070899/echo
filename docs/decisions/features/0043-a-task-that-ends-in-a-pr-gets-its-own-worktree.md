# A Task whose change goes up as its own PR gets its own worktree, and so keeps its Worker

Decided: 2026-10-31
Status: accepted

The Orchestrator gives a writing Worker its own worktree when its change goes up as its own PR, whether or not another writer is active; the spec's acceptance names the branch and the PR.
That Worker then keeps its branch until it is merged or dropped (features/0042); Tasks that do not end in a PR keep the old worktree rules and get a new Worker each time.
Why: the Orchestrator cannot tell a long Task from a short one up front, but it knows whether a change becomes a PR; and a lone feature worked in place had its Worker closed after its first report, losing its context for the review and CI rounds that follow.

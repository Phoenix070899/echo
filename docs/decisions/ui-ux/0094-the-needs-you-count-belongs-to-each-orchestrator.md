# The needs-you count sits on each Orchestrator, not on the repo

Decided: 2026-11-13
Status: accepted

Supersedes: ui-ux/0093, only where an agent showed a ring for what waits on it.
The amber count is on the agent's own line in the sidebar: how many of its Workers, or it itself, wait on the human. An agent with nothing waiting shows none. The repo's line carries no count, and the ring for an agent is dropped. A Worker's own row keeps its amber target (ui-ux/0092).
The collapsed rail still shows the repo's total.
Why: the human works one Orchestrator at a time, and a single number for the whole repo did not say which one to open.

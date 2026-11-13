# What waits on you is a ring in the sidebar, not a card

Decided: 2026-11-13
Status: accepted

Supersedes: ui-ux/0084, only where a Worker's question or prompt showed as buttons under its agent.
The sidebar no longer lists cards for what waits on the human ("w942 is idle", a question, a permission prompt, with Open or answer buttons). A Worker that waits shows on its own row with the amber target (ui-ux/0092).
An agent shows the same target at the right of its own line when it asks itself (a permission prompt) or when its Workers are folded away; its tooltip says how many wait. The repo's amber count stays.
Answering a question or approving a prompt happens in the Orchestrator's chat or the Worker's panel, which the row opens.
Why: the human reads and acts from the Orchestrator, and the cards made the tree tall and loud.

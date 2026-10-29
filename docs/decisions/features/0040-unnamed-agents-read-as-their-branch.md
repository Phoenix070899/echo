# An unnamed agent reads as its branch

Decided: 2026-10-29
Status: accepted

Adds to features/0004: until a name is given or the first request names it, an Orchestrator, Claude Code session, or Terminal shows as the branch it works on: the one picked or made for it, else the branch checked out where it works.
Only on a detached HEAD does it fall back to "Orchestrator a3" and the like.
The branch is a stand-in, not a stored name, so the first request still names the agent, and a Rename or issue name still wins.
`echoctl sessions` shows the same.
Why: the human wanted new Orchestrators and Terminals named after their branch by default.

# Agents drive Echo's window with `echoctl ui`, and Echo never comes to the front for it

Decided: 2026-10-27
Status: accepted

`echoctl ui open <path>[:line]`, `show <w12|a3>`, `diff <w12>`, `notify "<text>"`, and `orchestrator [--branch | --new-branch [--base]]` let an agent change what Echo shows.
The CLI asks the daemon, which keeps each request for 30 seconds in the repo's snapshot; Echo acts on each one once, and only on those made since it started, so a relaunch replays nothing.
Echo changes its selection, tab, or Worker view, but never activates itself; only a click on a notification brings it forward.
A request fails with "Echo is not open on <repo>" while no Echo window follows that repo, so the agent can say so in words; `orchestrator` still starts the Orchestrator then.
Opening a file selects the agent or Worker that works in that file's checkout, the asking one first, as file tabs belong to the selected checkout.
The `echoctl:echo` skill teaches these commands, from the skills-only plugin in `skills/` that Orchestrators and Normal sessions load; Workers do not, as they report through their Orchestrator.
A Normal session gets only that plugin, not the Orchestrator's view in `mod/`, so it otherwise stays plain Claude Code.
Why: the human wanted agents to point at things in Echo instead of describing them.
Rejected: a separate socket or URL scheme into the app, because Echo already follows each repo's events stream.

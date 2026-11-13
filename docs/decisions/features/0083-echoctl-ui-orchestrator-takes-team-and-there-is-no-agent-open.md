# `echoctl ui orchestrator --team <name>` is the command-line way to start an Orchestrator with a Team

Decided: 2026-11-13
Status: accepted

`echoctl ui orchestrator` takes `--team <name>` (a name from `echoctl team list`), as it takes `--branch`, `--new-branch` and `--base` (features/0033); the Orchestrator then starts and resumes with that Team (features/0081).
The daemon's `agent.open` method takes the same `team`, which is how Echo's New session sheet and a phone pass it. There is no `echoctl agent open` command, and none is added for Teams.
`echoctl team` only lists and shows Teams; it does not start anything.
Why: `echoctl ui orchestrator` is where an Orchestrator is started from the command line today, so the Team rides on it instead of making a second way to start one.
Rejected: an `echoctl agent open` command, which would be a second entry beside `ui orchestrator` that has to keep the same options; `echoctl team start <name>`, which would split starting an Orchestrator across two commands.

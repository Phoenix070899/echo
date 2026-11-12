# The daemon runs one side shell per checkout, named by the hex of its path

Decided: 2026-11-12
Status: accepted

`terminal` accepts `{"side": "<checkout path>"}` and attaches to that checkout's side shell, starting it in the folder if it is not running.
`side.status` returns whether the shell runs and whether it printed in the last 1.5 s; `side.stop` forgets the shell and kills it.
The holder keeps the shell under the key `t` plus the lowercase hex of the canonical path, so a restarted daemon adopts it again (`recover()` reverses the key); `shutdown --force` kills side shells with the agents.
A shell that exits is forgotten, so the next attach starts a new one.
Why: the app's side terminal (ui-ux/0089) must outlive the app and the daemon like any agent's terminal (ADR 0009), and the phone may use it later.

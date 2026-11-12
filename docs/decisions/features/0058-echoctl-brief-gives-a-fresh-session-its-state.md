# echoctl brief gives a new or resumed Orchestrator session its state

Decided: 2026-11-11
Status: accepted

`echoctl brief` prints, for this repo: Workers running or waiting (id, profile, state, branch, title, any blocker, quiet time), Workers settled and still open with the first line of their Final Report, and open questions.
`orchestrator.md` starts with it instead of `worker list`, for a fresh session and a resumed one alike.
Why: a session that starts over, or after a clear, otherwise rebuilds this from several commands and from reading old reports; the daemon already holds all of it.
Rejected: injecting the brief into the prompt at launch; it would be stale by the time the session reads it.

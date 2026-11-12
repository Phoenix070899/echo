# An idle Orchestrator is renewed on a new session when its context passes a size the human sets

Decided: 2026-11-11
Status: accepted

`orchestratorRotateAt` in `settings.json` is a context size in tokens; absent or 0 means off, and a value under 100000 is raised to 100000. It is off by default.
When it is on, the daemon renews an Orchestrator that has sat with an unchanged screen at its input box (idle, or waiting on its own listener) for two minutes, has no Worker running, no undelivered message and no open question, has made at least 20 requests, and whose last request's context from Claude Code's transcript is at or above the size. The transcript is measured at most every ten minutes.
Renewing gives the agent a new Claude session id, stops its terminal and starts it again with the first message "Your session was renewed ... Run `echoctl brief`"; the old session stays in Claude Code's history and can be resumed by hand.
`agent.renew` does the same on request, for any Orchestrator.
Why: an Orchestrator's cost is its context re-read on every wake; the 14-day baseline had a median of 176k per request and one session at 363k, with the daemon already holding all the state a new session needs (features/0058).
The human's conversation with that Orchestrator before the renewal is not in the new session; that is the price, and why the setting is off unless chosen.
Rejected: renewing at a fixed size without a setting, which would drop the conversation of every human without asking; renewing while Workers run, which would cut the listener a Worker's message depends on.
Not built: a control in Echo's Settings (Swift), and a way to renew by hand from `echoctl`.

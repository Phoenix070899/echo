# Whether the Orchestrator starts with the repo's Lessons is a setting, on by default

Decided: 2026-11-11
Status: accepted

`orchestratorLessons` in `settings.json` (true or false) decides whether an Orchestrator's prompt includes the repo's Lessons; without it, or if it is not a boolean, they are included as before.
`settings.set` takes it and `settings.get` returns it. Workers always get the Lessons.
Why: the Lessons are mostly about how to write code, which the Orchestrator does not do, and they are in its context for every wake; the human can try it off and see in `echoctl stats` what it saves.
Rejected: turning it off by default before the numbers show the cost.
Not built: a control in Echo's Settings, which needs the Swift build on the Mac.

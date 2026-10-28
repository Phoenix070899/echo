# The Orchestrator's rules that people differ on come from Settings, as overrides after orchestrator.md

Decided: 2026-10-28
Status: accepted

Four rules can be changed in `settings.json` in the daemon's state (Settings, Agents): at most how many Workers run at once (1 to 16, default 4), waiting for the human's "go" before a Task that writes code, a `sasuke` review after each writing Worker, and merging a verified branch without asking.
`orchestrator.md` keeps the defaults as they are; an Orchestrator's prompt adds a "The human's Settings" section after it naming only the rules that differ, each saying what it replaces.
They apply to Orchestrators started or resumed after a change; anything else the human wants goes in their Preferences.
The same file holds the default `cli` and `model` (features/0036); `settings.set` refuses any other key and an unknown CLI.
Why: these were the author's own rules, and people using Echo will want them differently.
Rejected: an editable `orchestrator.md` per person, which every Echo update would break.

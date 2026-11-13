# A forced CLI overrides every Profile's own CLI and model

Decided: 2026-11-13
Status: accepted

Supersedes: features/0036's order of levels, only when `forceCli` is on; with it off the order stands.
`"forceCli": true` in `settings.json` (the human's, or a repo's `.echo/settings.json`) makes the `cli` and `model` set there apply to every agent over a Profile's own `cli` and `model`.
What is picked for one agent or one Worker (`echoctl worker start --cli --model`, an agent's own CLI and model) still wins over it, and `orchestratorModel` still sets Orchestrators' model.
With `forceCli` on and no `cli` set, nothing is forced; with a `cli` but no `model`, the agent runs the CLI's own default, since a Profile's model may name another CLI's models.
`echoctl profile list` and the Settings screen show what a Profile runs with after the force, and Settings has a switch for it beside the CLI.
Why: the shipped Profiles say `cli: claude`, so with Kiro chosen in Settings an Orchestrator's Workers still started on Claude, which has no usage left; the human wants one switch, not an edit of six Profiles.
Rejected: removing `cli` from the shipped Profiles, whose models name Claude's and are refused by Kiro; a different CLI per Profile in Settings only, which leaves new Profiles on Claude.

# Orchestrators start on Opus 5.5 at high effort unless Settings say otherwise

Decided: 2026-11-11
Status: accepted

An Orchestrator's model is, from the highest: the model picked for that agent, `orchestratorModel` in `settings.json`, the repo's `.echo/settings.json`, the human's general `model`, then `anthropic/claude-opus-5-5`; the last applies only to the `claude` CLI, and only when none of the others is set.
Its effort is `orchestratorEffort` in `settings.json` (low, medium, high, xhigh, or max), else `high`; Normal sessions and Workers are not changed.
`settings.set` takes both keys, refuses an effort Claude Code does not take, and an empty string puts the default back; `settings.get` returns both.
They apply when an Orchestrator is started or resumed, so a resumed session now runs on this model and effort too.
This adds a level and a default to the model order of features/0036 for Orchestrators; that decision stands, and Workers keep its order.
Why: until now an Orchestrator ran on whatever Claude Code's own default was, with no effort passed (`Start.effort` was never set for it); the human chose Opus 5.5 at high effort as the default.
Rejected: changing the general `model` default, which would move Workers too; no built-in default, which leaves the Orchestrator's model to the CLI's version of the day.
Not built: a control for these two settings in Echo's Settings > Agents, which needs the Swift build on the Mac.

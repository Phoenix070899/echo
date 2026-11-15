# A model is picked from the CLI's own list, not typed

Decided: 2026-11-15
Status: accepted

Every model field in Settings (Defaults, a Team's Orchestrator and Workers, Profiles set apart, a Member) is a Foundry picker of the models its CLI offers, named as Echo names them, plus an empty choice that leaves the model to the level below.
The daemon's `models` method lists them: Codex from `codex debug models` (the ones its picker lists), Kiro from `kiro-cli chat --list-models --format json`, both on Echo's own login while it is signed in.
Claude Code has no command that lists its models, so its picker's three (Opus, Sonnet, Haiku 5.5) are written in `models.rs`, after the extra ones its `.claude.json` caches for the account (`additionalModelOptionsCache`, such as Fable 5.1).
The daemon keeps the lists ten minutes; a list that failed is asked for again on the next call.
A model set before that the CLI does not list stays picked, under its own id.
Why: a typed name was easy to get wrong (`anthropic/claude-haiku-5.5` for `anthropic/claude-haiku-5-5`), and the Worker failed to start only later.

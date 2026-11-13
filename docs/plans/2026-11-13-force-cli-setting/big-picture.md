# Big picture: one switch that runs every agent on the chosen CLI

Status: approved by the human ("go"), 2026-11-13. Decision: `docs/decisions/features/0075-a-forced-cli-overrides-every-profiles-own-cli-and-model.md`. Follows the Kiro plan in `../2026-11-13-kiro-cli-provider/`.

## Why
With Kiro chosen in Settings, an Orchestrator's `echoctl worker start naruto` still starts a Claude Worker, because a Profile's `cli` outranks `settings.json` and the shipped Profiles say `cli: claude`. The human's Claude usage is out, so every Worker must follow the chosen CLI without editing Profiles.

## Goals
1. `"forceCli": true` in the state `settings.json` or a repo's `.echo/settings.json` applies the `cli` and `model` from those files to every agent over a Profile's own, as decision 0075 says. Explicit per-agent and per-Worker picks still win; `orchestratorModel` still applies.
2. `settings.get` / `settings.set` carry `forceCli`; `echoctl profile list` shows what each Profile runs with after the force.
3. Settings has a switch for it beside the CLI picker, with a one-line explanation.
4. Proven with a short real run on Kiro (`claude-haiku-5.5`): with `{"cli":"kiro","model":"claude-haiku-5.5","forceCli":true}`, `echoctl worker start --profile naruto` without `--cli` starts a Kiro Worker.

## Non-goals
Changing the Profile files; the chat tab, usage or stats for Kiro; the resume-loses-its-Task problem (a separate item); any per-session picker.

## Constraints
As in `../2026-11-13-kiro-cli-provider/big-picture.md`: obey the decisions in force and never edit a committed one; bugs found get a `docs/bugs/` file; `~/.cargo/bin/cargo test -p echoctl` and `cargo fmt --check`; `make -C app test`; isolated `HUB_STATE=/tmp/hubk` for any daemon run, never the human's daemon, repos or tmux; `~/.kiro` is the human's (add and remove only `echo-*.md` agent files); real Kiro runs use `claude-haiku-5.5` and stay short. The disk is nearly full (about 470 MB free): do not create big files, run `cargo clean` only in a scratch copy, never delete `target/` or `app/.build/`; if a build fails with "no space", report it.
Commit messages `Daemon: ...`, `Echo: ...`, `Docs: ...`; no attribution, no em dashes; never push, amend or rebase.

## Acceptance
Rust and Swift suites pass; new unit tests cover the force cases; the smoke run's evidence is in the task report; the tree is clean at the end.

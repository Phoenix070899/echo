# Big picture: Teams, a named setup for an Orchestrator, its Workers and its rules

Status: requested by the human on 2026-11-13 ("many profiles with an orchestrator, subagents underneath; select one when creating a session; in a profile customise the orchestrator model, subagent model and behaviours, or create a new one"); the questions below were left to the recommended options, which are stated here. Decision: `docs/decisions/features/0081-a-team-is-a-named-setup-for-an-orchestrator-its-workers-and-its-rules.md` (read it first; it fixes the file format and the order of levels).

## Why
The Orchestrator feels sluggish. Echo's Orchestrators default to Opus 5.5 at high effort, and a session in this project runs at a median 260k tokens of context per request, up to 466k. Echo has no screen for the Orchestrator's model, effort or renewal threshold, so the human cannot adapt it per provider; and the Worker models live in six Profile files that name Claude's models. A Team lets one choice at session start set the planner's model and effort, the Workers' models (all, or per Profile), and the Orchestrator's rules, and lets the human keep several (lean for speed, thorough for hard work, one per provider).

## Choices made for the human's open questions (recommended options)
- The word is **Team** (the word Profile already means a Worker's role). Added to CONTEXT.md.
- Three levels of files like Profiles (shipped, `~/.echo/teams/`, a repo's `.echo/teams/`), edited in Settings; shipped Teams are read-only and can be duplicated.
- Shipped Teams: `claude-opus` (today's behaviour: Opus 5.5 at high, Workers by their Profiles), `claude-lean` (Orchestrator Sonnet 5.5 at medium, renew at 150000 tokens, Workers by their Profiles), `kiro-lean` (Orchestrator on Kiro `claude-sonnet-5.5` at medium; Workers on Kiro `claude-haiku-5.5` at low, `naruto` and `sasuke` on `claude-sonnet-5.5` at high and medium). The New session picker's default is `claude-opus` for an unchanged first experience; it remembers the last Team used.
- A Team applies to Orchestrators only at start/resume; Normal sessions and Terminals have none.
- "Behaviours" means: `rules` (maxWorkers, planApproval, review, mergeWithoutAsking), `rotateAt` and free-text `instructions`. Nothing else is configurable in v1.
- Context renewal (`rotateAt`) works for Claude Orchestrators today and not yet for Kiro (it reads Claude transcripts): the Settings screen says so when a Kiro Orchestrator is chosen.

## Goals
1. Team files: parse, validate, load from the three levels, save and delete the human's and a repo's, with shipped seeds.
2. An agent stores its Team (`agents.team`); an Orchestrator starts and resumes with its Team's CLI, model, effort, rules, `rotateAt` and instructions; its Workers (and the verifiers and fan-out tries it starts) resolve CLI, model and effort in the order of decision 0081.
3. `agent.open` takes `team`; `team.list`, `team.get`, `team.save`, `team.delete` exist; `echoctl team list|show` prints them; `echoctl profile list` can show what each Profile runs with under a Team (`--team <name>`).
4. The New session sheet has a Team picker (Orchestrator mode); the agent's row tooltip and header name its Team.
5. Settings has a Teams page: list, create, duplicate, delete, and edit every field of decision 0081, with the model fields validated against the chosen CLI.
6. A real run on Kiro (`claude-haiku-5.5`/`claude-sonnet-5.5`, short): an Orchestrator started with `kiro-lean` runs on Kiro with the Team's model and effort, and a Worker it starts runs with the Team's Worker model.

## Non-goals
Stats and renewal for Kiro; Teams for Normal sessions; per-repo default Team (the picker remembers the last one); changing Profile files; mixing settings from several Teams; Echo Remote UI for Teams (the phone can pass `team` to `agent.open` but gets no editor).

## Constraints
As in `../2026-11-13-kiro-parity/big-picture.md`: obey decisions in force and never edit a committed one (supersede with a new file; new decisions numbered after 0081 in `docs/decisions/features/` and the latest in `ui-ux/`); a bug found gets a `docs/bugs/` file; `HUB_STATE=/tmp/hubk` for any daemon run; `~/.kiro` is the human's (only `echo-*.md` agent files may be added and removed, run real Kiro with `KIRO_HOME` set to a scratch dir only where it needs no login, otherwise note what was written); real Kiro runs on `claude-haiku-5.5` or `claude-sonnet-5.5`, short; the human's running daemon, Echo and Kiro are not to be touched; do NOT run `make -C app app` (it replaces the running Echo; use `swift build --product HubApp` in `app/`); do not delete `target/` or `app/.build/`; follow the UI rulebook of this repo's decisions (`docs/decisions/ui-ux/`, Claude's design language, `Ledger` tokens only); commit prefixes `Daemon:`/`Echo:`/`Docs:`, no attribution, no em dashes, never push, amend or rebase.

## Acceptance
fmt, `~/.cargo/bin/cargo test -p echoctl` and `make -C app test` pass; new tests cover Team parsing and validation, the three levels, every step of the resolution order (including `forceCli` interplay and a resumed session re-reading an edited Team), the rules/instructions merge into the Orchestrator prompt, `agents.team` migration on an existing database, and the Swift decoders and form state; the smoke run (T08) is quoted in the report; the tree is clean at the end apart from this plan's `status.md`.

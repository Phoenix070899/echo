# Big picture: Kiro CLI as a third agent CLI in Echo

Status: approved by the human ("go", then "approve all"), 2026-11-13.
Decision: `docs/decisions/features/0068-kiro-runs-as-a-third-agent-cli.md`.

## Why

The human's Claude usage ran out. Kiro offers Claude (and GPT and other) models on separate credits, and `kiro-cli` is installed and signed in. Echo should be able to run its Orchestrators, Normal sessions and Workers on Kiro so work continues in Echo, with the ledger, Worker rows, Needs-you counts and terminals working as they do for Claude and Codex.

## Goals (milestone 1, this plan)

1. `cli: kiro` runs an Orchestrator, a Normal session and a Worker on `kiro-cli chat --v3`, from a Profile, `settings.json`, the Settings CLI picker, or `echoctl worker start --cli kiro`.
2. The Worker Contract, Preferences, Lessons and the Profile's role reach the Kiro agent as its system prompt; the folders it needs outside its checkout (the echo hub dir and the memory dir) are readable and writable by it without a prompt.
3. The daemon learns each Kiro session's id from a hook, resumes with `--resume-id`, and sees the states Working, Waiting, Idle, permission prompt from Kiro's screen, so Worker rows, Needs you, idle blockers, `decide` (approve/deny) and `chat.send` work.
4. A Worker on Kiro can reach a Final Report with `echoctl done`, and an Orchestrator on Kiro can start Workers and hear from them (`echoctl wait`), proven by a real smoke run on a cheap model.
5. The Settings screen offers Kiro; labels and model names read correctly for Kiro agents.

## Non-goals (not in this plan)

- The chat tab for Kiro sessions (milestone 2), per-provider usage and stats (milestone 3), Orchestrator renewal by context size on Kiro. These show as unsupported or "not counted", as for Codex. They get their own plans after this one ships.
- Driving Kiro over ACP, Kiro's cloud sessions, Kiro Crew, Kiro specs or workflows.
- A per-session CLI picker in the New session sheet (the Settings picker, Profiles and `--cli` are enough).
- Changing the human's own `~/.kiro` agents, steering or settings. Echo only adds `~/.kiro/agents/echo-*.md` files.
- Changing Claude's or Codex's behaviour.

## Constraints

- Obey the decisions in force; to overrule one add a new decision file, never edit a committed one. `docs/decisions/README.md` has the format. A new choice a later session could undo by accident gets its own decision file in the same change (the next number in `docs/decisions/features/` after 0068).
- Bugs found or fixed get a file in `docs/bugs/` (`docs/bugs/README.md`).
- Never test against the human's daemon, repos or tmux sessions: use `HUB_STATE=/tmp/hubk` (short), a throwaway repo whose folder name differs from any real one, and `HUB_TEST_AGENT=crates/hub/tests/fake-agent.sh` for daemon tests. A test that starts a real `kiro-cli` spends the human's credits: use `claude-haiku-5.5` (0.06x) and keep runs short.
- Rust: `~/.cargo/bin/cargo test -p echoctl` and `~/.cargo/bin/cargo fmt --check` must pass. Swift: `make -C app test` (plain `swift test` misses the macro plugin). Only Command Line Tools are installed: no `@State`.
- Commit messages: `Daemon: ...` for Rust, `Echo: ...` for the app, `Docs: ...` for docs; no attribution lines, no em dashes. Commit on the current branch; never push, amend or rebase.
- Never touch `~/.kiro/agents/{hinata,ino,jiraiya,kakashi,naruto,sasuke,shikamaru}.md`, `~/.kiro/settings`, or any existing file under `~/.kiro`, except to add `echo-*.md` agent files and, for the spike only, `echo-spike-*.md` files that it deletes afterwards.

## Acceptance criteria

1. `~/.cargo/bin/cargo test -p echoctl` and `cargo fmt --check` pass; new unit tests cover the Kiro arm (`parse`, `model_arg`, `args` for an Orchestrator, a Worker and a resume, `has_session` with a temp `KIRO_HOME`, the content-named agent file, the screen readers on the captured fixtures, the hook handling).
2. `make -C app test` passes.
3. `docs/research/kiro-cli-spike.md` records the spike's answers with evidence, and the screen fixtures it captured are in `crates/hub/tests/fixtures/kiro/`.
4. The smoke run (task T08) shows, in its own report: a Kiro Worker started with `echoctl worker start --cli kiro --model claude-haiku-5.5` in a throwaway repo under a throwaway `HUB_STATE` reaches `state=done` with a Final Report; a Kiro Orchestrator receives that Worker's message through `echoctl wait`.
5. Decision 0068 is committed; README and CONTEXT mention Kiro where they name the CLIs; `git status` is clean at the end.

## Risks

- Kiro's screen text and keys are undocumented: mitigated by the spike capturing real screens first; the readers are written against fixtures, and any difference found later is a bug file plus a fixture.
- An Orchestrator is woken by a background `echoctl wait` on Claude Code. If Kiro's shell tool cannot do that, T05 changes the Kiro prompt addendum (foreground `echoctl wait` with a timeout, looped); if Kiro cannot wait at all, milestone 1 ships Workers and Normal sessions on Kiro and the Orchestrator stays on Claude (the plan reports it).
- The hook environment: if Kiro's hook does not inherit `HUB_WORKER`/`HUB_AGENT`, T04 passes them in the hook command line instead.
- Credits: the smoke run and the spike use Haiku and short prompts.

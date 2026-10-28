# Echo

Echo lets one person direct a team of coding agents from one window.
You talk to an Orchestrator.
It splits the work into Tasks, hands each Task to a specialised Worker, and reports back.
You can also open a plain Claude Code session next to it.

Two parts:

- **The Echo app**: a native macOS app (`app/`, Swift) that shows every agent of a repo in one ledger and one terminal.
- **Hub Daemon and `echoctl` CLI**: a Rust program (`crates/hub/`) that owns each Worker's terminal, worktree, and messages, so Workers outlive the Orchestrator and the app.

The domain words (Orchestrator, Worker, Task, Needs you, Final Report, and the rest) are defined in [`CONTEXT.md`](CONTEXT.md).

## Echo

![The ledger and an Orchestrator's terminal: Needs you, Running, Done](docs/screenshots/Working.png)

![A Final Report read as a document](docs/screenshots/FinalReport.png)

![The Files column beside the terminal](docs/screenshots/Files.png)

![Rendered Markdown with notes to send to the agent](docs/screenshots/FileMarkdown.png)

Echo has one tab per repo.
Under each agent the ledger groups what is **Needs you**, **Running**, and **Done**.
Needs you is the only place that uses the highlighter colour, so a waiting question or permission prompt is never missed.

- Approve, Deny, or answer a Worker's question without leaving the ledger.
- Open any Worker's terminal, review its diff, or send it an Intervention.
- Read a Worker's Final Report as a document.
- Browse the agent's checkout, preview files, and leave notes on rendered Markdown for the agent.
- Start an agent from a branch or a GitHub issue; fan out and keep one.
- Menu bar view and notifications when something needs you.
- Terminal runs inside your own tmux or screen; a background image with dim and blur is optional.

## How a Hub Session works

```
you  ->  Orchestrator  ->  Worker (naruto: implement)
                       ->  Worker (sasuke: verify)
                       ->  Worker (lee: run commands)
     <-  Summary: Needs you / Done / Running
```

1. You describe the work to the Orchestrator.
2. It shows a plan and waits for your "go" before any Task that writes code.
3. It starts Workers with `echoctl worker start <profile> --spec-file <file>`, in place or in their own worktree, at most 4 at once.
4. Each Worker does exactly one Task and ends with `echoctl done`, a Final Report that says done or blocked, what changed, and how it was verified.
5. A `sasuke` Worker verifies every writing Worker's commits before the Orchestrator reports.
6. A Worker that is blocked runs `echoctl ask`; the question reaches the Orchestrator, or you.

Rules for the Orchestrator are in [`orchestrator.md`](orchestrator.md).
Rules every Worker follows are in [`worker-contract.md`](worker-contract.md).

## Agent Profiles

A profile is a CLI-neutral Markdown file in [`profiles/`](profiles/): which agent CLI, model, effort, tools, and role a Worker starts with.

Echo ships the ones below in [`profiles/`](profiles/). Yours, in `~/.echo/profiles/`, and a repo's, in its `.echo/profiles/`, replace one of the same name whole.

```
echoctl profile list               every Profile here, and where each comes from
echoctl profile copy sasuke        your own copy to change ("--repo" for this repo's, shared through git)
echoctl profile new code-reviewer  a blank Profile to fill in
```

A Profile's `cli` and `model` (`provider/model`) can be left out: they then come from the repo's `.echo/settings.json`, else `~/.echo/settings.json` (`{"cli": "claude", "model": "anthropic/claude-sonnet-5-5"}`), else claude's own default.
`echoctl worker start --cli --model` overrides all of them for one Worker.
The CLIs are `claude` (Anthropic models) and `codex` (OpenAI models, as `openai/<model>`).

| Profile | Role |
| --- | --- |
| `naruto` | Implementer: one coding Task, runs its verify command |
| `sasuke` | Verifier: reviews a writer's commits, read-only |
| `hinata` | Codebase analyst: read-only analysis for planning |
| `jiraiya` | Web researcher: cited answers from primary sources |
| `lee` | Command runner: tests, builds, git, scripts |
| `ino` | Scribe: keeps your Preferences and each repo's Lessons tidy |

## The `echoctl` CLI

```
echoctl                      open the Orchestrator working in this checkout
echoctl a10                  open a named agent
echoctl attach <w12|a3>      make this terminal a Worker's or an agent's terminal (Ctrl-] detaches)
echoctl status               dashboard rows for this repo's Workers
echoctl sessions             repos the daemon knows, each with its agents
echoctl daemon | shutdown    run or stop the Hub Daemon
echoctl profile <action>     see and change the Agent Profiles Workers start as
echoctl ui <action>          have Echo open a file, show an agent or a diff, notify, or start an Orchestrator
                             (agents learn it from the echoctl:echo skill in skills/)

Orchestrator:  echoctl worker start|list|read|send|key|close|resume, echoctl wait, echoctl reply, echoctl inbox
Worker:        echoctl ask, echoctl send, echoctl done
```

The daemon starts on the first `echoctl` command and keeps running.
It stores Tasks and each Worker's Claude session id, so a Worker lost to a crash is resumed, not restarted.

## Build and run

Requirements: macOS 26, Rust (stable), Swift (Command Line Tools), `tmux` (default multiplexer), and the [Claude Code](https://claude.com/claude-code) CLI.

```sh
# Rust daemon and CLI
cargo build --release          # target/release/echoctl
cargo test
cargo fmt --check

# Echo
make -C app app                # builds app/build/Echo.app
make -C app test
make -C app run
```

Put `target/release/echoctl` on your `PATH`, then run `echoctl` inside any git repo.

State lives in `~/.echo` (state from before the rename moves there on its own, leaving `~/.agent-hub` as a link); set `HUB_STATE` to use another folder.
`ECHO_REPO` points at this repo when the binary runs from somewhere else.

To try the daemon without a real agent, set `HUB_TEST_AGENT=crates/hub/tests/fake-agent.sh`.

## Layout

| Path | What |
| --- | --- |
| `app/` | Echo: `HubCore` (daemon client, models) and `HubApp` (SwiftUI views) |
| `crates/hub/` | Hub Daemon and `echoctl` CLI |
| `profiles/` | Agent Profiles |
| `mod/` | Claude Code plugin: folds tool calls and shows the Worker Dashboard in the Orchestrator's terminal |
| `settings/` | Settings applied to Workers |
| `docs/adr/` | Architecture decisions |
| `docs/decisions/` | Decisions about how Echo looks and behaves, and what it does |
| `docs/design/` | Early layout explorations |

## Decisions

Every change obeys the decisions in force.
Read [`docs/decisions/README.md`](docs/decisions/README.md) for the rules and the format.
A committed decision file is never edited; a new file supersedes it.

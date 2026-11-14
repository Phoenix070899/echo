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
3. It starts Workers with `echoctl worker start <member-or-profile> --spec-file <file>`, in place or in their own worktree, at most 4 at once.
4. Each Worker does exactly one Task and ends with `echoctl done`, a Final Report that says done or blocked, what changed, and how it was verified.
5. A verifier (its Team's `verify` Member, else `sasuke`) checks every writing Worker's commits before the Orchestrator reports.
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

A Profile is a Worker's role. A Team's Member starts from a Profile and may change it for that Team alone (see Teams below), so two Workers of one Profile can differ without editing the shared file.

A Profile's `cli` and `model` (`provider/model`) can be left out: they then come from the repo's `.echo/settings.json`, else `~/.echo/settings.json` (`{"cli": "claude", "model": "anthropic/claude-sonnet-5-5"}`), else claude's own default.
`echoctl worker start --cli --model` overrides all of them for one Worker.
With `"forceCli": true` beside a `cli` in `settings.json` (or a repo's `.echo/settings.json`), that `cli` and `model` come before a Profile's own for every agent, so one switch runs everything on, say, Kiro; a pick for one Worker still wins.
The CLIs are `claude` (Anthropic models), `codex` (OpenAI models, as `openai/<model>`) and `kiro`.

`kiro` runs `kiro-cli chat --v3`, so it needs `kiro-cli` installed and signed in; your Kiro credits pay for it.
Kiro names models its own way: a bare id such as `claude-sonnet-5.5` (a dot, not a dash), or `kiro/<id>`; `kiro-cli chat --list-models` lists them.
Another provider's `provider/model` form, like `openai/gpt-5`, is refused with a message naming it, and the start fails before a worktree is made.
With `{"cli": "kiro", "model": "claude-sonnet-5.5"}` in `settings.json`, also set `orchestratorModel` to a Kiro id: an `anthropic/...` value is refused for a Kiro Orchestrator.
Echo gives a Kiro agent its prompt, folders and hooks through a generated agent file, `~/.kiro/agents/echo-<hash>.md`; the name comes from the file's content, and the files are small and safe to delete.
A Kiro Worker's allow and deny rules sit in that file; a Kiro Orchestrator may run `echoctl` commands without asking and is asked about everything else.
Kiro Orchestrators wait for their Workers with a foreground `echoctl wait` they run again, since Kiro has no background command to wake them.
While `kiro-cli` is installed and signed in, the daemon's `usage` reply adds a "Kiro credits" entry beside Claude's limits (credits used of the plan, percent, billing-cycle reset), read every five minutes from a short-lived `kiro-cli acp` run that starts no session and spends nothing.
It runs with its own `KIRO_HOME` under the state folder, so `~/.kiro/logs` is left alone; when a reading fails the last good one stays, and nothing shows when Kiro is missing or signed out.
Kiro has no stats and no Orchestrator renewal by context size; they show as not counted.

A repo's `.echo/settings.json` can also prepare new worktrees: `"copy": [".env"]` copies files git ignores from the main checkout, and `"setup": "pnpm install"` runs before the agent starts.

| Profile | Role |
| --- | --- |
| `naruto` | Implementer: one coding Task, runs its verify command |
| `sasuke` | Verifier: reviews a writer's commits, read-only |
| `hinata` | Codebase analyst: read-only analysis for planning |
| `jiraiya` | Web researcher: cited answers from primary sources |
| `lee` | Command runner: tests, builds, git, scripts |
| `ino` | Scribe: keeps your Preferences and each repo's Lessons tidy |

## Teams

A Team is a named setup for an Orchestrator, its Workers and its rules, picked when a session starts: a lean one for speed or for a provider whose usage is low, a thorough one for hard work.
It also holds a tree of Members, the plan of which Workers the Orchestrator may start and what follows each.
It is a JSON file `<name>.json` (lowercase letters, digits and `-`, up to 40 characters) in three places, a later one replacing a same-named file whole: Echo's own in [`teams/`](teams/) (`claude-opus`, `claude-lean`, `kiro-lean`), yours in `~/.echo/teams/`, and a repo's in its `.echo/teams/`, shared through git.
Every field is optional, and a missing one means the level below:

```json
{
  "description": "Sonnet plans, Haiku works, on Kiro",
  "orchestrator": { "cli": "kiro", "model": "claude-sonnet-5.5", "effort": "medium", "rotateAt": 150000 },
  "workers": {
    "cli": "kiro", "model": "claude-haiku-5.5", "effort": "low",
    "profiles": { "naruto": { "model": "claude-sonnet-5.5", "effort": "high" } }
  },
  "rules": { "maxWorkers": 3, "planApproval": true, "review": true, "mergeWithoutAsking": false },
  "members": [
    { "id": "build", "action": "execute", "profile": "naruto", "instructions": "Keep changes small." },
    { "id": "check", "action": "verify", "profile": "sasuke", "parent": "build" },
    { "id": "ask-the-web", "action": "research", "profile": "jiraiya", "model": "claude-haiku-5.5" }
  ],
  "instructions": "Text added to the end of the Orchestrator's prompt, after the rules."
}
```

```
echoctl team list                          every Team here, with where it comes from and what it runs
echoctl team show claude-lean              one Team's origin, file and every field it sets, its Members as a tree
echoctl team actions                          the Actions a Member can be for, with the Profile each starts from
echoctl ui orchestrator --team kiro-lean   open an Orchestrator that starts and resumes with that Team
```

### Members and Actions

A Member is one node of a Team's tree: a Worker slot with a name (`id`), an Action, the Profile it starts from, and the changes this Team makes to that Profile.
A Member's fields are `id`, `action`, `profile`, `parent`, `instructions`, `replaceRole`, `cli`, `model`, `effort`, `tools`, `skills`, `context`, `lessons`, `writes` and `worktree`; only `id`, `action` and `profile` are required, and a field left out means the level below.
`members` is a flat array in tree order, and `parent` names the Member above, so moving a Member is a small diff in git.
`instructions` are added after the Profile's role (or replace it with `replaceRole`); `tools`, `skills` and `context` replace the Profile's lists when they are not empty; `lessons: false` leaves the repo's Lessons out of that Worker's prompt.
The tree is at most 3 levels deep with at most 24 Members, and a `verify` Member sits under an `execute` Member.

An Action is what a Member is for. Echo ships six in [`actions/`](actions/), each with a default Profile, and a Member built on a Profile of your own is `custom`:

| Action | Default Profile | For |
| --- | --- | --- |
| `scan` | `hinata` | reading the code |
| `research` | `jiraiya` | reading the web |
| `execute` | `naruto` | changing code |
| `verify` | `sasuke` | reviewing a writer's commits |
| `run` | `lee` | commands, tests and builds |
| `scribe` | `ino` | Preferences and Lessons |

The tree is a plan of hand-offs that the Orchestrator and the daemon carry out; a Member never starts another Member, and Workers still talk only to their Orchestrator.
A Team with Members gives its Orchestrator a generated "Your Workers" section: each Member, its Action, what it runs on, and what follows it.
`echoctl worker start <member-or-profile>` takes a Member's `id` first, else the first Member that uses that Profile, else a bare Profile; the Worker records its Member.
A writer started with `--verify` is verified by its Member's first `verify` child, else by `sasuke`; the Team's `rules.review`, when set, decides whether it is verified at all.
A Worker's CLI, model and effort come from the first of these that sets them: what was picked for it, its Member, the Team's `workers.profiles.<Profile>`, the Team's `workers`, the Profile, the repo's `.echo/settings.json`, then `~/.echo/settings.json`.

### The Teams section in Echo

Settings has one section for all of this, Teams, in place of the old Agents and Teams tabs.
Its list holds a Defaults entry (the default CLI and model, "Use for every agent", and the Orchestrators' default rules) and every Team, with where each comes from.
Picking a Team shows its tree: the Orchestrator at the root and its Members below it.
Drag a Member to move it, or drag a chip from the palette to add one; with the tree focused, ↑ and ↓ select, ⌥↑ and ⌥↓ move among siblings, ⌥→ indents, ⌥← outdents, Return renames, Delete removes, `a` adds and `d` duplicates. The same moves are buttons and menu items.
Picking a Member opens its inspector: name, Action, Profile, instruction, CLI, model and effort, tools, skills, context, Lessons, writes and worktree, with "Edit shared role..." for the Profile's own file and "New custom Worker..." for a Profile of your own.
"New Team" asks for a starting point and a provider.
Unsaved edits ask before they are lost.
Echo's own Teams (`claude-opus`, `claude-lean`, `kiro-lean`) are trees too, and read-only: Duplicate one to change it.

A Team differs from a Profile: a Profile is a Worker's role (its prompt and tools), while a Team says which models the Orchestrator and the Workers run on and under which rules.
A Team's `workers` choices come before a Profile's own `cli`, `model` and `effort`, and `workers.profiles.<Profile>` before the rest of `workers`.
A Team applies when an Orchestrator starts or resumes and when a Worker starts or resumes, so editing a Team's file changes a running session at its next start or resume.
A Team a model or effort cannot run is refused when it is saved and again when it is used, before any worktree is made.
Only Orchestrators take a Team: a Normal session and a Terminal have none.
Echo's own Teams are read-only; saving one under the same name writes your copy, which then replaces it.

## The `echoctl` CLI

```
echoctl                      open the Orchestrator working in this checkout
echoctl a10                  open a named agent
echoctl attach <w12|a3>      make this terminal a Worker's or an agent's terminal (Ctrl-] detaches)
echoctl status               dashboard rows for this repo's Workers
echoctl sessions             repos the daemon knows, each with its agents
echoctl daemon | shutdown    run or stop the Hub Daemon (agents keep running; --force stops them too)
echoctl stats [--days N]     what Workers spent tokens on and how much they read
echoctl profile <action>     see and change the Agent Profiles Workers start as
echoctl team <action>        see the Teams an Orchestrator can start with, their Members, and the Actions
echoctl ui <action>          have Echo open a file, show an agent, a diff, or a Settings section (`ui settings teams`), notify, or start an Orchestrator
                             (agents learn it from the echoctl:echo skill in skills/)

Orchestrator:  echoctl worker start <member-or-profile>|list|read|send|task|key|close|resume, echoctl wait, echoctl reply, echoctl inbox
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
| `actions/` | Actions: what a Team's Members are for, each with a default Profile |
| `teams/` | Echo's own Teams, as trees of Members |
| `mod/` | Claude Code plugin: folds tool calls and shows the Worker Dashboard in the Orchestrator's terminal |
| `settings/` | Settings applied to Workers |
| `docs/adr/` | Architecture decisions |
| `docs/decisions/` | Decisions about how Echo looks and behaves, and what it does |
| `docs/design/` | Early layout explorations |

## Decisions

Every change obeys the decisions in force.
Read [`docs/decisions/README.md`](docs/decisions/README.md) for the rules and the format.
A committed decision file is never edited; a new file supersedes it.

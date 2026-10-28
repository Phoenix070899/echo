# Echo alternatives

Date: 2026-10-27

Products that run and supervise several coding agents at once, checked against their own sites, docs, and repos.
Every claim cites its source.
GitHub facts (license, last push, stars) come from `gh repo view` and `gh api repos/<repo>/license` on 2026-10-27.

## What Echo already has

So the ideas at the end skip these: Orchestrator to Worker Tasks with profiles, per-Worker worktrees, Needs you / Running / Done ledger, Final Reports, line comments on diffs sent to agents, file preview and edit, start from a GitHub issue, fan out and keep one, Echo Remote on the phone, notifications, plan usage in the title bar, and `echoctl ui`.

## Products

### Conductor

- What: a Mac app to "run parallel coding agents on your Mac" ([conductor.build](https://www.conductor.build/)).
- Platform: macOS; agents "still run on your Mac with your user permissions" ([workspaces](https://www.conductor.build/docs/concepts/workspaces-and-branches)).
- Open source: no license or repo is stated on the site ([conductor.build](https://www.conductor.build/)).
- Agents: Claude Code, Codex, Cursor, and OpenCode ([docs](https://www.conductor.build/docs/)).
- Isolation: each workspace is a git worktree with its own branch; setup scripts run in it and apps can read `CONDUCTOR_PORT` ([workspaces](https://www.conductor.build/docs/concepts/workspaces-and-branches)).
- Supervision: line comments on the diff go to the agent, with per-commit filter and unified view ([diff viewer](https://www.conductor.build/docs/reference/diff-viewer)).
- Standout: a Checks tab gathers git status, PR data, CI, deployments, GitHub review threads, and todos as "the last review pass before merge", and can block merge on failed checks or open todos ([checks](https://www.conductor.build/docs/reference/checks)).
- Pricing: Free; Pro $50/month adds cloud workspaces, multiplayer, the API, and the mobile app; Teams $60/user/month ([pricing](https://www.conductor.build/pricing)).

### Paradev (formerly Superset)

- What: "an agentic IDE to orchestrate 100+ coding agents in parallel" ([repo](https://github.com/superset-sh/superset)).
- Platform: macOS first, Linux experimental, no Windows; iPhone and iPad app ([README](https://github.com/superset-sh/superset)).
- Open source: Elastic License 2.0, source-available, not OSI open source ([README](https://github.com/superset-sh/superset)).
- Agents: Claude Code, Codex, or any CLI agent ([README](https://github.com/superset-sh/superset)).
- Isolation: a git worktree per workspace; local or cloud workspaces ([README](https://github.com/superset-sh/superset)).
- Lifecycle scripts: `setup`, `teardown`, and `run` in `.superset/config.json`, with per-user and local overrides ([lifecycle scripts](https://docs.paradev.com/llms.mdx/setup-teardown-scripts)).
- Orchestration: a coordinator agent uses the `superset:orchestrate` skill to create workspaces, start Workers, read and send to their terminals, and wait for "done or blocked" ([orchestration](https://docs.paradev.com/llms.mdx/orchestration)).
- Supervision: workspace activity strip, sounds, dock badge for "need your attention" ([agent status](https://docs.paradev.com/llms.mdx/agent-status)); select PR diff lines and send them to an agent ([README](https://github.com/superset-sh/superset)).
- Standout: automations run agents on a schedule or on events such as a PR review request or a Sentry issue ([README](https://github.com/superset-sh/superset)); in-browser Design mode sends a picked element to the agent ([README](https://github.com/superset-sh/superset)).
- Pricing: Free; Pro $20/user/month adds remote access, automations, mobile; Team $60 adds cloud workspaces ([pricing](https://paradev.com/pricing)).

### Orca

- What: "the AI Orchestrator for 100x builders", running agents side by side, each in its own worktree ([repo](https://github.com/stablyai/orca)).
- Platform: macOS, Windows, Linux; iOS app and Android APK ([README](https://github.com/stablyai/orca)).
- Open source: MIT ([README](https://github.com/stablyai/orca)).
- Agents: Codex, Claude Code, OpenCode, Pi, or any CLI agent ([README](https://github.com/stablyai/orca)).
- Isolation: git worktrees, plus SSH worktrees on a remote box with port forwarding ([README](https://github.com/stablyai/orca)).
- Orchestration (experimental): Runs, Tasks with dependencies forming a DAG, Dispatches, typed inbox messages (`worker_done`, `escalation`, `question`, `heartbeat`), blocking `ask`, and coordinator-owned decision gates that block a Task until resolved ([orchestration](https://www.onorca.dev/docs/cli/orchestration)).
- Supervision: batched diff notes sent to a chosen agent in one prompt, because one-at-a-time comments make "the agent swing back and forth" ([annotate diff](https://www.onorca.dev/docs/review/annotate-ai-diff)); phone push when an agent finishes, replies by text or voice, relay or LAN pairing ([mobile](https://www.onorca.dev/docs/mobile)).
- Standout: Design Mode in a real Chromium window, account switcher with usage and rate-limit resets, and an `orca` CLI agents use to drive the app ([README](https://github.com/stablyai/orca), [CLI](https://www.onorca.dev/docs/cli/overview)).
- Pricing: free, MIT ([README](https://github.com/stablyai/orca)).

### Nimbalyst (formerly Crystal)

- What: Crystal was deprecated in February 2026 and replaced by Nimbalyst ([Crystal repo](https://github.com/stravu/crystal)), a "visual workspace for Claude Code, Codex, and OpenCode" ([repo](https://github.com/Nimbalyst/nimbalyst)).
- Platform: macOS, Windows, Linux (Electron); iOS companion ([README](https://github.com/Nimbalyst/nimbalyst)).
- Open source: MIT ([repo](https://github.com/Nimbalyst/nimbalyst)).
- Agents: Codex and Claude Code; OpenCode and Copilot in alpha; a Gemini provider ([README](https://github.com/Nimbalyst/nimbalyst)).
- Isolation: a git worktree per session ([README](https://github.com/Nimbalyst/nimbalyst)).
- Supervision: red/green review inside the rendered document, accepting or rejecting each edit; the phone shows which agents need you, takes text or voice replies, and pushes when an agent waits ([README](https://github.com/Nimbalyst/nimbalyst)).
- Standout: a session kanban, task trackers agents read and update, and WYSIWYG editors for Markdown, Mermaid, Excalidraw, CSV, and mockups ([README](https://github.com/Nimbalyst/nimbalyst)).
- Pricing: the app is "free for individuals"; Wiki Teams is paid, free in beta ([nimbalyst.com](https://nimbalyst.com/)).

### Claude Squad

- What: a terminal app that manages several Claude Code, Codex, Gemini, Aider, and other agents ([repo](https://github.com/smtg-ai/claude-squad)).
- Platform: any OS with tmux and gh; latest release v1.0.20 on 2026-08-20 ([releases](https://github.com/smtg-ai/claude-squad/releases)).
- Open source: AGPL-3.0 ([repo](https://github.com/smtg-ai/claude-squad)).
- Isolation: tmux session plus its own git workspace per task ([README](https://github.com/smtg-ai/claude-squad)).
- Supervision: preview and diff tabs; `c` commits and pauses a session, `r` resumes, `s` pushes; an `--autoyes` mode accepts prompts ([README](https://github.com/smtg-ai/claude-squad)).
- Standout: pause and resume a session, freeing its checkout ([README](https://github.com/smtg-ai/claude-squad)).
- Pricing: free.

### Sculptor (Imbue)

- What: "a desktop app for running coding agents in parallel", an experimental research preview ([repo](https://github.com/imbue-ai/sculptor)).
- Platform: macOS (Apple Silicon) and Linux ([README](https://github.com/imbue-ai/sculptor)).
- Open source: MIT ([repo](https://github.com/imbue-ai/sculptor)).
- Agents: Claude Code and Pi built in, any terminal agent otherwise ([README](https://github.com/imbue-ai/sculptor)).
- Isolation: workspaces are worktrees; agents in one workspace share its working copy ([agents](https://github.com/imbue-ai/sculptor/blob/main/docs/help/agents.md)); an experimental backend runs in Docker or, in principle, a remote VM ([container backend](https://github.com/imbue-ai/sculptor/blob/main/docs/help/experimental/container_backend.md)).
- Supervision: a Changes tab with per-file discard and agent-written commits; feedback goes through chat ([changes](https://github.com/imbue-ai/sculptor/blob/main/docs/help/changes.md)).
- Standout: bundled workflow skills, such as `fix-bug`, which interviews for a repro, writes failing tests, then fixes ([README](https://github.com/imbue-ai/sculptor)).
- Pricing: not stated.

### Vibe Kanban

- What: plan with kanban issues, then run agents in workspaces ([repo](https://github.com/BloopAI/vibe-kanban)).
- Status: bloop announced the shutdown on 2026-04-10; it stays open source and community maintained, local only ([shutdown post](https://www.vibekanban.com/blog/shutdown)); the repo was still pushed on 2026-10-26.
- Platform: local web app via `npx vibe-kanban` ([README](https://github.com/BloopAI/vibe-kanban)).
- Open source: Apache-2.0 ([repo](https://github.com/BloopAI/vibe-kanban)).
- Agents: Claude Code, Codex, Gemini CLI, Copilot, Amp, Cursor, OpenCode, Droid, CCR, Qwen Code ([README](https://github.com/BloopAI/vibe-kanban)).
- Isolation: each workspace gets a branch, a terminal, and a dev server ([README](https://github.com/BloopAI/vibe-kanban)).
- Supervision: inline diff comments sent to the agent; PRs with generated descriptions; a built-in browser with devtools and inspect mode ([README](https://github.com/BloopAI/vibe-kanban)).
- Pricing: free.

### Cursor Agents Window and cloud agents

- What: Cursor 3 (2026-04-02) added an Agents Window to run and manage many agents across repos and environments ([agents window](https://cursor.com/docs/agent/agents-window)).
- Platform: Cursor desktop, web at cursor.com/agents, iOS app, Android PWA ([cloud agent](https://cursor.com/docs/cloud-agent)).
- Open source: no.
- Agents: Cursor's own agent with a curated set of models ([cloud agent](https://cursor.com/docs/cloud-agent)).
- Isolation: local git worktrees, or a cloud VM and branch per agent; an agent can move between cloud and local ([agents window](https://cursor.com/docs/agent/agents-window)).
- Supervision: agents return screenshots, videos, and logs as proof; you can take over the agent's remote desktop to test; teammates open a shared agent URL ([cloud agent](https://cursor.com/docs/cloud-agent)).
- Standout: start agents from Slack, Linear, or an `@cursor` comment on a GitHub issue or PR ([cloud agent](https://cursor.com/docs/cloud-agent)).
- Pricing: cloud agents need Premium $30/month or higher ([pricing](https://cursor.com/pricing)).

### OpenAI Codex app (ChatGPT desktop)

- What: Codex runs inside the ChatGPT desktop app, which can "run projects in parallel" ([app](https://learn.chatgpt.com/docs/app)).
- Platform: macOS, Windows, Linux; phone control through the ChatGPT mobile app ([app](https://learn.chatgpt.com/docs/app), [remote connections](https://learn.chatgpt.com/docs/remote-connections.md)).
- Open source: the Codex CLI is open source ([openai/codex](https://github.com/openai/codex)); the desktop app is not.
- Isolation: Codex-managed worktrees per chat; Handoff moves a chat between the worktree and your checkout; `.worktreeinclude` copies ignored files ([worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees.md)); setup scripts per local environment ([index](https://learn.chatgpt.com/llms.txt)).
- Supervision: a review pane with inline comments and stage or revert per hunk ([code review](https://learn.chatgpt.com/docs/code-review.md)); the phone can start, steer, approve, and review diffs and test output ([remote connections](https://learn.chatgpt.com/docs/remote-connections.md)).
- Standout: Auto-review routes approval prompts to a separate reviewer agent, which approves or denies with a reason; a denial makes the main agent find a safer path or ask the user ([auto-review](https://learn.chatgpt.com/docs/sandboxing/auto-review.md)); before a managed worktree is deleted, Codex snapshots it so the chat can be restored ([worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees.md)).
- Pricing: included in ChatGPT plans from Free up ([index](https://learn.chatgpt.com/llms.txt)).

### GitHub Copilot Agent HQ

- What: one place on GitHub to assign work to Copilot and partner agents; Claude and Codex entered public preview in February 2026 ([Agent HQ post](https://github.blog/news-insights/company-news/welcome-home-agents/), [changelog](https://github.blog/changelog/2026-02-04-claude-and-codex-are-now-available-in-public-preview-on-github/)).
- Platform: github.com, VS Code, CLI, GitHub Mobile ([third-party agents](https://docs.github.com/en/copilot/concepts/agents/about-third-party-coding-agents)).
- Open source: no.
- Isolation: cloud sessions on GitHub Actions; stopping a session ends the Actions run ([manage agents](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/manage-agents)).
- Supervision: session logs, steering messages mid-run (not for third-party agents), and the work lands as a PR ([manage agents](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/manage-agents)).
- Pricing: a paid Copilot plan; sessions use Actions minutes and AI credits ([third-party agents](https://docs.github.com/en/copilot/concepts/agents/about-third-party-coding-agents)).

### Warp

- What: "an agentic development environment, born out of the terminal" ([repo](https://github.com/warpdotdev/warp)).
- Platform: desktop app plus cloud agents ([agent platform](https://docs.warp.dev/agent-platform/)).
- Open source: client is AGPL-3.0, UI crates MIT ([README](https://github.com/warpdotdev/warp)).
- Agents: Warp's own agents; Claude Code, Codex, and OpenCode as CLI agents with notifications, vertical-tab status, and inline review comments ([CLI agents](https://docs.warp.dev/agents/cli-agents/overview/)).
- Orchestration: a parent agent spawns child agents one level deep, local or cloud, through a message bus with per-agent inboxes and lifecycle states (`SUCCEEDED`, `FAILED`, `BLOCKED`); the human approves the plan, parallelism, and models before children launch ([orchestration](https://docs.warp.dev/platform/orchestration/)).
- Remote: publish a running Claude Code or Codex session as a link, opened in any browser, with view or edit access ([remote control](https://docs.warp.dev/agents/cli-agents/remote-control/)).
- Pricing: Free; Build $20/month; Max $200/month; Business $50/user/month ([pricing](https://www.warp.dev/pricing)).

### cmux

- What: an "open source Ghostty-based macOS terminal with vertical tabs and notifications for AI coding agents" ([repo](https://github.com/manaflow-ai/cmux)).
- Platform: native macOS (Swift, AppKit, libghostty); an iOS app and a TUI also exist ([README](https://github.com/manaflow-ai/cmux), [LICENSE](https://github.com/manaflow-ai/cmux/blob/main/LICENSE)).
- Open source: app, iOS app, and CLI are GPL-3.0-or-later; server parts are BUSL-1.1 ([LICENSE](https://github.com/manaflow-ai/cmux/blob/main/LICENSE)).
- Agents: any terminal agent; `cmux claude-teams` runs Claude Code teammate mode as native splits ([README](https://github.com/manaflow-ai/cmux)).
- Isolation: none of its own; `cmux ssh` makes a workspace on a remote machine ([README](https://github.com/manaflow-ai/cmux)).
- Supervision: notification rings on panes, a notification panel, and a sidebar with branch, PR status, ports, and latest notification text ([README](https://github.com/manaflow-ai/cmux)).
- Pricing: free.

## Also checked

- JetBrains ThinkRail: Apache-2.0 IDE around the `pi` agent with worktree workspaces, anchored review comments, a shared plan with a commit per step, living `SPEC.md` files, and a PR bar showing CI checks that can hand failing checks to the agent ([repo](https://github.com/JetBrains/thinkrail)).
- Zed agent panel: parallel threads, optional worktree per thread, hunk-level accept or reject, and Claude, Codex, and Gemini CLI over ACP ([agent panel](https://zed.dev/docs/ai/agent-panel), [external agents](https://zed.dev/docs/ai/external-agents)).
- opcode (formerly Claudia): AGPL-3.0 Tauri GUI for Claude Code with custom agents, usage analytics, and session checkpoints; last release v0.2.0 in August 2025 ([repo](https://github.com/winfunc/opcode)).
- Terragon: shut down; an Apache-2.0 snapshot was published on 2026-01-16; it ran agents in cloud sandboxes with automations and a `terry` CLI for local handoff ([repo](https://github.com/terragon-labs/terragon-oss)).
- uzi: MIT CLI with worktrees, tmux, and a dev server per agent from `devCommand` and `portRange`; last push June 2025 ([repo](https://github.com/devflowinc/uzi)).

## Comparison

| Product | Isolation | Multi-agent orchestration | Diff review | Mobile / remote | Open source |
| --- | --- | --- | --- | --- | --- |
| Echo | Worktree or in place | Orchestrator to Workers | Line comments to agent | Echo Remote (phone web app) | Repo source |
| Conductor | Worktree; cloud (Pro) | No, parallel only | Line comments, Checks tab | Mobile app (Pro) | No |
| Paradev | Worktree; cloud (Team) | Coordinator skill over CLI | Line comments, PR lines | iOS app, remote hosts (Pro) | ELv2 (source-available) |
| Orca | Worktree; SSH | Tasks, DAG, gates (experimental) | Batched line notes | iOS and Android | MIT |
| Nimbalyst | Worktree | No | Accept or reject per edit | iOS companion | MIT |
| Claude Squad | tmux and worktree | No | Diff tab | No | AGPL-3.0 |
| Sculptor | Worktree; Docker (experimental) | No | Changes tab | No | MIT |
| Vibe Kanban | Worktree and dev server | No, kanban | Inline comments | No | Apache-2.0 |
| Cursor | Worktree; cloud VM | Cloud subagents | Diffs view, artifacts | iOS, web | No |
| Codex app | Worktree; cloud | Not documented | Inline comments, hunk stage | Phone via ChatGPT | CLI only |
| GitHub Agent HQ | GitHub Actions | No, assign per agent | PR review | GitHub Mobile | No |
| Warp | Local or cloud | Parent and child agents | Inline comments | Shared session link | AGPL-3.0 client |
| cmux | None; SSH | Claude Code teams | No | iOS app | GPL-3.0 app |

## Ideas for Echo

Ranked by fit with the Orchestrator and Worker model.

1. Task dependencies and decision gates (Orca).
   Let the Orchestrator say a Task waits on another, and let the daemon start it when that Task's Final Report says done.
   A gate is a question tied to a Task that holds it until answered, and it would show in Needs you.
   Echo's daemon already stores Tasks, so it can hold the order and keep the Orchestrator's context free of polling.
2. Worktree setup, run, and teardown scripts with a port per worktree (Conductor, Paradev, Codex, uzi).
   A Worker in a new worktree starts without `node_modules`, `.env`, or a free port, so builds and `sasuke` checks fail or collide.
   A checked-in config, plus a list of ignored files to copy like Codex's `.worktreeinclude`, fixes this for every Worker.
3. A reviewer agent before Needs you (Codex Auto-review).
   Route a Worker's permission prompt to a reviewer first; it approves or denies with a reason, and only unclear ones reach the human.
   This fits Echo's rule that a blocked Worker asks the Orchestrator first, and cuts the noise in Needs you.
4. Merge readiness per Worker branch (Conductor Checks, ThinkRail, Paradev).
   Show PR state, CI checks, and GitHub review threads next to the Worker's diff, and send a failing check back to that Worker as a Task.
   Echo starts from GitHub issues but stops before the PR; this closes the loop.
5. Automations (Paradev, Codex, Terragon, Cursor).
   Start an Orchestrator on a schedule or on an event, such as a new issue, a PR review request, or a failing CI run, and put its Summary in Done.
   The Orchestrator already plans and reports, so an unattended start only needs a trigger and a rule for when "go" is implied.
6. Snapshot a worktree before cleanup, restore on demand (Codex).
   Done Workers leave Echo after five minutes; a saved snapshot lets the human reopen the work later without keeping every worktree on disk.
7. Picked-element context from a running app (Orca Design Mode, Paradev Design, Vibe Kanban).
   Echo already previews HTML in a web view; picking an element and sending its HTML, CSS, and a cropped screenshot to a Worker would make UI fixes precise.
8. Workers on a remote host over SSH (Orca, cmux, Codex).
   The daemon could start a Worker's terminal and worktree on a bigger machine, while the ledger and Echo Remote stay the same.
9. Progress heartbeats for long Tasks (Orca).
   Echo already catches prompts and idle Workers through hooks; a heartbeat would also catch a Worker that stays busy with no progress, and flag it in Needs you.

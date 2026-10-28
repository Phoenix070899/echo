# A repo's new worktrees get its ignored files and run its setup before the agent starts

Decided: 2026-10-28
Status: accepted

A repo's `.echo/settings.json` may list `"copy"`: paths inside the repo that git ignores, like `.env`, copied from the main checkout into each new worktree where it lacks them, folders whole.
It may also set `"setup"`: a command run in each new worktree, in the human's login shell, before the Worker's or agent's CLI starts, like `pnpm install`.
The setup runs in the agent's own terminal, so the human watches it there; a Worker's start then waits up to 20 minutes instead of 90 seconds.
A setup that fails starts no agent: the start fails with the terminal's last lines, and the Orchestrator reports it.
Copying happens for any worktree that is not the main checkout; the setup runs only on a Worker's first start in a `new:` worktree and an agent's first start in a worktree of its own, never on a resume or in place.
Why: Workers in new worktrees started without the repo's secrets or installed dependencies, and spent their Task setting them up (research: Conductor, Paradev, and Codex do this).
Rejected: running the setup inside the daemon, which would block it and hide the output.

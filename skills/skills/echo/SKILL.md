---
name: echo
description: Point the human at something in Echo, the app they watch you in, with `echoctl ui`. Use when showing a file or line, a Worker or agent, or a Worker's diff beats describing it; when a result is ready and the human may be away; or when the human asks for a new Orchestrator, on a branch or not.
---

# Showing things in Echo

You run inside Echo: the human sees your terminal there, beside the files and Workers of this repo.
`echoctl ui` changes what that window shows. Echo never comes to the front for it, so the human looks when they choose; say in your reply what you showed and why.

## Point

- A file, at the line that matters: `echoctl ui open <path>[:line]`. The path is relative to your working directory. Echo selects the agent or Worker that works in that file's checkout, so a file in a Worker's worktree opens beside that Worker.
- A Worker or agent: `echoctl ui show w12` or `echoctl ui show a3`.
- A Worker's changes, ready for review: `echoctl ui diff w12`. Do this whenever you ask the human to review or merge a Worker's work.

- A setting only the human changes, like which CLI or model a Team's Members run with, or the shape of a Team's tree of Members: `echoctl ui settings teams` (Settings has one section for all of it, Teams; `agents` still opens it); `memory` for the human's Preferences and this repo's Lessons (also window, theme, background, font, multiplexer, remote).

Point at the one place the human needs, at the moment you mention it.

## Workers by Member

A Team with Members lists them to you as "Your Workers". Start a Worker by a Member's id, or by a Profile name when there is no Member for it:

```
echoctl worker start <member-or-profile> --spec-file <file> [--verify]
```

The name is looked up as a Member id first, else the first Member that uses that Profile, else a bare Profile; the Worker is recorded under its Member. With `--verify`, the writer's Member's `verify` child checks its commits, else `sasuke`.

- `echoctl team show <team>` prints a Team's Members as a tree, with each one's Action and what it runs on.
- `echoctl team actions` lists the Actions a Member can be for (`scan`, `research`, `execute`, `verify`, `run`, `scribe`, and `custom` for a Member on the human's own Profile) with the Profile each starts from.
- `echoctl profile list` lists the Profiles, for a Profile the list lacks.

The tree is a plan of hand-offs for you to follow, not a chain the daemon runs; only the verify step is run for you.
To change a Team's tree, point the human at `echoctl ui settings teams`.

## Notify

`echoctl ui notify "<one line>"` posts a macOS notification from you; clicking it opens Echo on you.
Notify when something is ready for the human (a Summary, a question, a review) and they may be away, once per thing.
"-" as the text reads it from stdin.

## Start an Orchestrator

When the human asks for another Orchestrator, start it and Echo shows it:

```
echoctl ui orchestrator                                      # on the repo's checkout
echoctl ui orchestrator --branch <existing-branch>           # on that branch, in its own worktree
echoctl ui orchestrator --new-branch <name> [--base <ref>]   # a new branch from <ref> (default HEAD)
                       [--name "<name>"] [--request "<its first request>"]
```

It prints `Started Orchestrator a<N>.`; tell the human its name and branch.

## When it fails

- "Echo is not open on <repo>": nothing was shown. Give the human the path, Worker, or text in your reply instead. An Orchestrator started anyway.
- "no Worker w12 in this repo" or "no agent a3": check the id with `echoctl status`.

`echoctl ui --help` and `echoctl ui <action> --help` list every flag.

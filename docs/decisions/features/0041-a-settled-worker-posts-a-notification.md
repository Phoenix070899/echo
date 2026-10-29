# A Worker that settles posts a notification

Decided: 2026-10-29
Status: accepted

When a Worker Echo saw running settles (done, blocked, exited, lost, or ended), Echo posts a macOS notification: the Worker, its Profile, how it ended and its Task as the title; the repo and its Orchestrator as the subtitle; the blocker, else the Final Report's first line, as the body.
Clicking it opens Echo on that Worker.
A Worker already settled when Echo opens, or first seen settled, posts none, so a relaunch announces nothing again.
It adds to the Needs' notifications, which still post as before.
Why: the human wanted to know each time a Worker finishes, without watching the ledger.

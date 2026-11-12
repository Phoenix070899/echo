# Typing into a Worker checks its screen first and reports whether it started

Decided: 2026-10-31
Status: accepted

`echoctl worker send`, `echoctl worker task`, and a review typed into a Worker refuse while it shows a permission or trust prompt, because the text would answer it; `worker send --force` types anyway.
After the text and its Enter, they watch the screen for up to 5 s and report `started`: true once a turn is under way (working, or stopped at a prompt), false otherwise, and the CLI says to read the screen.
A Worker resumed on its next Task reports no `started`; `worker start` already waits for the first turn.
Why: text sent while a prompt showed answered it, and a send the Worker never acted on went unnoticed until the idle blocker; herdr-core's `send` (crates/herdr-core/src/input.rs) refuses over a blocked agent and reports whether it started the same way.

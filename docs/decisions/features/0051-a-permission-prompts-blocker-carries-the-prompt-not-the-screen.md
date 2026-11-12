# A permission prompt's blocker message carries the prompt, not the Worker's screen

Decided: 2026-11-11
Status: accepted

The blocker message for a `permission_prompt` has the prompt's own lines (`prompt_lines`, ending in "Do you want to ...") under "The prompt:", and no screen.
When the prompt's lines cannot be read, and for every other blocker (an idle Worker), it keeps the last 25 lines of the screen as before.
The Orchestrator can read more with `echoctl worker read <w>`; `orchestrator.md` says so.
Echo's Needs you reads the same lines from the snapshot's `prompt` field (features/0017), so what it shows does not change; its `body` is the fallback only when `prompt` is empty.
Why: the message was 25 lines of 160 columns that the Orchestrator keeps in its context for the rest of the session, to show the human a command of one or two lines.

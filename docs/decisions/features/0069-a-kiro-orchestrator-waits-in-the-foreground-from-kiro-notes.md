# A Kiro Orchestrator waits in the foreground, and the Kiro differences live in kiro-notes.md

Decided: 2026-11-13
Status: accepted

A Kiro Orchestrator calls `echoctl wait --timeout 170` through the shell tool with `timeout: 200000`, in the foreground, and calls it again while any Worker is open.
Kiro's shell tool has no background wake: `run_in_background` only appends `&` and returns, so no message reaches the agent when the command ends.
The shell tool stops a command at 120000 ms unless `timeout` is set, so the 200000 ms limit sits above the 170 s wait and the wait always ends by itself; `--timeout` stays at or below 190.
`hub/kiro-notes.md` is the one place that says this and the other Kiro differences (tool names, permission denial, the blocked rules). The daemon appends its `## Orchestrator` or `## Worker` section to the agent's prompt under "# Running on Kiro"; a Normal session gets none. A Kiro Orchestrator or Worker fails to start with a message naming the file when the file or its section is missing.
A message the human types during a wait may reach the Orchestrator up to 170 s late; that is why the wait is short.
Why: the Claude prompt tells an Orchestrator to wait with one background listener, which on Kiro would end every turn with Workers open and never wake it.
Rejected: the Claude prompt's background listener, which the spike (Q8) showed never wakes a Kiro agent.

# `chat.read` gives an agent's last 200 chat items, then only what is new

Decided: 2026-11-12
Status: accepted

`chat.read` (agent, optional session and after) finds the agent's current session's transcript under `$CLAUDE_CONFIG_DIR/projects` (else `~/.claude/projects`) and returns chat items, the session, and the byte offset to continue from.
A first read takes the file's tail, reading back from 2 MiB by fourfold steps until 200 items fit or the file starts; a read with the same session and an offset reads only the whole lines after it, so a line being written waits for the next read.
A new session (a renewal, `/clear`) starts the chat over; keeping the earlier session above a divider comes with history paging (milestone 4).
Items are `user`, `reply`, `tool`, `result` (a tool's output, matched by its tool id), `event`, and `divider`; texts are cut at 20,000 characters and tool output at 40 lines.
An agent on another CLI reads as `supported: false`, and Echo says its chat is not there yet.
Why: Orchestrator transcripts reach tens of MB, so reading one whole on every switch or poll would be slow.

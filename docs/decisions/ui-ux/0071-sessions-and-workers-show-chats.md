# Claude Code sessions and Workers show their chat too

Decided: 2026-11-12
Status: accepted

Supersedes: ui-ux/0065, only its line that Claude Code sessions and Workers keep their terminal; plain Terminal tabs still do.
A Claude Code session's panel shows its chat with the same "Chat | Terminal" switch as an Orchestrator's.
A Worker's header picker reads "Chat | Terminal | Changes" while it runs, and "Chat | Final Report | Changes" once it settled, plus Compare for a fan-out; ⇧⌘T flips between the first two.
The choice is remembered per agent and Worker by label (`a3`, `w12`) in `terminalChats`; agent ids saved earlier under `terminalAgents` still count.
A Worker's message box says "Intervention: w12 does what you ask and tells the Orchestrator", in place of the banner under its terminal.
A Codex Worker or session has no transcript Echo reads: a settled Codex Worker shows its Final Report view, a running one says its chat is not there yet.
Why: one picker instead of two segmented controls side by side, which read as the same choice twice.

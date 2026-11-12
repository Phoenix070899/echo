# An Orchestrator shows its chat by default, and ⇧⌘T switches it to its terminal

Decided: 2026-11-12
Status: accepted

An Orchestrator's panel shows its chat (ADR 0010); "Chat | Terminal" in its header and ⇧⌘T (View menu, Show Terminal or Show Chat) switch it.
The choice is remembered per agent (`terminalAgents` in Echo's defaults), so a tab switched to its terminal stays so until switched back.
Switching to the terminal gives it the keyboard; the tab above the panel reads "Chat" or "Terminal" to match.
Claude Code sessions and Workers keep their terminal until the chat takes typing (milestone 3); plain Terminal tabs always do.
Why: ⌘` is macOS's next-window key, and ⇧⌘T was free in Echo; plain ⌘T stays free for a future "new tab".

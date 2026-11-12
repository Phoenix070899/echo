# Agents show as a chat over their terminal

Decided: 2026-11-12
Status: accepted

Echo shows an agent as a chat: the human's messages, the agent's replies as Markdown, and its tool calls folded.
The agent itself does not change: Claude Code keeps running in its terminal inside the multiplexer (ADR 0007), owned by the terminal holder (ADR 0009).
The chat is drawn from Claude Code's transcript, which the daemon reads and sends as chat items (`chat.read`); Echo never reads the transcript files itself, so Echo Remote can show the same chat later.
The real terminal stays one switch away (⇧⌘T), so whatever the chat does not draw yet, such as `/config` menus or pickers, still works there.
Replies appear whole when written, not word by word: Claude Code writes a message to its transcript once it is finished.
The chat comes in milestones: read-only Orchestrator chats first; then typing, prompts as buttons, and a Working row; then Claude Code sessions and Workers; then slash completion and pasted files; then the phone; then Codex, whose transcripts differ.
Why: the human wanted a chat UI that keeps every terminal feature; drawing the chat beside an unchanged Claude Code is the only way to keep all of them.
Rejected: running Claude Code headless (`claude -p --output-format stream-json`, or the Agent SDK) and building the chat on its events, which loses slash commands, interactive menus and plan-mode prompts, and breaks ADRs 0007 and 0009 and Codex.

# A chat draws the human on the right and the agent full width, on Ledger's tokens

Decided: 2026-11-12
Status: accepted

The human's messages and slash commands sit on the right on a `Ledger.wash` bubble.
The agent's replies are full-width Markdown on paper, with no bubble, drawn by the file preview's `MarkdownBlockView`.
A reply whose Needs you section lists something gets an amber edge (`Ledger.changed`), by the same rule as the Orchestrator mod's `needsHuman`.
Task notifications and command output are one dim line; a compacted context is a divider.
The column is at most 860 pt wide, centred.
Until the chat takes typing, a footer says to press ⇧⌘T to type in the terminal.
Why: the Astryx restyle comes after the chat, so the chat uses today's Lanh look (ui-ux/0048) and is restyled with everything else.

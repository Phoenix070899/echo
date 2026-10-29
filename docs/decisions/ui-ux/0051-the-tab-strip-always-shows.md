# The tab strip always shows over a terminal

Decided: 2026-10-29
Status: accepted

Supersedes: ui-ux/0025's "appears as soon as one file is open"; the rest of 0025 stands.
Whenever an agent or a Worker is shown, the strip over the main panel shows, with the Terminal tab alone when no file of its checkout is open.
Why: the strip took two rows from the terminal only where files were open, so switching between an agent with tabs and one without resized the terminal; the multiplexer and Claude Code then redrew the whole screen, which undid ui-ux/0050's instant switch.
Every terminal in the panel is now the same size, so a kept terminal shows again without a resize.

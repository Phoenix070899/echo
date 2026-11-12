# Echo wears Claude's design language

Decided: 2026-11-12
Status: accepted

Supersedes: ui-ux/0077 for colour, type and radius; the layout, the chat column (ui-ux/0078) and every other rule stay.
Every surface takes its colours from `Ledger`, now Anthropic's published palette: a warm cream canvas (`#f0eee6` desk, `#faf9f5` sheets), charcoal ink `#141413`, mid and light greys `#b0aea5` and `#e8e6dc` as hairlines and fills, clay orange `#d97757` for the one accent, blue `#6a9bcc` for running and green `#788c5d` for done. Dark mode is a warm charcoal (`#1f1e1d` desk, `#262624` sheets) with the same accents.
The primary button is clay orange; in light mode it is `#b4532f`, darker than the brand orange, so its cream text keeps 4.5:1.
Text and status colours that the palette gives only as a light step are darkened for light mode (running `#35699b`, done `#5b6e42`) to keep 4.5:1 on cream; failed is a crimson (`#b42318`) the palette lacks, kept apart from the orange.
The highlighter that means "this needs you" is Claude's manilla (`#ebdbbc`, kraft `#d4a27f` in dark), with dark ink on it.
The interface is the system sans (SF). Headings, section titles and the agent's replies in the chat are the system serif (New York) through `Ledger.serif`; code, commands, paths and the terminal stay monospaced.
Radii: 6 inner, 10 element (buttons, fields, rows, cards), 16 container (sheets, the message box), all through `Ledger.radiusInner`, `radiusElement` and `radiusContainer`; no view carries a literal radius except the 1.5 to 3 pt slivers.
Why: the human wanted every part of Echo, the sidebar, chat and Files column alike, to look like Claude.
Rejected: bundling Claude's own faces (Styrene, Tiempos), which are not licensed for this app; the system serif is the nearest stand-in.

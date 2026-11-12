# Echo wears Astryx's neutral theme

Decided: 2026-11-12
Status: accepted

Supersedes: ui-ux/0048 for colour, type, and radius; the layout and the rules it states about buttons' sizes and selected rows stay. ui-ux/0066's "today's Lanh look" is this look now.
Echo's Ledger tokens take their values from Astryx's `@astryxdesign/theme-neutral` (0.7.14): a flat grey ramp, white sheets (`#ffffff` / `#262626`) on a light-grey desk (`#f1f1f1` / `#1b1b1b`), black and white ink, and its info, success and error steps for running, done and failed.
Every token keeps its name and its light and dark twin, so views still take colours only from `Ledger` (ui-ux/0005); the Echo Light and Echo Dark presets of Custom carry the same values.
The highlighter is Astryx's warning yellow (`#ffce2f`, `#eec448` in dark), with dark ink on it in both modes; amber `changed` is its warning text step.
Tokens Astryx has no step for (`ink3`, `band`, `fill`, `selected`, the washes, the border blended on its surface) are blends of two Astryx values; `ink3` is `#6b6b6b`, darker than Astryx's disabled grey, to keep ui-ux/0005's 4.5:1.
Text is Figtree, Astryx's face, bundled in `app/bundle/Fonts` under its OFL licence: 400 for text, 500 for labels, 600 for headings and 700 for the heaviest, through `Ledger.font`. Code, commands, paths and the terminal stay monospaced.
Radii are Astryx's: 6 inner, 10 element (buttons, fields, rows, cards; `Ledger.radiusElement`), 12 container (sheets, the message box; `Ledger.radiusContainer`).
Why: the human wanted Echo to look like Astryx once the chat shipped; the commit before it is the place to go back to.
Rejected: embedding Astryx's React components, since Echo is native SwiftUI; only its tokens carry over.

# Echo wears Lanh AI's design system

Decided: 2026-10-29
Status: accepted

Supersedes: ui-ux/0001 for colour, type, and radius; the layout it describes stays.
Echo's Ledger tokens take their values from Lanh AI's design system (`lanh-ai/frontend/design-system`): its warm neutral ramp, white sheets on a neutral-1 desk, near-black ink, and its status, info and yellow steps for done, failed, running and the highlighter.
Every token keeps its name and its light and dark twin, so views still take colours only from `Ledger` (ui-ux/0005); the Echo Light and Echo Dark presets of Custom carry the same values.
Text is Google Sans Flex, bundled in `app/bundle/Fonts` under its OFL licence: weight 350 for text and 500 for anything heavier, through `Ledger.font`.
Code, commands, paths and the terminal stay monospaced, since Echo is a tool for code; Lanh has no mono face.
`Ledger.ink3` is neutral-6, not Lanh's neutral-5, to keep the 4.5:1 contrast ui-ux/0005 promises on white.
Buttons are Lanh's: 28 pt (32 pt large), radius 8, a neutral-8 primary and a 6% ink wash for the rest.
Sheets take the panel radius (12); a selected row is a rounded fill inset 8 pt from its column, with no bar at its edge.
Why: the human wanted Echo to look like Lanh AI; the commit before it is tagged `pre-lanh-theme` to go back.

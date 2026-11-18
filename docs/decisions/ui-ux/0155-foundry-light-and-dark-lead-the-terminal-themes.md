# Foundry Light and Foundry Dark lead the terminal themes

Decided: 2026-11-16
Status: accepted

Supersedes: ui-ux/0153, only its list of presets; everything else in it stands.
Settings' Terminal Theme lists thirteen presets, starting with Foundry Light and Foundry Dark, then the eleven of ui-ux/0153.
The Foundry themes take the Ledger's colours (ui-ux/0104): the sheet for background, ink for text, the safety orange for the cursor, the highlighter (light) or chosen fill (dark) for selections.
Their red, green, yellow, and blue are the Ledger's failed, done, changed, and running colours, so a terminal reads like the rest of Echo.
Every palette colour but black reads at 4.5:1 or better on the background; Foundry Light draws selected text in ink, since its highlighter would drop some colours below that.
Echo's first look stays Ayu Dark (`standard`).
Why: the human wanted a terminal theme that matches the Foundry design system.

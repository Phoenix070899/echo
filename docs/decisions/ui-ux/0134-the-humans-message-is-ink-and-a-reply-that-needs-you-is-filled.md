# The human's message is an ink bubble, and a reply that needs the human sits on the theme's orange

Decided: 2026-11-15
Status: accepted

Supersedes: ui-ux/0117, only the sunk grey of the human's bubble and the accent edge of a reply that needs the human, because the human asked for the dark bubble and no vertical line.
The human's own message is `Ledger.sent` (ink in light mode, near black in dark) with white text (`Ledger.onSent`); a message the Orchestrator typed into a Worker keeps the sunk grey.
A reply whose Needs you section lists something has no edge; it sits 16 pt in on `Ledger.accentDeep` (`#B45A29` in both modes, the theme's orange 10 % deeper, so white text on it is 4.7:1), its text white (`Ledger.onSent`) in both modes, with the card radius; on it every list marker, checkbox, quote bar, and link (underlined) is white too, code chips and code cards are black at 28 % over the orange, and tables take their dark-mode fills, because the ink's quieter shades, the run blue, and the done green fall under 3:1 on it.
Why: the human's words stand out from the agent's at a glance, and a vertical line read as a quote (ui-ux/0124 already keeps vertical lines out of lists).

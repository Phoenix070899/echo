# The chat column is at most 1200 pt wide

Decided: 2026-11-12
Status: accepted

Supersedes: ui-ux/0066, only its 860 pt column.
The messages and the message box share one centred column of at most 1200 pt (`ChatBottom.width`); a narrower pane uses all of its width less the 32 pt side padding.
Why: at 860 pt a wide window left bands of empty desk either side, and tool outputs, diffs and tables wrapped early.
Rejected: filling the pane, which makes a line of prose too long to read on an ultrawide display.

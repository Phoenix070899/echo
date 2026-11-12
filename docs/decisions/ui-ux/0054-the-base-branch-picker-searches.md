# Create from's base-branch picker is a search, not a menu

Decided: 2026-10-31
Status: accepted

The base-branch picker at the right of Create from opens a popover with a search field over the repo's branches, focused when it opens.
Typing filters the branches by name; ↑ and ↓ move the highlight, Return picks, Escape closes; a check marks the current base.
The list scrolls past about ten branches instead of growing.
Why: a repo has dozens of branches, and a menu of them could only be scrolled, not searched.

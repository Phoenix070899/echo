# The side columns give way before the main panel, and the panel clips instead of pushing

Decided: 2026-11-12
Status: accepted

When the window is too narrow for every column, the Files column shrinks first, down to 220 pt, then the ledger, down to 300 pt; the main panel takes what is left.
The main panel is laid out at the width it is offered and clips what does not fit, so text is cut at the edge and nothing is pushed outside the window.
Why: dragging the right edge made the chat's content slide off the screen instead of clipping.
The ledger is laid out the same way (clipped from its top-left corner), and a title that fades at its end (`fadedEnd`) may be narrower than its text; before, the longest title kept the column's content wider than the column, and it was centred, so both edges were cut.

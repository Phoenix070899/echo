# A terminal in the window stays drawn while the window is covered

Decided: 2026-11-14
Status: accepted

Adds to ui-ux/0050: a terminal shown in Echo's window counts as visible to libghostty even while other windows cover the window; only a kept terminal, out of any window, is occluded.
libghostty frees an occluded surface's frames and draws them again only once told it is visible, after the window is already back on screen, so every return to Echo showed its terminals empty for a moment (bugs/0081).
The cost: the few shown terminals keep their frames while Echo is covered, and draw when their output changes.
Rejected: reporting occlusion only after the window stays covered for a while, which still flashes after a longer absence.
Why: the human saw the window go black for a moment each time they switched back to Echo.

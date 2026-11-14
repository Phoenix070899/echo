# A covered window came back with its terminals empty for a moment

Found: 2026-11-14
Where: app/Sources/HubApp/TerminalPane.swift (GhosttyView.syncOcclusion)
Fixed in: the change that adds this file

After Echo had been behind another app's windows, switching back showed the window with its terminals dark and empty for a moment before their text drew again.
A recording of a throwaway copy, back after 40 s behind Terminal, showed the shown terminal with no text and no multiplexer status line for about 150 ms; with a background image the empty pane is the dimmed image, otherwise the terminal layer is clear.
Cause: each surface was told it was occluded whenever its window's `occlusionState` lost `.visible`, and libghostty (since c4e16970a, "release GPU resources for hidden surfaces") frees an occluded surface's swap chain, frames included.
Back in sight, the surface draws only after AppKit posts the occlusion change, so the window first shows a terminal with nothing in it.
Fix: a surface in a window always counts as visible; only a kept terminal out of any window is occluded (ui-ux/0127).
Lesson: never tell libghostty a shown terminal is occluded; what it frees is drawn again only after the window is already on screen.
Check a fix like this with the window really covered for a while and recorded on screen (`screencapture -v -R`), as a capture of the window alone does not show what the window server composites.

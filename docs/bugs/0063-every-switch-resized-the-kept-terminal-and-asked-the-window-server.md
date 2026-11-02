# Every switch resized the kept terminal twice and waited on the window server

Found: 2026-11-02
Where: app/Sources/HubApp/TerminalPane.swift (makeNSView, GhosttyView.syncSize, backing)
Fixed in: the change that adds this file

With the Files column shown, a switch between agents took about 62 ms of main-thread time; `sample` showed a third of it in `GhosttyView.syncSize`, waiting on the window server.
Cause: each shown agent gets a new pane, whose host started at a placeholder 800 by 500 points; a kept terminal put in it was resized to that, then to the pane's real size, so its surface changed size twice on every switch.
Out of a window, its pixel size came from `NSScreen.main`, which ui-ux/0058 had added for terminals started out of sight, and which asks the window server each time.
Fix: the host starts at the size terminals settle at, a surface is given a size only when it changes, and the screen scale is the last window's, kept, not asked for.
With Files shown, a switch fell from about 62 to 40 ms (`FILES=1 app/scripts/measure-switch.sh`, waits counted as busy).
Lesson: a wait on the window server is main-thread time even though `sample` shows it in `mach_msg2_trap`; count only the run loop's own wait as idle, and never ask `NSScreen` on a path every switch takes.

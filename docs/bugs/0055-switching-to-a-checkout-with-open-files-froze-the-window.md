# Switching to an agent in a checkout with open files froze the window

Found: 2026-10-29
Where: app/Sources/HubApp/ContentView.swift (MainPanel's preview overlay), app/Sources/HubApp/AppModel.swift (checkoutFiles)
Fixed in: this change

Showing an agent in a checkout with files open in tabs, like a Terminal in the repo's checkout, froze the whole window for up to a second; between Orchestrators with no open files it was much shorter.
Cause: the preview overlay held only the shown checkout's open files, so leaving that checkout threw their views away and coming back laid every file out again, a long Markdown file with tables most of all, on the main thread.
Fix: every checkout's open files stay in the overlay, hidden while another checkout shows; a hidden one gets its checkout's files unwatched (`checkoutFiles(_:shown: false)`), so it never stops the shown checkout's watcher.
Measured on a copy of a 3,544-file repo with two files open: main-thread busy time on that switch fell from a median of 327 to 143 samples, and other switches stayed as they were.
Keeping every recent checkout's file list as well bought nothing on top and slowed other switches, so it was left out.
Lesson: measure a switch with `sample` on a test copy (main-thread samples not in `mach_msg2_trap`), several runs each, before and after; single runs vary by 2 to 3 times.

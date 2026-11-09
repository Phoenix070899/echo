# A screen parser panic froze its terminal for good

Found: 2026-11-09
Where: crates/hub/src/pty.rs (output, adopt, resize)
Fixed in: the change that adds this file

a34 (a Normal session) stopped drawing in Echo and its Claude Code hung, while Echo felt slow.
The daemon log showed one panic in vt100 (`grid.rs:689`, `col_wrap`), then a PoisonError panic on every later screen read and resize of that terminal.
Restarting the daemon did not help: adopting a34 replayed the holder's tail into a new parser, which panicked again and took the new daemon down.
Cause: vt100 0.16 panics when a one-row screen wraps a line, and an attached client had resized the terminal to one row.
The panic happened under the parser's lock, so the lock was poisoned and the terminal's output reader died; the holder then blocked sending that terminal's output, so its program blocked writing to its PTY.
Fix: the parsed screen keeps two rows at least, whatever size the terminal is; and a parser panic is caught, the screen starts over blank, and output keeps flowing.
Lesson: never let third-party parsing run unguarded under a lock that a terminal's output depends on; a bad byte must cost a redraw, not the terminal.

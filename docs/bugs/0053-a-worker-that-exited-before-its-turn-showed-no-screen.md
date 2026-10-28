# A Worker that exited before its turn started was reported with an empty screen

Found: 2026-10-28
Where: crates/hub/src/daemon.rs (start_worker)
Fixed in: the change that adds this file

`echoctl worker start` said "w2 exited before starting its turn:" and nothing after it, so whoever started it could not tell why.
Cause: the start read the screen from the Worker's live terminal, which the exit had already taken off the daemon's list.
Fix: when the terminal is gone, the start takes the last screen from the exit message the daemon kept.
Lesson: anything read after a process may have exited comes from what the exit recorded, not from the live terminal.

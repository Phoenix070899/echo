# A blocked Worker closed when its report was delivered

Found: 2026-11-16
Where: crates/hub/src/daemon.rs (`echoctl wait`)
Fixed in: the change that adds this file

w1031 and w1034 reported `blocked` and were closed six seconds later, so they left `echoctl worker list` while they still needed the human.
Cause: features/0090 superseded the close at delivery from features/0056 and says a blocked Worker stays open, but the code that closes a branchless Worker once `echoctl wait` delivers its `done` message stayed, and a `blocked` report is a `done` message too.
Fix: delivering a message closes nothing; a done Worker closes through `close_when_done` only.
Lesson: when a decision supersedes another, find and remove the code the old one added, and test the case the new one keeps open.

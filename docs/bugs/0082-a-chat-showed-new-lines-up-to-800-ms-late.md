# A chat showed each new line up to 800 ms late, and its Working row moved in jumps

Found: 2026-11-15
Where: app/Sources/HubApp/ChatView.swift, crates/hub/src/daemon.rs (`chat.read`), crates/hub/src/pty.rs
Fixed in: the change that adds this file

The human said streaming from the terminal to the chat did not feel fast or smooth; `app/scripts/measure-chat.sh` measured 411 ms median and 807 ms slowest from a transcript line being written to Echo reading it.
Cause: a shown chat polled `chat.read` every 800 ms, and the Working row's spinner and step came on the same poll; the terminal path itself forwards every chunk as it comes.
Fix: `chat.read` takes `wait` and `state` and is held until the transcript grows or the Working state changes, woken by the terminal's output (features/0088); new rows fade in (ui-ux/0133). The same script measures 0 ms median and 1 ms slowest.
Lesson: a view that follows something the daemon already sees change asks the daemon to answer when it changes, not on a timer; measure the delay with `measure-chat.sh` before and after.

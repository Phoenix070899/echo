# A Worker that finished its work but skipped its Final Report showed as failed

Found: 2026-10-24
Where: crates/hub/src/daemon.rs (on_exit, rows), crates/hub/src/screen.rs (turn_ended)
Fixed in: the change that adds this file

bash Workers printed their report on screen and stopped at the input box without `hub done`; the Orchestrator read the screen and closed them, and Echo listed them as Failed in red.
Cause: every exit of a live Worker settled as `exited`, whether it died mid-turn or finished its turn and was closed.
Fix: an exit while the screen shows a finished turn at the input box settles as `ended`, keeps the last screen as the report, and is not trouble (features/0029).
Lesson: tell "stopped after finishing" from "died while working" by the screen at exit before calling an exit a failure.

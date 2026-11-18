# The usage check saved a Claude session every five minutes

Found: 2026-11-18
Where: crates/hub/src/daemon.rs (`run_usage`)

Echo reads the plan's limits with `claude -p /usage` every 5 minutes, and each run was saved as a session: 2,970 of them (93 MB) piled up in the human's `~/.claude/projects`, and each one fired every SessionStart hook the human has (notch apps, graft, ADHD mode).
Cause: `/usage` is a local command, but a `-p` run is still a full session unless told otherwise.
Fix: the check runs with `--no-session-persistence` and `--settings '{"disableAllHooks":true}'`.
Lesson: anything the daemon runs on a timer through an agent CLI runs without saving a session and without the human's hooks.

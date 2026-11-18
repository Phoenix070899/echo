# Cancelling a Profile draft waited for what the CLI had started

Found: 2026-11-16
Where: crates/hub/src/daemon.rs (draft_profile)

Caught while building: `profile.draft.cancel` killed the drafting CLI, but the call still took 30 seconds to fail as cancelled.
Cause: the CLI had started a child (the test's `sleep`, a real CLI's helpers) that kept its stdout open, and the daemon waited to read that pipe to its end.
Fix: the CLI runs in its own process group, a cancel or timeout kills the whole group, and the output is read only once the CLI ended on its own.
Lesson: to stop a CLI you spawned, stop its process group, and never wait on a pipe its children may still hold.

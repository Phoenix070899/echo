# Codex listed no models: its output filled the pipe while the daemon waited for it to exit

Found: 2026-11-15
Where: crates/hub/src/accounts.rs (`run`), crates/hub/src/models.rs
Fixed in: the change that adds this file

Settings' model picker for Codex was empty, and the daemon log said "`codex debug models` took over 15 seconds", though it takes 40 ms in a shell.
Cause: `run` read the child's output only after it exited; `codex debug models` prints 300 KB, more than the 64 KB pipe holds, so Codex waited for a reader and the daemon waited for Codex until the limit killed it.
Fix: a thread reads the output while the child runs; the fake agent's catalog is as large as the real one.
Lesson: when running a child with piped output under a time limit, read the pipe while it runs; never wait for its exit first.

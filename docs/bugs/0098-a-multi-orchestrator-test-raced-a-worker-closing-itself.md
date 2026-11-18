# A multi-Orchestrator test raced a Worker closing itself

Found: 2026-11-18
Where: crates/hub/tests/daemon.rs (`a_repo_runs_several_orchestrators_and_each_hears_only_its_workers`)

The test failed about one run in four under a full `cargo test`: it waited for w1's phase to be `done`, then expected `worker list` to show it, but a done Worker closes itself once its turn ends (features/0090), and a closed Worker is not listed.
Cause: the test was written before Workers closed themselves, and a slow machine let the close land between the two checks.
Fix: the test starts w1 with `--keep`, so it stays listed after it settles.
Lesson: a test that lists a Worker after it is done starts it with `--keep`.

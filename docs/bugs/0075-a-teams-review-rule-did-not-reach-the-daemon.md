# A Team's review rule shaped the Orchestrator's prompt, but the daemon verified by the human's setting alone

Found: 2026-11-14
Where: crates/hub/src/daemon.rs (`start_worker`, `start_verifier`), crates/hub/src/launch.rs (the prompt's rules), crates/hub/src/settings.rs (`Rules::with_team`)
Fixed in: the change that adds this file

Found while building Team Members. A Team with `rules.review: false` told its Orchestrator to skip the verifier, yet a Worker started with `--verify` was still verified when the human's Settings had review on. The reverse held too: a Team with `review: true` over a human's `review: false` told the Orchestrator to verify, and the daemon did not.
Cause: the prompt was built from the human's rules with the Team's laid over them (`Rules::with_team`), but `start_worker` read the human's Settings alone to decide whether `--verify` takes effect, so the same rule had two readers that could disagree.
Fix: `start_worker` builds the rules the same way as the prompt (the human's, then the Team's present keys over them) from the Team of the Orchestrator starting the Worker. A Team that leaves `review` out still follows the human's setting, and a Worker with no Orchestrator or no Team reads the human's as before (features/0086).
Lesson: when a setting shapes the prompt and also gates what the daemon does, resolve it in one place with the same layers (the human's, then the Team's), so what the Orchestrator is told and what happens cannot differ.

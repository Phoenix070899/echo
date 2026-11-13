# A resumed Kiro Worker was sent its first Task after it had been given a later one

Found: 2026-11-13
Where: crates/hub/src/daemon.rs (`resume_worker`, `resume_message`, `next_task`), crates/hub/src/db.rs (`insert_task`, `current_task`), crates/hub/src/profile.rs (`resumed`)
Fixed in: the change that adds this file

Found by review of the fix for bug 0070. A Kiro Worker that had finished its first Task and then taken `worker next`, or been sent back by a verifier with feedback, and was resumed afterwards, was told "Your Task:" followed by the first Task it had already finished.
Cause: the resume message took the Task from `workers.spec`, which is written once when the Worker starts; `next_task` only stored the new Task as an input and typed or launched it. Bug 0070's fix did not ask which Task was current.
Fix: an input that gives a Worker a Task (its first, a next one, a verifier's feedback) is stored with a `task` mark, and a resume sends the latest marked one, falling back to `workers.spec` when none is marked (features/0079). `workers.spec` stays the Task it started with, so the verifier's prompt is unchanged. The 4000-character bound, and Claude's and Codex's resume message, are as before.
Lesson: when a message repeats "the Task", take it from the record that says which Task is current now, not from the one written at the start; and when two kinds of input share an origin, mark the kind where it is stored instead of guessing it from the origin later.

# A Worker that finished kept its question in Needs you

Found: 2026-11-03
Where: crates/hub/src/db.rs (settle, set_state, open)
Fixed in: the change that adds this file

w712 asked the human to allow `gh pr merge` (question #942), saw the PR merged by someone else, sent `echoctl done`, and was closed.
Its question stayed in Needs you with a Reply box, and picking it showed "w712 is gone"; the Orchestrator's `echoctl inbox` listed it too.
Cause: settling a Worker changed only the Worker's row; its unanswered questions stayed open, and Needs you and the inbox list every open question whatever its Worker's state.
Fix: a Worker that settles (done, blocked, exited, ended, lost) withdraws its open questions: they get the answer "(withdrawn: the Worker settled before an answer)", and `echoctl reply` to one says it was withdrawn. Opening the database withdraws the ones settled Workers already left open.
Lesson: when a Worker settles, close everything that waits on it, not only its own row.

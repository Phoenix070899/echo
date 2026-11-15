# A done Worker closes once its turn ends, branch or not, unless started with --keep

Decided: 2026-11-15
Status: accepted
Supersedes: features/0056, its close at delivery and its rejection of closing at `echoctl done`; and features/0042, only its "stays open after its Final Report": the branch's Worker still takes every later Task on that branch.

A Worker that reports done is closed by the daemon as soon as its screen shows the turn ended at the input box, or 30 seconds after `echoctl done` at the latest (`CLOSE_DONE_WITHIN`).
A writer under verification closes once its verdict is delivered.
Started with `--keep`, it stays open; a blocked Worker stays open too.
Closing keeps its worktree, branch, Final Report and session: `echoctl worker task` resumes its session on the next Task and it is open again, and the message still reaches `echoctl wait`.
Echo's Done list keeps it five minutes as before (features/0030).
Why: the human wants finished Workers gone from `echoctl worker list` the moment they finish, not left open until the Orchestrator reads the report or the branch merges.
Rejected: closing at the moment of `echoctl done`, which kills the CLI while it is still writing its last turn.

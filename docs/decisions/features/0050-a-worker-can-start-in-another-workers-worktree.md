# `--worktree worker:w12` starts a Worker where Worker w12 works

Decided: 2026-11-11
Status: accepted

`echoctl worker start --worktree worker:<w id>` starts the new Worker in the folder of that Worker, in the same repo, on no branch of its own (as `path:` does).
It fails naming the Worker when it does not exist, belongs to another repo, or its folder is gone; `worker:feat` or any id that is not `w<N>` is refused with the form it expects.
`orchestrator.md` uses it to start a `sasuke` on a writer's commits; `worker list --json` is no longer named there, and stays as it is for Echo.
Why: the Orchestrator listed every open Worker as JSON, with each one's Final Report and session id, only to read one `cwd` out of it; the list stayed in its context for the rest of the session.
Rejected: putting the cwd in the text listing, which every `worker list` would then pay for; matching a Worker by branch, which a Worker in place does not have.

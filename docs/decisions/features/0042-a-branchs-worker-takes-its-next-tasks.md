# A writing Worker on its own branch takes every later Task on that branch until it is merged

Decided: 2026-10-31
Status: accepted

A writing Worker in its own worktree stays open after its Final Report, and the Orchestrator closes it only once its branch is merged or dropped.
Every follow-up on that branch goes to it with `echoctl worker task <w> --spec-file <file>`: a retry with sasuke's findings, the human's review, a CI failure, PR comments, a rebase.
`echoctl worker task` types the Task in at its input box when its terminal is open, else resumes its Claude session on it; either way the Worker is running again and reports with its own `echoctl done`.
A running Worker takes no next Task; short Tasks that stand alone still get a new Worker, and sasuke still reviews in a Worker of its own.
A settled Worker kept this way does not count toward the Workers that run at once.
Why: a new Worker re-reads the code and starts a cold prompt cache (about 30k tokens written per start, measured 2026-10-31); the branch's Worker already holds the change in its context, and the prompt cache only carries over within one session.
Rejected: forking the Orchestrator's session for each Worker, which only hits the cache when model, tools, and system prompt all match the Orchestrator's, and fills the Worker with the Orchestrator's unrelated history.

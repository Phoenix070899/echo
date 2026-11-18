# The Orchestrator runs short commands itself

Decided: 2026-11-16
Status: accepted

`orchestrator.md` no longer sends every project command to a `lee` Worker.
The Orchestrator runs short commands itself: builds, lint, the tests a change touches, `git` reads, quick scripts, and a merge the human approved, keeping their output small (`tail`, or grep the failures).
A `lee` Worker gets only commands that run long (a full test suite, or over about two minutes), start a server, or print far more than the Orchestrator needs.
A command that changes files (a formatter, code generation, a commit) is an edit and still goes through a Worker; the Orchestrator never edits files.
A command that installs, migrates, pushes, or starts a server still needs the human's "go", whoever runs it.
The `run` Action's routing line says the same, so a Team's `run` Member is picked for long or loud commands.
Why: starting a Worker costs many tokens of contract, Preferences and Lessons to run a command that takes seconds.
Rejected: keeping every command with `lee`, which spends a Worker per command; letting the Orchestrator run anything, which fills its context with long logs and lets it change files without a Worker.

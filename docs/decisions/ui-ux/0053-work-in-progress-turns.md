# Work in progress shows a turning mark

Decided: 2026-10-29
Status: accepted

Anything Echo is waiting on shows `Spinner` (Theme.swift), an arc turning once a second, in the colour of what it stands for.
A running or starting Worker's mark is the spinner in the running colour, in the ledger, the collapsed rail, the Worker header and the fan-out list; one waiting on background work turns slower (2.4 s); one that needs the human, or has settled, keeps the still square.
Every "Reading…", "Searching…" or "Starting…" line has the spinner before it (`Pending`), as do the start button while an agent starts, Changes while it loads, and Claude usage while it is read.
Under Reduce Motion the arc stands still.
Only this one mark is used, so a turning arc always means "in progress".
Why: the human wanted every in-progress state to look alive, not only to say so.

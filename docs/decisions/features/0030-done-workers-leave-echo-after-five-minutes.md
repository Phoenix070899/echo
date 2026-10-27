# Done Workers leave Echo's Done list after five minutes, read or not

Decided: 2026-10-25
Status: accepted
Supersedes: features/0002, only its 7-day keep for Final Reports; dismissing and read state stand.

A done, ended, or failed Worker leaves Echo's snapshot five minutes after it settles (`KEEP_REPORTS_SECONDS`), whether its report was read or not.
A blocked or lost Worker still needs the human, so it stays for 7 days (`KEEP_NEEDS_SECONDS`) unless dismissed.
The database keeps every Worker; `echoctl status` for the Orchestrator still drops settled ones after ten minutes.
Why: the human wants the Done list to clear itself instead of filling up with old reports.
Five minutes, not longer, because the Orchestrator already reports each result to the human; the Worker row is only a glance.

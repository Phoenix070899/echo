# A running Worker's row always has its status line

Decided: 2026-10-29
Status: accepted

Supersedes: ui-ux/0039's "with no status" clause for running Workers; the rest of 0039 stands.
A running Worker's second line always shows a status: its latest progress, else "Waiting on background work", "Needs you", "Starting", or "Working".
A change of status changes the words in place; the line never appears or goes, so the row keeps its height and the ledger below it never moves.
Settled Workers keep 0039's rule: a second line only for Failed, Blocked, or Ended, or their branch.
Why: the line came and went as a Worker moved between running and waiting, and every time the sidebar's layout jumped.

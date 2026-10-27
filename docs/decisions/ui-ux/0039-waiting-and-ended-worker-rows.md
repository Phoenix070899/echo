# Waiting and Ended Worker rows

Decided: 2026-10-24
Status: accepted
Supersedes: ui-ux/0014, only its line on what the second line says; its other rules still hold.

A Worker row's second line shows its branch, then its latest status; with no status, it says "Waiting on background work" for a Waiting Worker, "Ended, no Final Report" for an Ended one, or Failed or Blocked when it settled badly.
A Waiting Worker sits under Running with the running mark, and its label (row tooltip, Worker header, fan-out list) reads "Waiting".
An Ended Worker sits under Done with a grey (`ink3`) mark and an ink title, not the failed red.
Echo Remote shows the same states: a Waiting chip in the running colour and an Ended chip in grey.
Why: the human asked for a status that tells "busy in the background" and "finished without a report" apart from "needs you" and "failed" (features/0029).

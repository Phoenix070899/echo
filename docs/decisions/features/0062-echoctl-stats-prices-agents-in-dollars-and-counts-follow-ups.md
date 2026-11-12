# echoctl stats prices every request in dollars and counts the follow-ups a kept Worker takes

Decided: 2026-11-11
Status: accepted

`echoctl stats` prices each request at its model's list price and reports dollars: in total, Workers against Orchestrators, per profile, and per Orchestrator session; the token-equivalent shares stay as they were.
The prices sit in one table in `stats.rs` (Opus, Sonnet and Haiku 5.5, Fable 5.1, checked 2026-11-11), each standing for its whole family; Haiku costs five times as much past 100k tokens, and any other model costs nothing.
A follow-up is text typed or pasted into a Worker after its `echoctl done`: a next Task (features/0042), a review, or the human. Stats counts them and the median context the first request after each one already holds.
Stats also counts Claude Code's compactions (`compact_boundary` entries) across Worker transcripts.
The Orchestrators' per-session column that showed the cold requests' share of cost is now headed "cold cost", beside a "dollars" column.
Why: the token-equivalent weights treat an Opus request like a Sonnet one, so they cannot say whether Workers or Orchestrators cost more; and the planned cuts (renewing a kept Worker, compacting earlier) need a count of follow-ups and compactions to be judged.
The 14-day baseline before those cuts, from the transcripts in token equivalents: Workers 625M (88%), Orchestrators 85M; naruto 489M (69% of all), with 46% of its cost after its first Final Report, follow-ups carrying a median 265k context, and 18 compactions in 127 sessions.
Rejected: telling follow-ups apart by the text of the Task, which `echoctl worker task` types in as given, with no marker.

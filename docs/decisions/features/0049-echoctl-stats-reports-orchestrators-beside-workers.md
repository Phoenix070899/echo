# `echoctl stats` reports Orchestrators beside Workers, from their own transcripts

Decided: 2026-11-11
Status: accepted

`echoctl stats` adds an `orchestrators` object to its JSON and a second section to its text; every Worker number and its place stays as it was.
An Orchestrator counts for the window if it was open at any time in it (an Orchestrator lives as long as its session, so its start date says nothing); only requests sent in the window count, and Normal sessions are left out.
Per session and in total it reports: requests; context per request (first, median, last); the cache write lifetime used (5 min, 1 h, mixed); cold requests and their share of cost; the gap before each cold request; what woke each request, with how many of those were cold and what they cost; and the size of tool results by `echoctl` command (`wait`, `worker list`, `worker read`, and the rest).
A request is cold when its context is over 20k tokens and under 10% of it was read from the cache; the first request of a session is never counted as cold.
The gap is the time from the end of the previous answer to the arrival of what woke the request, taken from the transcript's timestamps; cold requests are bucketed as under 5 min, 5 min to 1 h, and over 1 h, so a listener that times out at the cache lifetime shows up as a cold wake in "over 1 h" and under "empty wait".
"Woken by" is the `echoctl` command or tool whose result arrived last; a background task's completion is "notification", a listener that returned `No messages in …s` is "empty wait", and a typed message is "human". Tool-call names come from the transcript, so a result of a background `wait` that Claude Code hands over as a notification is counted under "notification", not under "wait".
Costs use the weights of the Worker report (cache read 0.1, cache write 1.25 for 5 min or 2 for 1 h, output 5, in input-token equivalents).
Echo's title bar and popover (ui-ux/0056) are not changed: they read the Worker numbers only.
Why: the changes meant to cut an Orchestrator's token use depend on whether its wakes are warm or cold, and which lifetime the cache uses; nothing measured Orchestrators before, so every proposal was a guess. The numbers come from the transcripts the CLI already reads, so no new data is kept.
Rejected: counting by `created_at` like Workers (misses a long-lived Orchestrator); a daemon-side log of wakes (a second source that can disagree with what the model was billed for).

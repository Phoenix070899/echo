# The Orchestrator's wait gathers messages for five seconds and a status alone does not wake it

Decided: 2026-11-11
Status: accepted

`echoctl wait` returns once a message of any kind but `status` has waited five seconds for others, with every undelivered message then waiting; a `status` is delivered along with the next message that wakes it.
The five seconds apply from the first waking message; if the wait's own timeout runs out during them, what woke it is still returned.
`HUB_COALESCE_MS` shortens the hold for tests.
Why: every wake costs the Orchestrator its whole context at cache-read price, or at write price when its cache went cold; Workers' messages arrive in bursts (a done, then its next question), and a status tells the Orchestrator nothing to act on.
Rejected: a longer hold, which slows the human's answers to a question; dropping statuses, which the human still reads in Echo.

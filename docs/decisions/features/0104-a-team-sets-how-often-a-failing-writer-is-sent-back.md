# A Team sets how often a failing writer is sent back

Decided: 2026-11-16
Status: accepted

Builds on features/0086 (verification by the daemon).
A Team's `rules.verifyRetries` (1 to 10) is how many times the daemon sends a `--verify` writer back with the verifier's findings after a `fail` verdict; without it the writer is sent back once, as before.
After that many failed retries the Orchestrator hears "failed again after N retries: needs the human" with the findings.
When a Team sets it to other than 1, the Orchestrator's prompt says so in its rules lines, since `orchestrator.md` says once.
Settings > Teams shows it in Rules as a stepper, "Send a failed writer back up to N times", cleared with the other rules by Use my settings; the human's own Settings have no such rule.
Why: a Team for heavy work loops the writer and verifier until the verifier passes, without the human stepping in each round.
Rejected: no limit, which can spend tokens without end on a Task that cannot pass; a global setting, which no one has asked for.

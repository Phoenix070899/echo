# A Task can end with another Worker's Final Report, appended by the daemon

Decided: 2026-11-11
Status: accepted

`echoctl worker task <w> --from-report <w2>` appends `<w2>`'s Final Report to the Task verbatim, under the spec if there is one; the spec may be left out. It refuses when `<w2>` has no Final Report.
Why: the Orchestrator copied reports (a verifier's findings, a review) into spec files by hand, which costs output tokens at the highest price and can drift from what was reported.
Rejected: a free-form "include whatever" mode; only a Worker's Final Report is appended.

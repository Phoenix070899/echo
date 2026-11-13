# Kiro denies a permission prompt with Down and Enter, never Esc

Decided: 2026-11-13
Status: accepted

`Cli::deny_keys` for Kiro is Down then Enter, which picks "Deny once", the second row; `Cli::approve_keys` is Enter on "Allow once" for every CLI.
Esc on a Kiro prompt cancels the whole turn, not only the request, so Echo never sends it to Kiro: not in `decide`, not in the hint a Worker's blocker message gives the Orchestrator (`down enter`), and not in `kiro-notes.md`.
Why: the Worker should go on and be told what to do instead, as it is after an Esc on Claude or Codex.
Rejected: Esc, as for the other CLIs.

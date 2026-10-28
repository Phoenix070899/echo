# The sasuke Profile told Workers to finish with `--outcome`, a flag `echoctl done` does not have

Found: 2026-10-28
Where: profiles/sasuke.md, worker-contract.md
Fixed in: the change that adds this file

Reading the Profiles to make them neutral showed sasuke's role saying `--outcome succeeded` or `--outcome failed`; `echoctl done` takes only `--state done|blocked`, so a verifier that followed its role got an error from `echoctl done`.
Cause: the flag was renamed in the CLI and the Profile's text was not.
Fix: sasuke now says `--state done` for any verdict, even `fail`, and `--state blocked` when it could not verify.
Lesson: when an `echoctl` flag changes, grep `profiles/`, `worker-contract.md`, `orchestrator.md`, and `skills/` for it in the same change.

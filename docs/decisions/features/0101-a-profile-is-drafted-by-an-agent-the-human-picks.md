# A Profile is drafted by an agent the human picks, and lands as unsaved edits

Decided: 2026-11-16
Status: accepted

Builds on features/0099 and ui-ux/0145.
The daemon method `profile.draft` runs one headless call on the CLI and model the human picks (`claude -p`, `codex exec`, `kiro-cli chat --no-interactive`), with no tools and no writes, at medium effort where the CLI takes one, on the account agents run on.
It is shown the human's request, the form as it stands (unsaved edits included), the Worker Contract, the other Profiles' descriptions, Echo's own `hinata` role as the shape to follow, Echo's tools list, and the skills installed for the Profile's own CLI.
It may set the description, tools, skills, context, writes and role; the CLI, model and effort stay the human's.
The reply is one JSON object; a field it leaves out keeps the form's value, a tool or skill Echo does not offer is dropped and named back, and a reply with no role is refused.
The draft fills the form as unsaved edits; nothing is written until the human saves.
It gives up after 120 seconds, and `profile.draft.cancel` with the draft's id stops it and whatever it started.
There is no `echoctl` command for it until one is needed.
Why: writing a Profile from scratch is hard; the human says what they need and reviews what an agent proposes.
Rejected: a visible Worker editing the file, which is slower and writes before review; a fixed Claude model, since the human picks from the providers they have.

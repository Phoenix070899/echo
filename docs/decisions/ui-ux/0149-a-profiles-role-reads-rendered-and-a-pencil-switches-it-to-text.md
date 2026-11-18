# A Profile's role reads as rendered Markdown, and a pencil switches it to its text

Decided: 2026-11-16
Status: accepted

Supersedes: ui-ux/0145's "its role as a large text field".
In Profiles, the role shows as rendered Markdown in a 1 pt frame, the way a Final Report reads, with a pencil toggle at the right of its label: a 26 pt square in a 1 pt rule, filled in ink while editing.
Pressing the pencil turns it into the large mono text field; pressing it again renders the text again, keeping any unsaved edit, which Save or Revert settle as before.
Picking another Profile opens it rendered; New Profile opens it in the text field, since its starter role is there to be rewritten.
Echo's own Profiles have no pencil, as the rest of their fields are read-only.
An empty rendered role says "No role yet. Press the pencil to write one."
Why: the human reads a role far more often than they change it, and wants a clear switch for editing it in Echo.
Rejected: always a text field, which reads poorly as a prompt; editing in an external editor, which Open file already does.

# A Profile's Skills are a checklist of its CLI's skills, grouped by where each comes from

Decided: 2026-11-15
Status: accepted

Builds on ui-ux/0145; it replaces the Profile editor's comma list of skill names.
Under "Skills and context", Skills is a checklist of the skills `skills.list` gives for the Profile's CLI: its own CLI, else the one it runs on here.
Rows are grouped under small headings in this order: Yours, This repo, each plugin by name, then Built in; each row is a Foundry checkbox at the Tools checklist's size, with the skill's description under it in two lines at most, and in full as help text.
Over ten skills, a filter field above the list keeps the rows whose name or description has the text.
A skill the Profile names that the CLI does not have stays checked under Not installed, first, marked "Not installed", so saving never drops it unseen; unchecking it drops it.
Checking a skill adds it last; unchecking keeps the others in their order, so the file changes only where the human did.
A CLI with no skills shows one plain line saying so ("Kiro has no skills.").
Echo's own Profiles show the checklist disabled, as the rest of their fields.
Context stays a comma list.
Why: the human picks from what is installed instead of typing names that must match exactly, including a plugin's `<plugin>:` prefix.
Rejected: a picker of one skill at a time, which hides what is checked; hiding skills the CLI lacks, which would drop them on the next save.

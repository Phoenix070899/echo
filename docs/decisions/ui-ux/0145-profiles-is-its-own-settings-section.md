# Profiles is its own Settings section, after Teams

Decided: 2026-11-15
Status: accepted

Supersedes: ui-ux/0101's "there is no Agents section" and its button that opens a Profile's role, and ui-ux/0101's list of sections, which gains Profiles as 07 after Teams; the sections after it move down one.
The Profiles section is laid out like Teams (ui-ux/0121): the list on the left grouped as Yours, This repo and Shipped by Echo, the picked Profile in the middle, and a bar with Revert and Save under both.
The picked Profile shows every field in place: description, CLI, model, effort, tools, skills, context, lessons, writes, worktree, and its role as a large text field; Save writes its file.
Under CLI, model and effort a note says a Team's node or its Workers default replaces them.
Echo's own Profiles are read-only, with Make my copy, which asks Yours or This repo, as Echo's own Teams are (ui-ux/0100).
New Profile asks for a name and a level and opens a blank Profile with a short starter role; Duplicate copies any Profile; Delete follows features/0096.
"Used by" lists the Teams and Members that start from the Profile, read-only; Open file opens its Markdown.
In Teams, a Member's inspector edits its id, Action, Profile, Hand-offs, CLI, model and effort, and shows the rest of its Profile read-only with Edit in Profiles, which opens this section on that Profile.
`echoctl ui settings profiles` shows it.
Why: the human wants one place to see and change what each Worker is, and a Team to hold only the flow and what each node runs on (features/0094).
Rejected: Profiles inside the Teams section, which crowds the canvas's page; a raw Markdown editor, which leaves the fields' checks to the human.

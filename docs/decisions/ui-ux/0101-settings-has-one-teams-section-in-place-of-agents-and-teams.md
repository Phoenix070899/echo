# Settings has one Teams section in place of Agents and Teams

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0043 (the Agents tab's content) and ui-ux/0099 (the Teams page after Agents), because the two pages set the same things twice: models and effort, and the Orchestrator's rules.
Supersedes: ui-ux/0044's list of sections, which gains Teams in place of Agents, and ui-ux/0044's and ui-ux/0045's 680 pt column, for this section only; every other section stays as 0044 and 0045 say.
Settings lists Teams where Agents was, and there is no Agents section and no separate Teams page.
The Teams section uses the whole width of the window beside the section list, in three parts from left to right: the Teams list, the tree with the palette above it, and the inspector of what is selected.
The Teams list holds the Teams the selected repo can use, each with its origin in grey, with New, Duplicate and Delete under it, as ui-ux/0099 had them.
A Defaults entry stands at the top of the list; selecting it shows the default CLI and model every agent starts with, the `forceCli` switch (features/0075), and the Orchestrators' default rules and renewal size, which a Team's own rules replace (features/0081).
Selecting a Team shows its tree: the Orchestrator at the root and its Members under it (features/0084), with the Orchestrator's inspector holding its CLI, model, effort, renewal size, rules and instructions, and a Member's inspector holding the Member's fields.
The palette above the tree holds a chip for each Action (features/0087), one for each shipped Profile, and Custom.
Edits are held in a draft with Save and Revert until saved; ui-ux/0100 stands, so a shipped Team is read-only and is duplicated to change it.
A field left empty shows what it falls back to, and where that comes from.
Editing a Profile's role is a separate button that says it changes every Team.
`echoctl ui settings agents` stays accepted and shows the Teams section; `teams` is the new name.
Why: the human asked for one place to set up the Orchestrator and all its Workers, and a Team is that setup; a Profile's fields and the Team's per-Profile fields were the same choices on two pages.
Rejected: keeping both pages and linking them, which leaves two places to set one model; a tree inside the 680 pt column, which has no room for the tree and an inspector side by side.

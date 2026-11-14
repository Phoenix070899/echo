# The Teams section is a list with the section's head, a tree on a spine in columns, an inspector, and a bar with Save

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0101's palette above the tree and its Save and Revert inside the inspector, and ui-ux/0099's look of the list rows; everything else in both stands.
The left column, on the desk, carries the section's head ("06 / Settings" and "Teams" in display capitals), Defaults, then the Teams grouped as Yours, This repo and Shipped by Echo; each row is the name in bold over its description, with a square accent dot while it has unsaved edits and its problem in red.
New Team, Duplicate and Delete stay under the list (ui-ux/0099).
The middle column heads the Team with its origin as a badge, its name in display capitals, its number of Members, and a bar of the model families its Orchestrator and Members run on, each as wide as its share.
The tree hangs from a 2 pt spine: each row is a square node with the Action's two capitals (the Orchestrator's solid ink), stepped 30 pt per level, then fixed columns for the Action and id, a framed Profile and model with its family's mark, and the effort the row resolves to.
The picked row is the sunk grey with a 3 pt accent edge and an accent-framed node; a Member edited since the Team was saved shows "Changed" on the highlighter.
Under 600 pt the tree's margins, steps and columns narrow so the names keep room.
The right column is the inspector, 300 pt: "Orchestrator" or "Picked Member", the row's name in display capitals and where it sits, then its fields as mono capital labels over square controls.
A bar under the tree and the inspector says how many edits are not saved, with Revert and "Save <name>"; a shipped Team shows Duplicate there instead (ui-ux/0100), and the daemon's refusal shows there in red.
Teams are not given a default badge, and Teams without a description show none: Echo has no default Team, and only the Team files say what they are for.
Why: the human approved the Settings Teams artboard; the tree reads as a plan at a glance and Save sits where the edits it counts are seen.

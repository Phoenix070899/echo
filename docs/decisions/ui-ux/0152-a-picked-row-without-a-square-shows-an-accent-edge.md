# A picked row in a list without squares shows a 3 pt accent edge that moves nothing

Decided: 2026-11-16
Status: accepted

Supersedes: ui-ux/0124, only "no accent bar or edge marking a picked row"; ui-ux/0127, only that a row without a square changes only its fill when picked; ui-ux/0132, only that the Settings section list and the Teams list show the picked row by fill and bold ink alone. Everything else in them stands.
In a list whose rows have no grey square, the picked row keeps its fill and also shows a 3 pt `Ledger.accent` edge on its leading side (`pickedEdge` in Foundry's `Marks.swift`).
The edge is laid over the row, not beside it, so the row's text and marks stay where they are when it shows or goes.
It marks the picked row only; a hovered row still changes its fill alone.
Lists with it: the sidebar's repo and agent rows, the collapsed rail's agents and Workers, the Settings section list, the Teams list, the Profiles list, the Files column's commit and changed-file rows, popover menu rows and Quick Open, the base-branch picker, the slash-command list, and New Team's starts.
A list whose rows have grey squares never shows the edge; its picked row is still shown by its square turning the accent (ui-ux/0127): the sidebar's Worker rows, the Files tree, the Members tree, the branch rows of Start from, and the repo rows of Start a session.
Why: the human asked for an orange left border on every selected item, with no text moving, and none in lists that already mark rows with a square.

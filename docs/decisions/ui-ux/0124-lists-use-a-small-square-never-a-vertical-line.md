# Lists use a small square, never a vertical line

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0109, its spine and accent edge, already replaced in the sidebar by ui-ux/0111; ui-ux/0118, only the Files tree cursor's 3 pt accent edge; ui-ux/0119, only the picked repo's accent edge; ui-ux/0120, only the picked section's 3 pt accent bar; ui-ux/0121, only the tree's 2 pt spine and the picked row's 3 pt accent edge, including the picked Team's edge in the list. Everything else in these decisions stands.
No list or tree in Echo draws a vertical line: no spine or guide beside nested rows, and no accent bar or edge marking a picked row.
A list row is marked by a 6 pt square at its leading edge, vertically centred on its first line: `Ledger.accent` on the picked or active row, the rule's grey on the others (`ListMarker` in `Theme.swift`, as the sidebar's Worker rows draw it per ui-ux/0111).
In the Teams tree a Member's square sits under its parent's node, centred on its own node; the Orchestrator's row has none.
In a diff only the cursor's line shows the square, in the accent; other lines show none.
Indentation still shows nesting.
Horizontal accent underlines of tabs (ui-ux/0114) and a reply's edge in the chat (ui-ux/0117) are not list markers and stay; so does a Markdown quote's rule.
Why: the human asked for lists to be marked by squares in place of every spine and accent bar, as the updated Settings Teams artboard draws them.

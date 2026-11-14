# A row's square turns the accent when the row is picked or hovered, and a row without a square never gets one

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0124, only that the grey square is the rule's grey and that only the picked row's square is the accent; ui-ux/0125, only the 6 pt accent square on the menu row under the pointer or picked with the arrows; ui-ux/0126 stands. Everything else in them stands.
A list row that has a grey square turns that square `Ledger.accent` while it is picked or while the pointer is over it; its fill may also change, as it did before.
A list row that has no grey square never gains one on hover or pick: only its fill changes.
The Settings section list and the Teams list keep the accent square on the picked row alone, as Foundry's artboard draws it (ui-ux/0126); hovered, their rows change fill only.
Popover menu rows (`FoundryPopoverItem`) and the base-branch picker's rows have no square: picked or hovered, they turn the sunk grey.
The grey square is `Ledger.square` (#8A857B in light mode), darker than the rule, as the artboard draws it.
Rows with a grey square: the sidebar's Worker rows, the Files tree, the Members tree's child rows and its Add row, the branch rows of Start from, and the repo rows of Start a session.
`ListMarker` reads `listRowHovered` from the environment; a row sets it with `.listRowHover()` (the sidebar's `TreeRow` sets it from its own hover), and the Files tree, drawn in AppKit, colours the hovered row's square itself.
A diff's cursor line keeps its accent square (ui-ux/0124); it is a cursor, not a hovered row.
Why: the human's rule, so a square always means "this row", and rows without one do not grow marks under the pointer.

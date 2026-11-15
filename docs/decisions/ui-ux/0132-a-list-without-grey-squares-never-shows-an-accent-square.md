# A list without grey squares never shows an accent square, even on its picked row

Decided: 2026-11-15
Status: accepted

Supersedes: ui-ux/0126, that the picked row of the Settings section list and of the Teams list carries the accent square; ui-ux/0127, only that those two lists keep the accent square on the picked row; ui-ux/0124, only that a diff's cursor line shows the accent square. Everything else in them stands.
A square is a mark a whole list carries: when a list's rows have grey squares, the picked or hovered row's square turns the accent (ui-ux/0127); when they have none, no row ever shows one, picked, hovered or under the keyboard's cursor.
The Settings section list and the Teams list show the picked row by its fill and bold ink alone.
A diff's cursor line shows by its fill: the sunk grey on a context line, and a shade darker than its own green or red on an added or removed line.
Why: the human saw the accent square on the picked Team and Settings section, in lists with no grey squares, and asked that no such list show one.

# Every floating panel in Echo is Foundry's popover, drawn by Echo in the window

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0113, only the picked row's 3 pt accent edge, and ui-ux/0122, only that Add Member and More open AppKit menus; their contents stand.
Every menu, picker and small report that floats over the window is one component, `FoundryPopover` in `FoundryPopover.swift`: the sheet grey in a 2 pt ink frame casting one hard 6 pt ink block, never rounded, never blurred, with no arrow.
Its parts are a mono capital head with an optional quiet detail at the right over a 1 pt rule, menu rows, group rules, a body for reports, and a quiet foot line.
A menu row is a 36 pt icon square in a 2 pt ink frame, a bold title over a one-line note, and an optional 40 x 22 key box; a long menu's rows may drop the icon and set the note beside the title.
The row under the pointer or picked with the arrows is the sunk grey with the 6 pt accent square (`ListMarker`); other rows have no square.
`FoundryMenu` draws a menu from entries: arrows pick, Return runs, Esc or a click outside closes, and a menu taller than the window scrolls.
Echo draws the panel in the window's own overlay (`.foundryPopover` on the control, `.foundryPopoverHost` on the window), never in an NSPopover, whose frame and arrow cannot be taken off; it opens under its control, or over it when there is more room there, and stays inside the window (`PopoverPlacement`).
On it now: the New session menu, the title bar's Workers report, the base-branch picker, and the Teams tree's Add Member and More menus.
Native menus stay native where they are a form control or the system's: context menus, the menu bar and its status panel, and the dropdowns of form fields (`SquarePicker`, `FieldMenu`).
Why: Foundry's Popover component, so a New session menu, an Add Member menu and a statistics report read as the same object.
Rejected: NSPopover with its frame hidden, which still draws its arrow and lands in a separate window.

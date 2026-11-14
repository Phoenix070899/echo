# New session opens Echo's own menu with an Orchestrator and a Terminal only

Decided: 2026-11-14
Status: accepted

The ledger's New session button is full width, solid ink casting a 3 pt accent block, with "NEW SESSION" and ⌘N in mono capitals.
It opens a menu Echo draws under it, not a system menu: "Start in <repo>" and the branch, then Orchestrator (⌘N) and Terminal (⇧⌘N), each with a 36 pt framed mark, what it does and its shortcut, then "In another repo? Choose a repo…".
The menu is the sheet in a 2 pt ink frame casting a 6 pt hard ink block (black in dark mode); the row under the pointer or picked with ↑ ↓ is the sunk grey with a 3 pt accent edge; Return starts it, Esc or a click outside closes it.
Fan Out a Task leaves this menu; it stays in File > Fan Out a Task… (⌥⌘N) and in Quick open (⌘K).
Why: the NewSessionMenu artboard; a system menu cannot be drawn in Foundry.
Rejected: ⌘T for Terminal as the artboard shows; Terminal keeps ⇧⌘N, the shortcut it already had.

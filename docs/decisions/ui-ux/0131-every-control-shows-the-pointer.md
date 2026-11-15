# Every control and row shows the pointer, by its square or by its fill

Decided: 2026-11-15
Status: accepted

Extends ui-ux/0127 from list rows to every control; supersedes nothing.
A row with a grey square turns that square the accent while hovered or picked (ui-ux/0127); nothing else gains a square.
Everything else clickable that has no fill of its own takes `Ledger.wash` while the pointer is over it, through `.hoverFill()` in `Theme.swift`: icon buttons, tabs not picked, segment choices not picked, tool-call rows in the chat, rail marks, square pickers and fields, the square checkbox's box, the colour well.
A picked tab, segment or row keeps its own fill; hover never changes it.
Lists the keyboard also walks (⌘K, the `/` commands, the popover, the base branch search) move their one highlight to the row under the pointer, so pointer and keys never show two rows.
A primary button moves halfway onto its accent block while hovered and all the way while pressed; a secondary button takes the wash; a text link turns the muted ink, as Foundry's `fd-btn` and `fd-link` do.
Corners stay square: the attachment chips, the side terminal's grip and the terminal's find bar lose their rounding.
Why: the human asked that every element's hovered and highlighted state follow the rule set for list rows.

# Echo copies Claude's app where it has the same element, and adapts it where it does not

Decided: 2026-11-12
Status: accepted

Supersedes: ui-ux/0080 for the radii, the greys and the shape of the sidebar, the message box, the tool calls and the header; its palette, the serif replies and the rest stand.
Same element in both apps, copied:
- The sidebar sits flat on the window (`Ledger.desk`, Claude's bg-200) with no sheet and no rule above its foot; the chat canvas beside it is `Ledger.paper` (bg-100). Its first row is "New session": a clay disc with a plus, then the label, as Claude's "New chat". Under it a small "Sessions" label stands for Claude's "Recents".
- Sidebar rows are 32 pt, 14 pt text, an 8 pt rounded fill when picked or hovered; a title too long runs out in a fade (`fadedEnd`), not an ellipsis.
- The human's message is a right-aligned bubble in `Ledger.bubble` (bg-300, darker than the canvas in dark mode), 12 pt radius, 16 by 12 padding, 15 pt text. The agent's reply is bare serif text, 15 pt on a 1.7 line.
- The message box has 16 pt corners, a half-point border and a soft shadow; the text sits on top, "+" (attach) at the bottom left, the model's name and a clay square send button at the bottom right. The placeholder is "Reply to Claude…".
- A tool call is a card with a half-point border and 12 pt corners: a symbol by what the tool does, its label, a chevron at the right; opened, a hairline and its detail. A run of calls is one card with a row each.
- The Working row leads with a clay mark; the Chat | Terminal toggle is a grey track with a white thumb, as Claude's.
- Panel headers sit on the canvas with no band.
Radii are Claude's: 6 chips, 8 rows and buttons, 12 bubbles and cards, 16 panels and the message box.
Adapted, with no Claude counterpart: Needs you cards (manilla wash, 12 pt), Workers (the same row as an agent, a status mark first), the repo line with its amber count, the Files column and the terminal. They take Claude's tokens and radii only.
Why: the human wanted the app to look like Claude wherever the two share an element.
Rejected: Claude's 768 pt column; the chat stays 1200 pt wide (ui-ux/0078) because the human asked for it wider.

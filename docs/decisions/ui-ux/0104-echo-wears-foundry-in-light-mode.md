# Echo wears Foundry, the human's design system, in light mode

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0080 and ui-ux/0085 for the light palette and the faces, and ui-ux/0086 for the sans; the layout, the chat column and every other rule stay.
Light mode takes Foundry's tokens through `Ledger`: a pale concrete desk `#e6e4df`, sheets `#efeeea`, a sunk grey `#d8d5ce` for picked rows and the human's bubble, ink `#2b2b29`, muted ink `#5e5b55`, rules `#c2beb5`.
`Ledger.accent`, a muted safety orange `#c8642e`, marks things (the picked row's edge, the needs-you target, the button's offset, link underlines) and is never text in light mode, being 3.1:1 on the sheet.
Running, done and failed keep their own hues (`#3f6a92`, `#5b6e42`, `#a33a2a`), apart from the accent.
The interface is Archivo; code, paths, labels, tabs and readouts are JetBrains Mono. Both are bundled under the SIL OFL in `app/bundle/Fonts` and registered at launch; a missing face falls back to the system's.
Dark mode and Custom keep the values they had; Foundry is light only.
Why: the human made Foundry and asked for Echo to wear it, after reviewing the "Echo in Foundry" canvas.
Rejected: a Foundry dark palette, which Foundry does not define.

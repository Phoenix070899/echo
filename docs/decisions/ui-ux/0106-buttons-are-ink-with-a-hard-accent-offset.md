# The primary button is solid ink casting a hard accent offset; the rest are an ink outline

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0013, only for the primary button and the New session mark, which now cast a hard offset block.
The primary button is `Ledger.primary` (ink) with a solid `Ledger.accent` block 3 pt down and right behind it; pressing moves the button onto the block. It is a filled shape, never a blurred `.shadow`.
Other buttons are a 1.5 pt ink outline on no fill.
Button labels are JetBrains Mono capitals and never truncate.
The primary is kept for the one action that moves work forward; an action like Insert into terminal is an outline.
Every other surface still has no shadow, and the message box lost its soft one.
Why: Foundry's button, which the human approved on the canvas, with Insert into terminal made quiet at their request.

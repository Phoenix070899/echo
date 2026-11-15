# An on and off setting is a square checkbox

Decided: 2026-11-15
Status: accepted

Every on and off setting is Foundry's `Checkbox`: an 18 pt square in a 2 pt ink frame, solid ink with a paper tick when on, the label beside it in the sans.
Hovered, an empty box takes the hover wash; disabled, the whole row is at half strength.
It replaces the system's toggle and `SquareToggleStyle`; Echo has no sliding switch.
Why: Foundry is square (ui-ux/0105) and has no switch, and a checkbox reads the same in a settings page and an inspector.
Rejected: a square sliding switch, a shape Foundry does not have; a two-choice segmented track, which takes more room for one bit.

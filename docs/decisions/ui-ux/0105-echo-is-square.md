# Every corner in Echo is square

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0085 for the radii.
`Ledger.radiusInner`, `radiusElement`, `radiusCard` and `radiusContainer` are all 0; views keep naming the kind of shape they draw so a later look can round them again in one place.
Rules are a full point (`Ledger.hairline`); the message box and other strong frames are 2 pt ink (`Ledger.ruleStrong`).
Shapes macOS draws itself (the window, menus, grouped Settings forms) are left as the system draws them.
Why: Foundry is square, and the human chose it for Echo.

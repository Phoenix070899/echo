# Settings wear Foundry: a numbered list, a page head per section, and square label and value rows

Decided: 2026-11-14
Status: accepted

Supersedes: ui-ux/0105's exception for the grouped Settings forms, which are no longer drawn by the system; ui-ux/0044's look of the section list (its rows, icons and run-colour bar) and its width "as wide as the ledger"; ui-ux/0035's "a tab's page has no heading of its own".
The section list is headed by "SETTINGS" in mono capitals with Done as an accent-underlined link, over a 2 pt ink rule.
Each section is a 44 pt row over a 1 pt rule: its number (01 to 09) in mono and its name; the picked one is ink and bold on the sheet's grey with a 3 pt accent bar at its leading edge.
The list is 260 pt wide, narrower when the ledger is, so the Teams section's three columns fit a 1280 pt window.
Every section but Teams is a page in the centred 680 pt column (ui-ux/0045): a head with a 2 pt ink rule, "NN / Name" in mono capitals and the name in Archivo's condensed display capitals, then groups of Foundry data rows: a 2 pt ink rule over rows of a bold 240 pt label and its value, each over a 1 pt rule.
Nothing in Settings is rounded or drawn by the system: pickers are square fields that open an AppKit menu, toggles are square checkboxes, steppers are square minus and plus buttons, sliders are a square handle on a 2 pt track, colours are square swatches that open the colour panel, and buttons are Foundry's at 34 pt (`SettingsStyle.swift`).
Help text sits under its control in muted ink; problems are in the failed red, never the accent.
Light mode is Foundry; dark and Custom draw the same shapes from their own `Ledger` values.
Why: the human approved the "Echo in Foundry" Settings artboards and asked for Settings to match them, with nothing rounded.
Rejected: keeping `.formStyle(.grouped)`, whose rounded groups, pop-up buttons and switches belong to no other surface in Foundry.

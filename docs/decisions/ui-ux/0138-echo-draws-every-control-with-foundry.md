# Echo draws every control with Foundry, from one Foundry module

Decided: 2026-11-15
Status: accepted

Supersedes: ui-ux/0125, only its line that context menus and form dropdowns stay native, and that `FoundryPopover` lives in `FoundryPopover.swift`; its look stands.
Every control in Echo's window is a Foundry component: buttons, checkboxes, pickers, menus, right-click menus, questions, fields, steppers, sliders, segments and find bars.
The components and the `Ledger` tokens live in their own SwiftPM target, `app/Sources/Foundry/`, which depends on HubCore and never on the app; Echo's views use them and draw no control of their own.
A component a second view needs moves into Foundry rather than being copied.
These stay the system's: the menu bar and the status item (ui-ux/0057), the file chooser (`NSOpenPanel`), the colour panel a `SquareColorWell` opens, tooltips, scrollbars, and the text editing inside fields and code.
`noViewUsesASystemControl` in `app/Tests/FoundryTests` fails when a view in HubApp or Foundry uses a system control, menu or alert, and names the Foundry component to use instead.
Why: the human wants no element that reads as a stock macOS control, and one folder of components to reuse.
Rejected: a subfolder of HubApp, which lets a component reach into `AppModel` and stop being reusable; a review rule without a test, which a later change would miss.

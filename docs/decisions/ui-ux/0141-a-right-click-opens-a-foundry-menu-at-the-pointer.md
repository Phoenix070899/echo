# A right click opens a Foundry menu at the pointer

Decided: 2026-11-15
Status: accepted

A right click or a Control-click on a row opens its actions as a `FoundryMenu` at the pointer (`foundryContextMenu`), in place of the system's context menu; ↑ ↓, Return and Esc work as in every Foundry menu.
It opens on a window that is not in front too, as the system's menu does, and VoiceOver's Show Menu opens it.
The Files tree, which AppKit draws (ui-ux/0063), reports the right click and SwiftUI draws the same menu (`foundryPointerMenu`).
A row with nothing to offer opens nothing; a "Move to" submenu becomes a labelled group of rows, since Foundry menus have no submenus.
Why: the system's context menu is rounded and blurred, unlike every other menu in Echo.

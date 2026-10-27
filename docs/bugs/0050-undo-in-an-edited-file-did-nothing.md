# Undo in an edited file did nothing

Found: 2026-10-27
Where: app/Sources/HubApp/CodeView.swift (`CodeTextView`)
Fixed in: the change that adds this file

While building file editing, typing worked but ⌘Z left the text as it was.
Cause: the text view keeps its own `UndoManager`, so a reread can drop the file's history, but the Edit menu's Undo asks the window's undo manager, which held nothing.
Fix: `CodeTextView` handles ⌘Z and ⇧⌘Z in `performKeyEquivalent`, ahead of the menu, and answers `undo:` and `redo:` itself for the menu.
Lesson: a view with its own `UndoManager` must also take the Undo key and the menu's `undo:`; overriding `undoManager` alone does not reach the Edit menu.

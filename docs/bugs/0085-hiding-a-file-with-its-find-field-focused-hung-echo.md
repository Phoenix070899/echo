# Hiding a file while its find field held the keyboard hung Echo

Found: 2026-11-15
Where: app/Sources/HubApp/CodeView.swift (CodeCoordinator.update), app/Sources/Foundry/FindBar.swift
Fixed in: the change that adds this file

With Foundry's find bar open over a file, Esc went back to the chat and Echo stopped answering, a core busy.
Cause: SwiftUI's own Esc key on the preview ran before the find field saw it, so the preview hid the code view while the field's editor held the keyboard; AppKit then looked for the next key view through SwiftUI and never finished.
Fix: the bar watches for Esc while its field holds the keyboard and closes itself first, and the code view closes the bar before it hides.
Lesson: before hiding an AppKit view inside SwiftUI, move the keyboard out of any text field in it; and catch Esc for an AppKit field with a local event monitor, since SwiftUI around it takes Esc first.

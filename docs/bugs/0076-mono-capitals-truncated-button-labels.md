# Mono capitals truncated button labels like Stop Worker

Found: 2026-11-14
Where: app/Sources/HubApp/Theme.swift (LedgerButtonStyle)
Fixed in: the change that adds this file

After the buttons moved to JetBrains Mono capitals, a Worker's header showed "STOP WO…": capitals in a mono face run wider than the sans they replaced, and the header gave the button the old width.
Cause: the label kept `lineLimit(1)` with no fixed size, so SwiftUI truncated it under pressure.
Fix: the button label takes `fixedSize(horizontal: true, vertical: false)`; neighbours give way instead.
Lesson: when a face or case change widens text, check every header row with a button in it at the narrowest window, and never let a button label truncate.

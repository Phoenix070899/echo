# The menu bar item is built in AppKit, not as a SwiftUI MenuBarExtra

Decided: 2026-11-02
Status: accepted

The menu bar item is an `NSStatusItem` that the app delegate makes (`MenuBarItem` in `MenuBarView.swift`), not a `MenuBarExtra` scene.
It shows Echo's mark and the Needs You count, and changes only when that count does.
A click shows `MenuBarView` in a panel below it; a click elsewhere, Esc, or another click on the item closes it.
Why: a `MenuBarExtra` is set up again on every change to the app's state, and macOS redraws it on every display and Space each time; that was over half the time of a switch between agents (bugs/0061).

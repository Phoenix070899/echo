# Turning marks kept the main thread a fifth busy while Workers worked

Found: 2026-11-02
Where: app/Sources/HubApp/Theme.swift (Spinner)
Fixed in: the change that adds this file

With 12 Workers at work and the human doing nothing, Echo's main thread was busy for about 1,800 ms of every 9 s, and a switch between agents took about 71 ms instead of 15.
Cause: each `Spinner` was a SwiftUI `TimelineView` at 30 frames a second, and every frame SwiftUI laid the whole window out again; a spinner shows for every Worker at work (ui-ux/0053).
Fix: the arc is a `CAShapeLayer` that a Core Animation rotation turns, so it turns without the main thread; the look, the colours, the periods, and Reduce Motion stay as ui-ux/0053 has them.
Measured with `app/scripts/measure-switch.sh`: idle busy time fell from about 1,800 ms to 56 ms per 9 s, and a switch to about 17 to 29 ms.
Lesson: anything that moves for as long as work runs is a Core Animation animation, never a SwiftUI one driven per frame; check `idle:` in `measure-switch.sh` after adding one.

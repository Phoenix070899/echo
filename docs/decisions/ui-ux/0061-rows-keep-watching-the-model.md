# Ledger and file rows keep watching the model; a switch's cost is layout, not their bodies

Decided: 2026-11-02
Status: accepted

Ledger rows and Files column rows keep reading `AppModel` as an environment object.
Tried and dropped: rows that took what they show as plain values, acted through `AppModel.shared`, and compared equal so SwiftUI skipped unchanged ones, as Orca keeps its app from redrawing on a switch.
Measured with `app/scripts/measure-switch.sh` (3 agents, 12 Workers), switches took 17 to 25 ms with Files hidden and 34 to 40 ms with Files shown, with or without it; runs varied more than any change it made.
`sample` puts the rest of a switch in SwiftUI's layout of the window and of the new checkout's file list, and in Core Animation, not in row bodies or in Echo's code (about 5 ms).
Why: rows that list every value they show in their equality draw stale when one is forgotten; with no gain measured, that risk is not worth taking, nor is splitting `AppModel` for the same reason.
Measure with `measure-switch.sh` again before reopening this, with many more Workers than 12 if the human runs that many.

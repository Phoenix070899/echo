# A Worker that needs the human read "Running" in its header

Found: 2026-10-31
Where: app/Sources/HubApp/Theme.swift (WorkerRow.phaseLabel, markColor)
Fixed in: this change

A Worker stopped at a permission prompt showed a blue "Running" in its header, its tooltip, Quick Open, and its notification, while the ledger listed it under Needs you.
Cause: `phaseLabel` and `markColor` read only whether the Worker was active, not its `needs you` state.
Fix: an active Worker that needs the human reads "Needs you", with an amber (`Ledger.changed`) mark.
Lesson: a Worker's label comes from its full state, never from its phase alone.

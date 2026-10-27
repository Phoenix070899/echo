# Bands drew rounded corners inside the sheet, leaving notches between them

Found: 2026-10-25
Where: app/Sources/HubApp (every `.background(Ledger.band)`: the file tab strip, PanelHeader, the Files column bars)
Fixed in: the change that adds this file

The file tab strip over the terminal and the agent header below it each showed rounded corners, so a notch of the desk showed at the sheet's edge where they met.
Cause: inside a view clipped by `ledgerSheet()`'s rounded shape, a plain `.background(colour)` took that rounded shape too on this macOS, so every band was rounded on all four corners.
Fix: band backgrounds name their shape, `.background(Ledger.band, in: Rectangle())`; only the sheet itself is rounded.
Lesson: a background that should be square inside a rounded container says `in: Rectangle()`; check stacked bands at the sheet's edge, zoomed in, after any layout change.

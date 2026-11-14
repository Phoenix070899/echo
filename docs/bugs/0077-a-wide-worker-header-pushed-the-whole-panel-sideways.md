# A wide Worker header pushed the whole main panel sideways

Found: 2026-11-14
Where: app/Sources/HubApp/ContentView.swift (WorkerHeader)
Fixed in: the change that adds this file

With Foundry's 40 pt title, the views and Stop Worker on one row, the header wanted more than the 560 pt panel between the ledger and Files; the tab strip and every view under it moved 5 pt right and the title cut to "TH…".
Cause: the row's fixed-size controls set a minimum width larger than the panel, and `clippedToOffer` centres content that does not fit.
Fix: the title has a row of its own, and `ViewThatFits` drops the views under the Worker's name when the row does not fit.
Lesson: check every header at the narrowest panel the window allows; a row of fixed-size controls must have a narrower fallback.

# Moving one node on the Teams canvas counted every Member as an unsaved change

Found: 2026-11-15
Where: app/Sources/HubCore/TeamSummary.swift (changeCount, memberChanged)

Dragging one node of a Team that Echo had laid out showed "7 unsaved changes" and the Changed mark on every node.
Cause: the first edit on the canvas writes `x` and `y` into every Member so the others stay put (TeamGraph.placed), and the count compared each Member field by field with the saved one, which had no place.
Fix: a saved Member without a place counts as at the place Echo laid it out at, so only the moved Member is changed.
Lesson: when an edit writes fields the human did not touch to keep the view still, count changes against what the human saw, not against the file.

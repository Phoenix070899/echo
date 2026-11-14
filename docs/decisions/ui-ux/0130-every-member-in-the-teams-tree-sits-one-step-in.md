# Every Member in the Teams tree sits one step in, whatever its level

Decided: 2026-11-15
Status: accepted

Supersedes: ui-ux/0121, only that nodes step 30 pt per level; ui-ux/0124, only "Indentation still shows nesting" for the Teams tree and that a Member's square sits under its parent's node. Everything else in them stands.
In the Teams tree the Orchestrator's node sits at the edge and every Member's node sits one step (30 pt, 22 pt when narrow) in from it, whatever its level; its square sits 12 pt in, under the Orchestrator's node.
A Member's place in the tree shows in the inspector's "Under <parent>" line, and a drag's drop line still steps in by the level the drop would give.
The Orchestrator's row has no square, so hovered it turns the sunk grey and gains no mark (ui-ux/0127).
When a row is too narrow for both, a Member's id gives way whole before its name is cut.
Why: the human asked, on the Settings Teams artboard, for a nested Member to line up with the others rather than sit indented, and asked the app to match that artboard one to one.

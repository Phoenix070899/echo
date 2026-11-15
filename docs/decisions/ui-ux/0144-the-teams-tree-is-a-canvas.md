# The Teams tree is a canvas of Member nodes and Hand-off lines

Decided: 2026-11-15
Status: accepted

Supersedes: ui-ux/0121's tree on a spine in columns; ui-ux/0130 whole; ui-ux/0102's drops onto and between rows and its ⌥← and ⌥→ indent and outdent; ui-ux/0122's Indent, Outdent and Move To in the More menu. The list, the inspector, the save bar, the Add Member menu and the More menu stand.
The middle column of Settings > Teams is a canvas on the desk with an 8 pt grid; the Orchestrator's node sits at its top centre and cannot be moved, removed or duplicated.
A Member is a square-cornered node on paper: the Action's two capitals in a square, the id in bold, the Profile and the model with its family's mark, and the effort; the picked node has a 3 pt accent edge.
A Hand-off is a line with right angles and an arrowhead from the bottom of one node to the top of the next: a hint is a hairline in `rule`, an automatic Hand-off a 2 pt line in `accent`.
Dragging a node moves it and snaps it to the grid; dragging from a node's bottom port to another node draws a Hand-off; a Hand-off the rules of features/0092 refuse shows why in one plain line under the canvas and is not drawn.
Scrolling pans, a pinch or ⌘+ and ⌘− zoom from 50% to 200%, and Fit frames the whole Team.
Add Member places the new node under the picked node with a hint Hand-off from it, or under the Orchestrator.
The inspector gains an After list: one row per incoming Hand-off with its source and an Automatic switch, and an Add picker, so a drag is never the only way to draw one (ui-ux/0008).
With the canvas focused and no field being edited, the arrow keys pick the nearest node that way, ⌥ and an arrow move the picked node one grid step, Return opens its name, Delete removes it, `a` adds and `d` duplicates, as ui-ux/0102 had them.
A Member that cannot be reached from the Orchestrator has a `fail` frame and its reason in the inspector.
The canvas shows the Team only; a running Orchestrator's Workers stay in the ledger.
Why: the human wants to lay out Members and draw the lines between them by hand, and a tree cannot show a Member that follows two others.
Rejected: palette chips dropped onto the canvas, which ui-ux/0122 already removed for the Add Member menu; curved lines, which read less well at small zoom; live Worker state on the nodes, left for a later change.

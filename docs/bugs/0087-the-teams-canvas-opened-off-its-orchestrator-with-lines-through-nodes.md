# The Teams canvas opened scrolled away from its Orchestrator, and a line ran through a node it did not touch

Found: 2026-11-15
Where: app/Sources/HubApp/TeamCanvasView.swift, app/Sources/HubCore/TeamGraph.swift (layout and line routes)

In the end-to-end run, a shipped Team with six Members opened at its left edge with the Orchestrator out of view, and the Members' second lines were cut ("hinata · …nnet-5-5").
After wrapping wide rows, the automatic line from `build` to `test` ran straight through `build-ui`, so it read as build, then build-ui, then test.
Cause: the canvas opened at 100% at the scroll view's top-left; Echo laid every Member of a level in one row; a line dropped straight down at its target's centre whatever stood between; and a node was too narrow for a Profile and a full model name.
Fix: a Team opens at the zoom that fits its width, at most 100%, scrolled to the Orchestrator; Echo lays out at most three nodes side by side and wraps the rest half a step over; a line bends just under its source and takes a clear lane round any node in between; nodes are 192 pt wide and show models as "sonnet 5.5".
Lesson: look at the canvas with a Team wider than the window and with Hand-offs that skip a row before calling a layout done; unit tests of positions do not show a line crossing a node.

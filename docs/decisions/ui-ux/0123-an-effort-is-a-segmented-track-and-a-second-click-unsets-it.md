# An effort in the Teams inspector is a segmented track, and clicking the picked effort again unsets it

Decided: 2026-11-14
Status: accepted

The Orchestrator's, the Workers', a Profile's and a Member's effort are a Foundry segmented track of low, medium, high, xhigh and max across the inspector's width.
Clicking the picked effort again leaves it unset, so it follows the level below; for a Member, the effort it inherits is framed dashed while nothing is picked, and the line under it says where it comes from with Reset.
Why: the artboard shows the effort as a segmented control; the unset choice the old menu had ("Not set") must stay reachable without a sixth segment that would not fit 260 pt.

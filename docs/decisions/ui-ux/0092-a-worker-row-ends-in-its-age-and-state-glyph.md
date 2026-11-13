# A Worker's sidebar row ends in its age and a state glyph

Decided: 2026-11-13
Status: accepted

Supersedes: ui-ux/0084, only where it put a Worker's mark before its title.
A Worker's row in the sidebar reads title, age, glyph. The title takes the width and fades at its end; the age is how long since the Worker last reported ("now" under a minute, then 5m, 2h), updated each minute; the glyph is at the right edge.
The glyph: a turning ring while it works (slower while it only waits on background work), an amber target when it needs the human, a filled green tick when it is done, a plain grey tick when it ended at its input box, a red cross when it went wrong.
A title is set in the medium weight and full ink while the Worker needs the human; every other title stays regular and grey until its row is picked.
Nothing else changes: the dot under the agent, the row height, the fill, the tooltip, and the agent, repo and usage rows are as they were. The Worker header and the fan-out list keep the mark before the title.
Why: the human liked the way Harp's sidebar shows, at the right of each row, how long ago and in what state each session is, and asked for that on Workers only.

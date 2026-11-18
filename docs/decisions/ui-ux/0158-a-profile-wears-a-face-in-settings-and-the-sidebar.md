# A Profile wears a face, picked in Settings > Profiles and shown before each Worker in the sidebar

Decided: 2026-11-17
Status: accepted

Echo ships 100 faces, cut from the human's character sheet, as 160 px pictures in `app/bundle/Faces/` (`r01c01.png` to `r10c10.png`, row and column on the sheet).
Faces are square in a hairline rule frame, as Foundry draws everything; an empty frame stands for no face, so titles line up.
The Profile's head in Settings > Profiles starts with its face at 56 pt; clicking it opens Foundry's popover with every face in a 10-column grid, the picked one in an accent frame, and a "No face" link in the foot.
Picking a face is a change like any other field: the save bar counts it, and Save writes it.
Echo's own Profiles show their face but cannot change it until Make my copy, as with every field.
Each row of the Profiles list shows the face at 32 pt; the picked row shows the face being edited.
A Worker's row in the sidebar shows its Profile's face at 20 pt between its square and its title.
Why: the human asked to see at a glance which Profile each Worker runs as.

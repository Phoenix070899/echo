# Unsaved Team edits ask before they are lost

Decided: 2026-11-14
Status: accepted

When a Team has edits that are not saved and the human picks another Team or Defaults, goes to another section of Settings, or closes Settings (Done or Esc), Echo asks first, in a centred card (ui-ux/0006).
The card offers Save, Discard and Cancel; Return is Save, and Esc is Cancel.
Save writes the Team and then goes where the human was going; if the daemon refuses the Team, the card closes, the refusal shows where it does on the Team, and the human stays.
Discard drops the edits and goes on; Cancel stays on the Team with the edits kept.
A Team without edits is left without asking.
Why: the tree and the inspector are edited in a draft (ui-ux/0101), and a stray click on another Team would otherwise lose a tree the human just arranged.
Rejected: saving on every change, which writes half-built trees that the daemon refuses; keeping one draft per Team while another is shown, which leaves unsaved work the human cannot see.

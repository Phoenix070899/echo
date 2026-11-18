# Profiles has Rename, and their buttons carry no ellipsis

Decided: 2026-11-16
Status: accepted

Builds on ui-ux/0145; follows features/0103.
Under the Profiles list, your and the repo's Profiles show Duplicate, Rename and Delete as links.
Rename asks for the new name in a card prefilled with the current one, with Rename as its answer; the daemon's refusal shows in the bar, and the renamed Profile stays picked.
Button text in Settings > Profiles and Settings > Teams has no trailing ellipsis: "Delete", not "Delete…", even when a card follows.
Why: the human asked for plain labels.
Rejected: macOS's ellipsis for a button that asks more before acting.

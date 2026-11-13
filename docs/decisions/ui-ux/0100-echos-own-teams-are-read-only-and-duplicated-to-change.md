# Echo's own Teams are read-only and are duplicated to change them

Decided: 2026-11-13
Status: accepted

On the Teams page a shipped Team shows its fields dimmed and cannot be saved or deleted; a Duplicate button stands in the place of Save. Duplicate opens an unsaved copy named `name-copy`, then `name-copy-2` and so on, the first name no listed Team has, kept to a Team's 40 characters. The copy is saved at the human's level; a copy of a repo's Team stays in its repo. Nothing is written until the human presses Save.
Why: a shipped Team lives in Echo's own folder and changes with Echo, so an edit saved over it would be lost or would replace it silently for every repo; a copy under a new name is the human's to keep (features/0081).
Rejected: saving an edit of a shipped Team as a same-named copy in the human's folder, which makes the shipped Team vanish from the list behind an edited one; hiding the shipped Teams from the page, which leaves nothing to start a new Team from.

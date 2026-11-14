# A Team's tree is edited by dragging and by keys

Decided: 2026-11-14
Status: accepted

A Member row can be dragged. Dropping it onto a Member makes it that Member's child, dropping it between two rows puts it there among their siblings, and dropping it at the tree's left edge makes it a level 1 Member.
A chip from the palette is dropped the same way and adds a Member.
A drop that the rules of features/0084 refuse (a cycle, a tree deeper than 3, a `verify` Member not under an `execute` Member, a Member into its own subtree) shows why in one plain line under the tree and changes nothing.
A line or a filled row (`Ledger` tokens, no shadow) shows where a drop would land.
With the tree focused and no text field being edited, ↑ and ↓ select a row, ⌥↑ and ⌥↓ move the Member among its siblings, ⌥→ indents it under the sibling above, ⌥← outdents it, Return opens its name, Delete removes it (asking first when it has children), `a` adds a Member and `d` duplicates the selected one.
⌘N and ⌘D are not used for this: they are Echo's New Orchestrator and split (ui-ux/0008), and the list there stays as it is.
The same moves are offered as buttons and menu items, so a drag is never the only way (ui-ux/0008).
Why: a drag is the quick way to rearrange a tree and cannot be the only one; the keys follow the Option-arrow moves of outline editors, and the plain keys are safe because they act only while no field is being edited.
Rejected: ⌘-arrow keys and ⌘D, which clash with the text fields' and the split's own shortcuts; dragging only, which leaves the keyboard out; a drop that fixes an invalid tree on its own, which would move Members the human did not touch.

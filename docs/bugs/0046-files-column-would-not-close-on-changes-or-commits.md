# The Files column's close button and ⇧⌘E did nothing on the Changes and Commits tabs

Found: 2026-10-24
Where: app/Sources/HubApp/FilesColumn.swift (FilesListFocus, the tree's focus), app/Sources/HubApp/AppModel.swift (toggleFiles)
Fixed in: the change that adds this file

With Changes or Commits showing, the column's × and ⇧⌘E never hid the column; on Files they did.
Cause: the tree and both lists shared one "has the keyboard" flag; switching tabs, the old list's loss of focus could land after the new list's gain and clear the flag, so ⇧⌘E only asked for focus again, which changed nothing; and × called the same toggle.
Fix: the model keeps which tab's list has the keyboard, and only that list clears it; × hides the column outright.
Lesson: when several views report focus into one shared value, record which one owns it and let only the owner clear it; a button that says close calls close, not a toggle that depends on focus.
Came back: 2026-10-24, ⇧⌘E still only opened the column when the keyboard never reached it after opening (as with the window not key); now a press right after one that asked for the keyboard hides the column.

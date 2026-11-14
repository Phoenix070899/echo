# A previewed file's path shrank to an ellipsis in a narrow panel

Found: 2026-11-14
Where: app/Sources/HubApp/FilePreview.swift (header)
Fixed in: the change that adds this file

With the larger Foundry segmented choice, icon squares and Insert into terminal, the preview header showed only "…" where CONTEXT.md should be.
Cause: the path had layout priority -1, so it gave all its room to the fixed-size controls.
Fix: `ViewThatFits` puts the path on a row of its own above the controls when both do not fit on one row.
Lesson: text that names what is shown must never give way to zero; give it a fallback row instead of a lower priority.

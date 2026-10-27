# A previewed text file is edited in place behind an Edit toggle

Decided: 2026-10-27
Status: accepted

Supersedes: ui-ux/0031's "non-editable" text view, which is now editable while editing; the rest of 0031 stands.
Edit in the preview header, or ⌘E, turns the file's code view into editable text; Done, Esc, or ⌘E again stops.
Only a file shown whole as UTF-8 text takes Edit: not one cut at 1 MB, not images, PDFs, or binary files.
Rendered Markdown and HTML switch to their source to edit, and the Rendered and Source switch hides until editing stops.
While editing, ↑ ↓ and Return type, notes and the gutter's + are off, and the bar under the file says how to save and stop.
⌘S or Save writes the file in place, so its permissions stay; it does not save on its own.
A tab with unsaved edits shows a dot; stopping, closing the tab, or quitting first asks Save, Cancel, or Don't Save.
When the file changes on disk while edits are unsaved, the edits stay on screen and the bar offers "Keep my changes" or "Show the new file".
Each file keeps its own undo history, dropped when the file is read again.
Why: the human wanted to fix a file without leaving Echo; an always-editable view would take the note keys and could let an agent's change and the human's typing overwrite each other unseen.
Rejected: autosave, which would write half-typed code under a running agent; opening the system editor, which Open already does.

# One switch for how a previewed file shows, quiet icons, and one primary button

Decided: 2026-10-28
Status: accepted

Supersedes: ui-ux/0041's Edit toggle and Done button, and its hiding of the Rendered and Source switch while editing; ui-ux/0017's Reveal in Finder and Open as words.
The preview header holds one switch: Rendered, Source, and Edit for Markdown and HTML; View and Edit for other text; Edit only when the file can be edited.
Picking Rendered or Source while editing stops editing first, with the same Save, Cancel, or Don't Save prompt; Cancel keeps editing.
The switch is Echo's own: the picked mode raised on the pill fill over the field fill, with no accent colour, so it does not compete with the primary button.
Reveal in Finder, Open in browser, and Open in editor are icons in ink2, with a fill on hover and their names and keys as help.
The one primary button is Insert into terminal, or Save while editing, which is off until there are changes.
Why: the header had five actions in three styles, with accent text links and an accent switch competing with the primary button.

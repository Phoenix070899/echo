# New Profile and Duplicate write the Profile's file at once

Decided: 2026-11-15
Status: accepted

Builds on ui-ux/0145.
In Settings > Profiles, New Profile and Duplicate ask for a name, then for Yours or This repo (Return picks Yours), and write the file at once: New writes the daemon's blank Profile with its starter role (`profile.new`), Duplicate a copy of the picked Profile under the new name (`profile.new` with `from`).
Duplicate offers `<name>-copy`, then `-copy-2` and on, within a Profile's 32 characters.
The new Profile is then picked, and its edits go through Revert and Save like any other.
Why: a Profile is one Markdown file the daemon checks as a whole, and unlike a Team's draft graph there is nothing to hold before it is valid; writing at once keeps one path for every edit.
Rejected: an unsaved draft Profile as ui-ux/0100 has for Teams, which needs a second save path for a file that does not exist yet.

# A Profile names its face in its own file, and each Worker's row carries it

Decided: 2026-11-17
Status: accepted

A Profile's frontmatter has a `face` field: the name of a picture Echo ships (`r01c01`), or empty for none.
`profile.set` writes it like any other field; a new Profile has none.
Echo's own Profiles each name one: naruto `r01c01`, sasuke `r01c02`, ino `r01c06`, lee `r01c09`, jiraiya `r04c09`, hinata `r06c05`.
`profiles.list` sends each Profile's face, and the snapshot sends each Worker's Profile's face, read each time, so a changed face shows on Workers already at work.
The daemon does not check the name; Echo draws a name it does not ship as no face.
Why: the face travels with the Profile, to the human's copy and a repo's, and a rename keeps it; keeping faces in Echo's own defaults was rejected, as a repo's Profiles would lose theirs and Echo's own could not have one.

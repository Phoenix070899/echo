# Echo's own Actions are six, plus custom

Decided: 2026-11-14
Status: accepted

An Action is what a Member is for. Echo ships six, as read-only files in `actions/` of the Echo repo: `scan`, `research`, `execute`, `verify`, `run` and `scribe`.
Their default Profiles are `scan` hinata (reads the code), `research` jiraiya (reads the web), `execute` naruto (changes code), `verify` sasuke (reviews a writer's commits), `run` lee (commands, tests and builds), and `scribe` ino (Preferences and Lessons).
Each Action names its default Profile, the sentence the Orchestrator reads to know what to send it, whether its Member writes, and its worktree hint; `verify` also names the Action its Member must sit under, `execute`.
`custom` is not an Action file: it is the `action` of a Member the human built on a Profile of their own, and it has no routing sentence.
The human cannot define Actions in this version; the six and `custom` are all a Member's `action` can be.
A Member may start from a Profile other than its Action's default, and the Action does not limit what the Member's fields may hold.
Why: the Orchestrator needs a short, fixed set of words to route work by, and the human needs the same few words in the palette; a set anyone can extend would make the Orchestrator's prompt and the palette differ from Team to Team.
Rejected: user-defined Actions, which need a place to keep them, three levels and a way to read them, for a need `custom` already covers; one Action per Profile, which would tie the palette to the Profiles and leave a Profile of the human's own with no word.

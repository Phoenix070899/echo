# A bare skill name showed Not installed while its plugin skill was installed

Found: 2026-11-16
Where: app/Sources/HubCore/ProfileForm.swift (ProfileSkills.groups), app/Sources/HubApp/ProfilesSection.swift (SkillRow)

The `naruto` Profile names `skills: tdd`, and its Skills checklist listed `tdd` under Not installed, while `mattpocock-skills:tdd` was installed and listed further down.
Cause: Claude Code names a plugin skill `<plugin>:<skill>`, and the checklist matches names exactly, so the bare name matched nothing and the human got no hint of the right one.
Fix: a bare name that exactly one installed plugin skill ends with offers "Use <plugin>:<skill>", which swaps it in place (ui-ux/0148).
Lesson: when a name must match exactly, show the near match the human most likely meant, and let them take it.

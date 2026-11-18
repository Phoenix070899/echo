# A bare skill name the CLI lacks is offered the one plugin skill with that name

Decided: 2026-11-16
Status: accepted

Builds on ui-ux/0147.
Under Not installed, a skill name without a `<plugin>:` prefix that exactly one installed plugin skill ends with (`tdd` and `mattpocock-skills:tdd`) shows a link under it: "Use mattpocock-skills:tdd".
Pressing it puts the plugin skill's name in the bare name's place, so the order holds, and drops a second copy if it was already checked.
When no plugin or several plugins have the name, nothing is offered, and the name stays as it is until the human unchecks it.
Echo never rewrites the name on its own.
Why: Profiles written by hand or before a plugin was installed name the bare skill, and the exact match failed with no hint of the right name.
Rejected: matching bare names silently, which would change the file without the human seeing it; guessing between several plugins.

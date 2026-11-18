# A Profile's skills are picked from the ones its CLI has, as the daemon lists them

Decided: 2026-11-15
Status: accepted

The daemon's `skills.list` method (params: `repo`) lists, per CLI, each skill as `{name, description, source}`, `source` being `yours`, `repo`, `built-in` or `plugin` (with `plugin` its name), and the name being what the CLI invokes.
Claude Code's are read from the human's config folder as `accounts::source` names it (so `CLAUDE_CONFIG_DIR` moves it): each `skills/<dir>/SKILL.md`, then the repo's `.claude/skills/<dir>/SKILL.md`, then each enabled plugin's as `<plugin>:<skill>`.
A plugin counts when `plugins/installed_plugins.json` lists it for you (or for this repo) and `enabledPlugins` turns it on, in your `settings.json`, the repo's `.claude/settings.json` or `.claude/settings.local.json`, the last that names it winning.
A plugin's skills are each `skills/<dir>/SKILL.md` and each path its manifest's `skills` names (`.claude-plugin/plugin.json`, else its entry in the `marketplace.json` beside it), so a plugin that nests skills exposes only the ones it names, not its `in-progress/` or `deprecated/` folders.
A skill's name is its frontmatter `name`, else its folder; its description is folded onto one line.
A skill marked `disable-model-invocation: true` is left out: only the human can run it, so a Worker told to use it cannot.
Codex's are what `codex debug prompt-input`, run in the repo on Echo's own login while it is signed in, lists to its model under "Available skills": `~/.agents/skills`, the repo's `.agents/skills`, its own `skills/.system` (`built-in`) and its plugins' (`<plugin>:<skill>`).
Kiro has no skills.
The daemon keeps each repo's lists one minute, so a skill just installed shows soon; a list that failed is asked for again on the next call.
At a Worker's start the names still only become the line "Use these skills when they fit the Task: ...".
Why: a typed skill name was easy to get wrong, and a plugin's skill only works under its `<plugin>:` name; the list a Worker's CLI would actually load is the one worth offering.
Rejected: reading Codex's folders ourselves, since `~/.codex/skills` holds only its `.system` ones on this Mac and Codex also reads `~/.agents/skills` and plugin caches, which its own prompt input names exactly; listing every `SKILL.md` under a plugin, which offers skills it does not expose; reading skills from Claude Code transcripts, which exist only after a session ran in the repo.

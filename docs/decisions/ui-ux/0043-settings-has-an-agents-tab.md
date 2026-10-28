# Settings has an Agents tab: the default CLI and model, each Profile, and the Orchestrator's rules

Decided: 2026-10-28
Status: accepted

Supersedes: ui-ux/0035's list of tabs, which gains Agents before Remote; the rest of 0035 stands.
The Agents tab has three sections: the CLI and model every agent defaults to; one Profile picked from a menu, with where it comes from, what it runs with here, and its own CLI, model, and effort; and the Orchestrators' rules.
Changing a field of Echo's own Profile saves it as yours first, so Echo's own files are never written; Reset deletes your copy, and a Profile only you have is deleted instead, after asking.
Edit Role opens the Profile's file in the human's editor; New Profile asks for a name and opens the blank one.
The Orchestrator's rules are one section in this tab, not a tab of their own, because eight tabs pushed Remote out of the 520 pt window behind a "»".
Why: the human wants people to tune their agents without editing files by hand.

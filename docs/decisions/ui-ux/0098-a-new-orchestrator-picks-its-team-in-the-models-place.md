# A new Orchestrator picks its Team in the model's place, and the Team shows where the model did

Decided: 2026-11-13
Status: accepted

The New session sheet in Orchestrator mode shows a "Team" menu at the right of Name, where Normal mode keeps its model menu. An Orchestrator's model comes from its Team (features/0081), so a model picked beside it would override the Team and is not offered.
The menu lists the Teams by name. Under the Name row a single line of the same grey as the other captions says what the picked Team does ("Orchestrator: claude-sonnet-5.5, medium. Workers: by their Profiles."). A Team whose file has a problem stays in the list, dimmed and not pickable, and the line names it with its problem.
The sheet starts on the last Team used (kept per Mac, not per repo), else `claude-opus`, else the first usable Team. A remembered Team that no longer exists or has a problem is passed over. The Team is remembered when the human starts the Orchestrator.
The Team menu follows the repo picked in the sheet, so a repo's own Teams appear with it. The sheet gains no row, so it stays as short as before.
An Orchestrator's row names its Team in the tooltip ("Orchestrator, Team claude-lean, ...") and its panel header ends "Orchestrator in repo, Team claude-lean". An Orchestrator on a Team shows no "default model" there, since its model is the Team's. Agents with no Team show what they showed.
Why: one choice at the start sets the planner, the Workers and the rules, and the place that named the model is where the human already looks; the header and tooltip answer "which setup is this one running" without opening Settings.
Rejected: a second row for the Team, which adds height to a sheet already tall for small windows; keeping the model menu beside the Team, where a model would silently beat the Team; a Team badge on the row itself, which adds a mark to rows that end in an age and a state glyph (ui-ux/0092).

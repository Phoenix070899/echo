# Big picture: one Teams page where a Team is a tree of Members you drag, assign Actions to, and edit

Status: approved by the human on 2026-11-14 ("execute team builder plan first"); the choices listed at the end stand as stated. Detailed plan: `detailed-plan.md`, executed by kakashi on branch `plan/team-builder`. Code analysis of 2026-11-14 settled these open points: a Member's `tools`, `skills` and `context` replace the Profile's when set; a start name is a Member id, else the first Member using that Profile, else the bare Profile; a Worker whose Member was removed falls back to its Profile; with no `verify` child the verifier is sasuke; the Team's `rules.review` also decides the daemon's verification (it only shaped the prompt before); the section takes the whole window width; new keys are Option+arrows, `a`, `d`, Delete (Command+N and Command+D are menu items); unsaved edits ask before they are lost; `team.save` replaces the whole file, so the app's form must carry `members` before any save path uses them.
Requested: "consolidate agents and teams setting in one; an easy flow to create a new profile and the workers of that profile; predefined subagents like naruto, sasuke; a tree whose nodes can be dragged and dropped; predefined actions (research, scan source code, executioner, verifier, ...) assigned to a node's worker; each node editable: instruction, model, tools, context."
Read first: `docs/decisions/features/0081`, `0082`, `0075`, `0055`, `0035`; `ui-ux/0043`, `0035`, `0008`; `docs/plans/2026-11-13-teams/big-picture.md`; `CONTEXT.md`.

## Words (this plan changes the glossary)
The human's "profile" (the whole setup you pick when starting a session) is what the repo already calls a **Team**. The repo's **Profile** is one Worker's role (naruto). This plan keeps both words and adds two:

- **Member**: one node of a Team's tree. It is a Worker slot: a name, an Action, the Profile it starts from, and the changes this Team makes to that Profile.
- **Action**: what a Member is for. Echo ships `scan` (read the code), `research` (read the web), `execute` (change code), `verify` (review a writer's commits), `run` (commands, tests, builds), `scribe` (Preferences and Lessons). Each Action names a default Profile (hinata, jiraiya, naruto, sasuke, lee, ino), its routing sentence for the Orchestrator, and defaults (writes or not, worktree policy).

Both go into `CONTEXT.md`. "Subagent" stays in the Avoid list.

## What exists today
- Settings has two sections: **Agents** (default CLI/model, `forceCli`, one Profile picked from a menu with CLI/model/effort fields and "Edit Role…" opening a file, the Orchestrator rules) and **Teams** (a form: Orchestrator setup, Workers' CLI/model/effort for all and per Profile, rules, instructions). They overlap: both set models and effort, and rules exist in both (a Team's rules over the Agents page's).
- A Team file has no tree and no Members. It can only override cli/model/effort per Profile name (`workers.profiles.<name>`). Tools, skills, context and role text exist only in the Profile files, shared by every Team.
- A Worker starts as a Profile name (`echoctl worker start naruto`); two differently configured naruto in one Team are impossible.
- Verification is hard-wired: `--verify` starts a `sasuke` Worker (features/0055).
- Tool names in a Profile are Claude's; `cli.rs` already maps them for Kiro (`kiro_tools`), so a per-Member tool list needs no new vocabulary.

## Design

### 1. One section, one object: the Team
Settings has one section (recommended title **Teams**; it replaces both Agents and Teams, superseding ui-ux/0043 and the Teams page). Layout, left to right:

- **Teams list**: shipped, yours, repo's; New, Duplicate, Delete. A **Defaults** row at the top holds the default CLI/model and `forceCli` (the only things that are not per Team).
- **Tree canvas**: the picked Team. The root is the Orchestrator. Under it, Members.
- **Inspector**: the selected node's fields.
- **Palette** (a strip above the canvas): the Actions and the shipped Workers (naruto, sasuke, hinata, jiraiya, lee, ino) as chips to drag in, plus "Custom".

The root node's inspector holds everything an Orchestrator has: CLI, model, effort, renew-at size, the four rules (max Workers, plan approval, review, merge without asking), extra instructions. Fields left empty show what they fall back to ("from your defaults: claude-opus"), as the Teams page does now.

### 2. A Member's inspector (your list)
| Field | Meaning | Stored as |
| --- | --- | --- |
| Name | what the Orchestrator starts it as; unique in the Team | `name` |
| Action | what it is for | `action` |
| Profile | the role it starts from | `profile` |
| Instruction | text for this Member; added after the Profile's role by default, with a "replace the role" switch | `instructions`, `replaceRole` |
| CLI, model, effort | like today, validated against the CLI | `cli`, `model`, `effort` |
| Tools | checklist of Claude-named tools, mapped per CLI as today | `tools` |
| Skills | list | `skills` |
| Context | files to read first, plus switches for Preferences and Lessons | `context`, `lessons` |
| Writes / worktree | from the Action, overridable | `writes`, `worktree` |

Editing a Member changes this Team only. A separate "Edit shared role…" button opens the Profile file (the existing copy-on-edit behaviour of Echo's own Profiles stays), with a note that it affects every Team.

### 3. What the tree means (the main decision, recommended option)
Today Workers cannot start Workers: they only ask their Orchestrator (Worker Contract, CONTEXT.md "hears only from its own Workers"). A tree of nested delegation would break that. So the tree is a **plan of hand-offs, run by the Orchestrator and the daemon**:

- Root: the Orchestrator.
- Level 1: Members the Orchestrator may start.
- A child of a Member: what follows it. `execute` > `verify` means the daemon verifies that writer's commits with that verifier Member instead of the hard-wired sasuke (features/0055 reads the Team). Other children (`scan` > `execute`, `research` > `scan`) become routing text in the Orchestrator's prompt: "after `scan` reports, give its report to `execute` with `--from-report`".
- Sibling order is the order the Orchestrator is told to prefer; it enforces nothing.
- Validation: a `verify` Member must sit under an `execute` Member; names unique; depth at most 3; at least the root.

Rejected: real nested orchestration (a Member that starts its own Members). It needs a new ADR, a new message path and a new concurrency story, and is not needed to get what the human described. It can be built later on the same file format.

### 4. File format (frozen before milestones)
Team JSON gains `members`, a flat list in tree order, each with `parent` (the id of another Member, or absent for level 1) instead of nested JSON, so a drag is a small diff in git and a merge conflict stays readable:

```json
{
  "orchestrator": { "cli": "kiro", "model": "claude-sonnet-5.5", "effort": "medium" },
  "members": [
    { "id": "scan",   "action": "scan",    "profile": "hinata", "model": "claude-haiku-5.5" },
    { "id": "build",  "action": "execute", "profile": "naruto", "model": "claude-sonnet-5.5", "effort": "high",
      "instructions": "Prefer small commits.", "tools": ["Read", "Edit", "Bash"] },
    { "id": "check",  "action": "verify",  "profile": "sasuke", "parent": "build" }
  ],
  "rules": { "maxWorkers": 3 }
}
```

- Backward compatible: a Team without `members` behaves exactly as today, and `workers.profiles.<name>` still works. A Member whose `id` equals a Profile name is the same as the old per-Profile entry plus the new fields.
- Resolution for a Member's Worker: explicit pick > Member > Team `workers` > Profile > repo settings > state settings (the same shape as decision 0081, with Member in the place of `workers.profiles.<name>`; `forceCli` rules of 0075 unchanged).
- `echoctl worker start <id|profile>`: a Member id is tried first, then a Profile name. The Worker row records its Member id (nullable column, guarded migration).
- Shipped Actions live in `actions/*.json` in this repo, read-only; "Custom" is a Member with `action: "custom"` and no routing text.

### 5. Easy creation flow
1. **New Team** sheet: a name, a level (yours or repo's), a starting point: *Blank* (just the Orchestrator), *Solo* (execute + verify), *Standard* (scan > execute > verify, plus run), *Research-heavy* (research + scan > execute > verify), or *Copy of…*; and a provider preset (Claude, Kiro, Codex) that fills the models and effort.
2. It lands on the canvas with the starter tree. Selecting a node shows its inspector.
3. **Add a Member**: drag a chip from the palette onto a node, or press the node's `+` (or ⌘N) and pick an Action; the Member arrives prefilled from the Action's default Profile and the provider preset.
4. **Custom Worker**: "Custom" in the palette creates a Member and a new Profile together, and opens the role in the inspector (no file step).
5. Save validates (the daemon's existing model/CLI checks) and says what is wrong on the node that is wrong, not at the bottom.

### 6. Drag and drop
- Drag a Member onto another to make it a child, between two to reorder, out to the root level to promote. A line and a highlight show where it lands; an invalid drop (verify not under execute, too deep) shows why and does nothing.
- Drag palette chips in. Dropping onto the trash area or pressing ⌫ deletes (after asking when it has children).
- Keyboard-first (ui-ux/0008): ↑/↓ select, ⌘↑/⌘↓ move among siblings, ⌘→ indent under the previous sibling, ⌘← outdent, ⌘D duplicate, ⌫ delete.
- Technique: a custom recursive tree view with `.draggable` / `.dropDestination` (already used in `FilePreview.swift`), not `List`/`OutlineGroup`, whose drops cannot reparent. The CLT-only build rule applies: no `@State` macro, local state in an `ObservableObject`. The first milestone is a spike that proves reparenting and reordering drops work in a CLT build, before the rest depends on it.
- Edits live in a draft with Save and Revert, as the Teams page works now; the tree stays reversible until Save.

### 7. What an Orchestrator is told
A Team with Members adds a generated "Your Workers" section after the rules and before the Team's `instructions`: one line per Member (id, Action, the Profile's description, model), the hand-off order from the tree, and the start command. The Orchestrator no longer needs `echoctl profile list` to choose; a Member's role text is not copied into it.

## Goals
1. One Settings section replacing Agents and Teams; no setting is lost (default CLI/model, `forceCli`, Orchestrator rules and lessons, Profile fields, Team fields all remain reachable).
2. Team files with Members, validated, three levels, backward compatible; shipped Teams rewritten as trees.
3. Workers start by Member id with the Member's overrides applied (model, effort, instruction, tools, skills, context); the verifier child is used by `--verify`.
4. A New Team flow from template to saved Team in under a minute with no file editing.
5. A draggable tree with the palette, inspector, keyboard moves and drop validation.
6. A real run on Kiro with a three-Member tree, and screenshots in `docs/screenshots/`.

## Milestones (rough; the detailed plan splits them into tasks)
- **M0 Decisions and spike**: new decision files (Member and Action, tree meaning, one Settings section superseding ui-ux/0043, file format); a throwaway SwiftUI spike proving reparent and reorder drops; the Action files. Gate for everything else.
- **M1 Daemon: Members in Teams**: `team.rs` model and validation, load/save/list with Members, Action list, resolution order, `echoctl team show` printing the tree, tests (every step of the order, bad trees, backward compat).
- **M2 Daemon: Members at work**: `worker start <member>`, `workers.member` migration, instruction/tools/skills/context overlay in `profile::system_prompt` and the Kiro agent file, the Orchestrator's "Your Workers" section, `--verify` using the verifier Member, resume re-reading an edited Team.
- **M3 Echo: the merged section**: one `SettingsSection`, Teams list, Defaults row, root and Member inspectors (no drag yet), New Team sheet with templates, removal of the two old pages; Swift decoders and form-state tests.
- **M4 Echo: the tree**: canvas, palette, drag and drop, keyboard moves, inline validation, the "Edit shared role…" flow.
- **M5 Proof and docs**: Kiro smoke run, screenshots, README Teams section, CONTEXT.md, decisions, a `docs/bugs/` file for anything found.

M1 and M3 can run in parallel once the file format of section 4 is frozen in M0; M2 follows M1; M4 follows M3 and the spike.

## Non-goals
Nested orchestration (Members starting Members); Teams for Normal sessions and Terminals; a per-repo default Team; user-defined Actions beyond Custom; Echo Remote editing of Teams; Kiro stats or renewal; mixing Members from several Teams; a visual graph with free positioning (the tree is an outline, not a canvas of boxes and wires).

## Risks
- **Drag and drop on a CLT-only build** may not support reparenting cleanly. Mitigation: M0 spike; fallback is the keyboard moves plus a "Move to…" menu per node, which M4 builds anyway.
- **Two sources for one value** (Profile file vs Member override) confuses. Mitigation: the inspector shows each field's source ("from naruto", "this Team") and a Reset per field.
- **Tool names per CLI**: Kiro and Codex honour Claude-named tools unevenly; the inspector warns when a CLI ignores a tool, using the mapping `cli.rs` already has.
- **Instructions inside JSON** are long multi-line strings in git diffs. Accepted for v1; a `teams/<name>/<member>.md` split is possible later without changing the model.
- **Migration**: users' existing Teams and Profile edits must keep working untouched; covered by the backward-compat tests in M1.

## Choices made for open questions (recommended options; say if you want one changed)
1. The tree is a plan of hand-offs, not nested workers (section 3).
2. The merged section is titled **Teams**; the old Agents content moves into Defaults and the Members' inspectors.
3. A Member's instruction is added after the Profile's role unless "replace the role" is on.
4. Member edits are scoped to the Team; editing the shared Profile is a separate, labelled button.
5. Shipped Actions are fixed (six plus Custom); you cannot define new Actions in v1.
6. Shipped Teams (`claude-opus`, `claude-lean`, `kiro-lean`) become trees with the same models as today, so a first run behaves as it does now.

## Constraints (as in the Teams plan)
Obey decisions in force and never edit a committed one (supersede with a new file, numbered after `features/0083` and the latest `ui-ux/`); a bug found gets a `docs/bugs/` file; any daemon run uses `HUB_STATE=/tmp/hubk`; `~/.kiro` is the human's (only `echo-*.md` agent files may be added or removed); real Kiro runs use `claude-haiku-5.5` or `claude-sonnet-5.5`, short; never touch the human's running daemon, Echo or Kiro; do not run `make -C app app` (use `swift build --product HubApp` in `app/`); do not delete `target/` or `app/.build/`; `Ledger` tokens only; commit prefixes `Daemon:`, `Echo:`, `Docs:`, no attribution, no em dashes, never push, amend or rebase.

## Acceptance
`cargo fmt --check`, `~/.cargo/bin/cargo test -p echoctl` and `make -C app test` pass. Tests cover Member parsing and validation, the three levels, every step of the resolution order including `forceCli`, a Team without Members unchanged, a Member's overlay reaching the Worker's prompt for each CLI, the verifier child used by `--verify`, the migration on an existing database, the tree operations (move, indent, outdent, invalid drops) as pure functions, and the Swift decoders. The M5 smoke run and screenshots are quoted in the report, and the tree is clean at the end apart from this plan's `status.md`.

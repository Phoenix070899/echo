import Foundation

/// Settings > Profiles' editor, as plain values (ui-ux/0145): a Profile loaded into fields, the
/// fields turned back into the `profile.set` request, and the Teams whose Members start from it.
/// The daemon checks the file once more and its message is shown as it is.
public struct ProfileForm: Equatable, Sendable {
    /// Where a Profile is kept, as `profiles.list` and `profile.*` name the levels.
    public static let yours = "yours"
    public static let repo = "repo"
    public static let builtIn = "built-in"

    /// The worktree hints a Profile may give; empty leaves it to the Member's Action.
    public static let worktrees = ["current", "new"]

    public var name = ""
    /// "yours", "repo" or "built-in".
    public var level = ProfileForm.yours
    public var description = ""
    /// A picture in Echo's `Faces/` (`r01c01`); empty for none.
    public var face = ""
    /// Empty text means unset in the three fields below.
    public var cli = ""
    public var model = ""
    public var effort = ""
    public var tools: [String] = []
    public var skills: [String] = []
    public var context: [String] = []
    public var lessons = true
    public var writes = false
    /// "", "current" or "new".
    public var worktree = ""
    public var role = ""

    public init() {}

    /// A listed Profile in the fields, as its own file says them, not as it runs here.
    public init(profile: WorkerProfile) {
        name = profile.name
        level = profile.level ?? Self.builtIn
        description = profile.description
        face = profile.face ?? ""
        cli = profile.ownCli ?? ""
        model = profile.ownModel ?? ""
        effort = profile.ownEffort ?? ""
        tools = profile.tools ?? []
        skills = profile.skills ?? []
        context = profile.context ?? []
        lessons = profile.lessons ?? true
        writes = profile.writes
        worktree = profile.worktree ?? ""
        role = profile.role ?? ""
    }

    /// Echo's own Profiles are not written; Make my copy first (ui-ux/0145, ui-ux/0100).
    public var readOnly: Bool { level == Self.builtIn }

    /// Why it cannot be saved yet, in the words for the human; nil when it can.
    public var blocker: String? {
        if description.contains("\n") { return "The description is one line." }
        if role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Write its role: it is what its Worker is told to be."
        }
        if !worktree.isEmpty, !Self.worktrees.contains(worktree) {
            return "Worktree is current or new."
        }
        return nil
    }

    /// How many fields differ from `saved`, for the bar under the Profile.
    public func changeCount(from saved: ProfileForm) -> Int {
        let a = self, b = saved
        return [
            a.description != b.description, a.face != b.face, a.cli != b.cli, a.model != b.model, a.effort != b.effort,
            a.tools != b.tools, a.skills != b.skills, a.context != b.context, a.lessons != b.lessons,
            a.writes != b.writes, a.worktree != b.worktree, a.role != b.role,
        ].filter { $0 }.count
    }

    /// Every field as `profile.set` takes it, the role among them; an empty text empties the field.
    public var fields: [String: Any] {
        [
            "description": trimmed(description), "face": face, "cli": trimmed(cli), "model": trimmed(model),
            "effort": trimmed(effort), "tools": tools, "skills": skills, "context": context,
            "lessons": lessons, "writes": writes, "worktree": worktree, "role": role,
        ]
    }

    /// The `profile.set` parameters: the Profile's own level, and the repo a repo's Profile lives in.
    public func saveParams(repo: String?) -> [String: Any] {
        var params: [String: Any] = ["name": name, "level": level, "fields": fields]
        if let repo { params["repo"] = repo }
        return params
    }

    /// The Profile names are file names: 1 to 32 lowercase letters, digits and `-`, not starting
    /// with `-`, as the daemon checks them.
    public static func validName(_ name: String) -> Bool {
        TeamForm.validID(name)
    }

    /// `name-copy`, else `name-copy-2` and on, the first not in `taken`, within 32 characters.
    public static func copyName(of name: String, taking taken: [String]) -> String {
        var number = 1
        while true {
            let suffix = number == 1 ? "-copy" : "-copy-\(number)"
            var base = String(name.prefix(32 - suffix.count))
            while base.hasSuffix("-") { base.removeLast() }
            let candidate = base + suffix
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A Team whose Members start from one Profile, with those Members' ids: one row of "Used by".
public struct ProfileUse: Equatable, Sendable {
    public let team: String
    /// Where the Team comes from: "shipped", "user" or "repo".
    public let origin: String
    public let members: [String]

    public init(team: String, origin: String, members: [String]) {
        self.team = team
        self.origin = origin
        self.members = members
    }

    /// The Teams in `teams` with a Member on `profile`, in list order (features/0096).
    public static func of(_ profile: String, in teams: [Team]) -> [ProfileUse] {
        teams.compactMap { team in
            let members = team.members.filter { $0.profile == profile }.map(\.id)
            return members.isEmpty ? nil : ProfileUse(team: team.name, origin: team.origin, members: members)
        }
    }
}

// MARK: Tools

/// The checklist of tools a Profile can name, and what a CLI makes of a list.
public enum ProfileTools {
    /// Claude's names for them, in the order the checklist shows.
    public static let all = ["Read", "Grep", "Glob", "Edit", "Write", "Bash", "WebFetch", "WebSearch"]

    /// What Kiro can do with a Claude-named tool (`cli.rs`'s `kiro_tools`); the others it leaves out.
    public static let kiroMapped: Set<String> = ["Bash", "Read", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch"]

    /// `tools` with `tool` checked or unchecked, in the checklist's order and with names the
    /// checklist does not know kept after it. The last tool is never unchecked: a Profile that names
    /// no tool gets every tool of its CLI, which an empty checklist would hide.
    public static func toggled(_ tools: [String], _ tool: String, on: Bool) -> [String] {
        var chosen = Set(tools)
        if on { chosen.insert(tool) } else { chosen.remove(tool) }
        let result = all.filter(chosen.contains) + tools.filter { !all.contains($0) && chosen.contains($0) }
        return result.isEmpty && !tools.isEmpty ? tools : result
    }

    /// What the CLI does with the list, when it does not use all of it; nil when it does.
    public static func note(tools: [String], cli: String) -> String? {
        guard !tools.isEmpty else { return nil }
        switch cli {
        case "codex":
            return "Codex ignores a tool list and uses its own tools."
        case "kiro":
            let left = tools.filter { !kiroMapped.contains($0) }
            if left.isEmpty { return nil }
            if left.count == tools.count {
                return "Kiro has no \(named(left)), so it gets its whole set of tools."
            }
            return "Kiro has no \(named(left)) and leaves \(left.count == 1 ? "it" : "them") out."
        default:
            return nil
        }
    }

    /// "Grep", "Grep and Glob", "Grep, Glob and Foo".
    private static func named(_ tools: [String]) -> String {
        guard let last = tools.last, tools.count > 1 else { return tools.first ?? "" }
        return tools.dropLast().joined(separator: ", ") + " and " + last
    }
}

// MARK: Skills

/// The checklist of skills a Profile can name (features/0099, ui-ux/0147): the ones its CLI has,
/// grouped by where they come from, with the ones it names but the CLI lacks kept in sight.
public enum ProfileSkills {
    /// Over this many, the checklist offers a filter.
    public static let filterOver = 10

    /// One line of the checklist.
    public struct Row: Equatable, Sendable, Identifiable {
        public let name: String
        public let description: String
        /// False for a skill the Profile names that its CLI does not have.
        public let installed: Bool
        /// For a bare name the CLI lacks, the one plugin skill it has by that name, like
        /// `matt:tdd` for `tdd`, offered in its place.
        public var match: String? = nil
        public var id: String { name }
    }

    /// A heading and its rows.
    public struct Group: Equatable, Sendable, Identifiable {
        public let title: String
        public let rows: [Row]
        public var id: String { title }
    }

    /// The checklist: first the named skills the CLI lacks, under Not installed, so a save never
    /// drops one unseen; then the CLI's own, by source in the daemon's order (yours, this repo, each
    /// plugin, the CLI's built-in ones). `filter` keeps the rows whose name or description has it.
    public static func groups(installed: [SkillOption], chosen: [String], filter: String = "") -> [Group] {
        let known = Set(installed.map(\.name))
        let needle = filter.trimmingCharacters(in: .whitespaces)
        let keep = { (row: Row) in
            needle.isEmpty || row.name.localizedCaseInsensitiveContains(needle)
                || row.description.localizedCaseInsensitiveContains(needle)
        }
        var out: [Group] = []
        let missing = chosen.filter { !known.contains($0) }
            .map { Row(name: $0, description: "", installed: false, match: match(for: $0, in: installed)) }.filter(keep)
        if !missing.isEmpty { out.append(Group(title: "Not installed", rows: missing)) }
        var titles: [String] = []
        var rows: [String: [Row]] = [:]
        for skill in installed {
            let row = Row(name: skill.name, description: skill.description, installed: true)
            guard keep(row) else { continue }
            let title = title(of: skill)
            if rows[title] == nil { titles.append(title) }
            rows[title, default: []].append(row)
        }
        let order = ["Yours", "This repo"]
        let sorted = titles.filter(order.contains).sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
            + titles.filter { !order.contains($0) && $0 != builtIn } + titles.filter { $0 == builtIn }
        out += sorted.map { Group(title: $0, rows: rows[$0] ?? []) }
        return out
    }

    private static let builtIn = "Built in"

    /// The plugin skill `name` most likely means: the only installed one named `<plugin>:name`.
    /// Nil when `name` has a prefix already, or when none or several plugins have it.
    public static func match(for name: String, in installed: [SkillOption]) -> String? {
        guard !name.contains(":") else { return nil }
        let found = installed.map(\.name).filter { $0.hasSuffix(":" + name) }
        return found.count == 1 ? found[0] : nil
    }

    /// `chosen` with `name` swapped for `match` in its place, dropping `match` where it already was.
    public static func replaced(_ chosen: [String], _ name: String, with match: String) -> [String] {
        chosen.filter { $0 != match }.map { $0 == name ? match : $0 }
    }

    /// The heading a skill is listed under.
    public static func title(of skill: SkillOption) -> String {
        switch skill.source {
        case "yours": "Yours"
        case "repo": "This repo"
        case "built-in": builtIn
        default: skill.plugin ?? skill.source
        }
    }

    /// `chosen` with `name` checked or unchecked: a newly checked skill goes last, and the others
    /// keep their order, so the Profile's file changes only where the human did.
    public static func toggled(_ chosen: [String], _ name: String, on: Bool) -> [String] {
        let without = chosen.filter { $0 != name }
        return on ? without + [name] : without
    }

    /// The one line shown when the CLI has no skills.
    public static func none(cli: String) -> String {
        switch cli {
        case "kiro": "Kiro has no skills."
        case "codex": "Codex has no skills installed."
        default: "Claude Code has no skills installed."
        }
    }
}

// MARK: Drafting with an agent

/// A Profile drafted by an agent (features/0101): the fields it may set, what it says it did, and
/// the tools and skills it named that Echo does not offer, which the daemon dropped.
public struct ProfileDraft: Decodable, Equatable, Sendable {
    public struct Fields: Decodable, Equatable, Sendable {
        public var description: String
        public var tools: [String]
        public var skills: [String]
        public var context: [String]
        public var writes: Bool
        public var role: String

        public init(description: String, tools: [String], skills: [String], context: [String], writes: Bool, role: String) {
            self.description = description
            self.tools = tools
            self.skills = skills
            self.context = context
            self.writes = writes
            self.role = role
        }
    }

    public var fields: Fields
    public var summary: String
    public var dropped: [String]

    public init(fields: Fields, summary: String, dropped: [String] = []) {
        self.fields = fields
        self.summary = summary
        self.dropped = dropped
    }

    /// The line under the box once it lands.
    public var note: String {
        let said = summary.isEmpty ? "Drafted." : summary
        return dropped.isEmpty ? said : "\(said) Left out, as Echo does not offer them: \(dropped.joined(separator: ", "))."
    }
}

extension ProfileForm {
    /// The form with the draft's fields in place; CLI, model, effort and the rest stay.
    public func applying(_ draft: ProfileDraft) -> ProfileForm {
        var form = self
        form.description = draft.fields.description
        form.tools = draft.fields.tools
        form.skills = draft.fields.skills
        form.context = draft.fields.context
        form.writes = draft.fields.writes
        form.role = draft.fields.role
        return form
    }

    /// The form as the drafting agent is shown it.
    public var draftForm: [String: Any] {
        [
            "name": name, "description": description, "tools": tools, "skills": skills, "context": context,
            "writes": writes, "role": role,
        ]
    }
}

/// Which agent drafts Profiles (features/0101): a CLI and a model, remembered on this Mac.
public enum ProfileDrafter {
    public static let defaultCli = "claude"
    public static let defaultModel = "anthropic/claude-sonnet-5-5"

    /// The CLI as people call it.
    public static func name(of cli: String) -> String {
        switch cli {
        case "codex": "Codex"
        case "kiro": "Kiro"
        default: "Claude Code"
        }
    }

    /// The CLI to draft with: the remembered one while it is signed in, else the first that is.
    public static func cli(remembered: String, signedIn: [String]) -> String {
        signedIn.contains(remembered) || signedIn.isEmpty ? remembered : signedIn[0]
    }

    /// "Claude Code · Sonnet 5.5", or the CLI alone on its own default model.
    public static func label(cli: String, model: String, models: [ModelOption]) -> String {
        guard !model.isEmpty else { return name(of: cli) }
        return "\(name(of: cli)) · \(models.first { $0.id == model }?.name ?? model)"
    }
}

// MARK: Comma separated lists

/// Context is typed as one line: names with commas between.
public enum CommaList {
    /// The names between the commas, trimmed, without blanks or repeats.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// "a, b, c"
    public static func format(_ names: [String]) -> String {
        names.joined(separator: ", ")
    }
}

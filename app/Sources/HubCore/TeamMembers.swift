import Foundation

/// The Member inspector's pure parts (ui-ux/0101, features/0084, features/0085): editing one Member
/// of the draft, and working out what each of its fields comes to and where that comes from. The
/// inspector only draws what these return.

// MARK: Fields

/// A field of a Member that the Member itself may set, or leave to the level below.
public enum MemberField: CaseIterable, Sendable {
    case instructions, cli, model, effort, tools, skills, context, lessons, writes, worktree
}

extension Team.Member {
    /// Whether the Member sets the field itself, rather than leaving it to the level below.
    public func isSet(_ field: MemberField) -> Bool {
        switch field {
        case .instructions: !(instructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replaceRole != nil
        case .cli: !(cli ?? "").isEmpty
        case .model: !(model ?? "").isEmpty
        case .effort: !(effort ?? "").isEmpty
        case .tools: !tools.isEmpty
        case .skills: !skills.isEmpty
        case .context: !context.isEmpty
        case .lessons: lessons != nil
        case .writes: writes != nil
        case .worktree: !(worktree ?? "").isEmpty
        }
    }

    /// Takes the Member's own value out, so the field follows the level below again. Clearing the
    /// instruction takes the "replace the role" choice with it.
    public mutating func clear(_ field: MemberField) {
        switch field {
        case .instructions:
            instructions = nil
            replaceRole = nil
        case .cli: cli = nil
        case .model: model = nil
        case .effort: effort = nil
        case .tools: tools = []
        case .skills: skills = []
        case .context: context = []
        case .lessons: lessons = nil
        case .writes: writes = nil
        case .worktree: worktree = nil
        }
    }
}

// MARK: Editing the draft

extension TeamForm {
    /// The Member by id.
    public func member(_ id: String) -> Team.Member? {
        members.first { $0.id == id }
    }

    /// Changes one Member in place; nothing happens for an id no Member has.
    public mutating func updateMember(_ id: String, _ change: (inout Team.Member) -> Void) {
        guard let at = members.firstIndex(where: { $0.id == id }) else { return }
        change(&members[at])
    }

    /// Takes the Member's own value for `field` out.
    public mutating func clearMember(_ id: String, _ field: MemberField) {
        updateMember(id) { $0.clear(field) }
    }

    /// Gives the Member a new id and points its children's `parent` at it. A refusal names why in
    /// one plain line and changes nothing; nil means it is done (also when the id is unchanged).
    public mutating func renameMember(_ id: String, to newID: String) -> String? {
        let name = newID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard members.contains(where: { $0.id == id }) else { return "That Member is not in the tree." }
        if name == id { return nil }
        if !Self.validID(name) {
            return "An id is 1 to 32 lowercase letters, digits and -, not starting with -, like build-2."
        }
        if members.contains(where: { $0.id == name }) {
            return "\(name): another Member has this id. Give each Member its own."
        }
        for at in members.indices {
            if members[at].id == id { members[at].id = name }
            if members[at].parent == id { members[at].parent = name }
        }
        return nil
    }

    /// Makes the Member do `action`. A change that leaves the tree broken is refused with the
    /// reason and changes nothing: a `verify` Member needs an `execute` parent, and an `execute`
    /// Member cannot change while a `verify` Member sits under it. The Profile stays as it is;
    /// `offeredProfile` says when the Action has another default.
    public mutating func changeMemberAction(_ id: String, to action: String) -> String? {
        guard let member = member(id) else { return "That Member is not in the tree." }
        if member.action == action { return nil }
        guard Action.isAction(action) else {
            return "\"\(action)\" is not an Action. Use " + (Action.shippedIDs + [Action.custom]).joined(separator: ", ") + "."
        }
        var changed = members
        if let at = changed.firstIndex(where: { $0.id == id }) { changed[at].action = action }
        if Self.problem(with: members) == nil, let problem = Self.problem(with: changed) {
            return problem
        }
        members = changed
        return nil
    }

    /// The default Profile of `action`, nil for `custom` and for a word that is no Action.
    public static func defaultProfile(for action: String, actions: [Action] = Action.shipped) -> String? {
        actions.first { $0.id == action }?.profile
    }

    /// The Profile the Member's Action starts from, when that is not the Profile the Member has:
    /// offered after the Action is changed, never applied on its own.
    public func offeredProfile(for id: String, actions: [Action] = Action.shipped) -> String? {
        guard let member = member(id),
              let profile = Self.defaultProfile(for: member.action, actions: actions),
              profile != member.profile else { return nil }
        return profile
    }

    /// Adds a `custom` Member on `profile` at level 1, named after the Profile, and returns its
    /// id; nil when the Team already holds as many Members as it can, or `profile` is empty.
    public mutating func addCustomMember(profile: String) -> String? {
        let profile = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.isEmpty,
              let added = TeamTree.add(action: Action.custom, profile: profile, to: members) else { return nil }
        members = added.members
        let id = TeamTree.uniqueID(from: profile, taking: Set(members.map(\.id)))
        return renameMember(added.id, to: id) == nil ? id : added.id
    }
}

// MARK: Where a value comes from

/// What a field comes to for a Member, and which level said so.
public struct MemberValue<Value: Equatable & Sendable>: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case member
        /// The Team's `workers.profiles` entry for the Member's Profile.
        case teamProfile(String)
        case teamWorkers
        case profile(String)
        case action(String)
        /// Your settings: the default CLI and model, which a repo's settings may replace.
        case defaults
        /// Nothing sets it, so Echo's own default stands.
        case standard
    }

    public let value: Value
    public let source: Source

    public init(_ value: Value, from source: Source) {
        self.value = value
        self.source = source
    }

    /// Whether the Member itself says it, which is when Reset has something to clear.
    public var isOwn: Bool { source == .member }

    /// Where it comes from, in the words shown under the field: "from naruto", "this Team's
    /// Workers", "your defaults".
    public var sourceText: String {
        switch source {
        case .member: "this Member"
        case .teamProfile(let profile): "this Team, set apart for \(profile)"
        case .teamWorkers: "this Team's Workers"
        case .profile(let name): "from \(name)"
        case .action(let id): "from the \(id) Action"
        case .defaults: "your defaults"
        case .standard: "the default"
        }
    }
}

/// Your default CLI and model, as far as they decide what a Member runs with (features/0075).
public struct MemberDefaults: Equatable, Sendable {
    public var cli = "claude"
    /// Empty leaves the model to the CLI.
    public var model = ""
    /// The CLI and model are used for every agent over a Profile's own.
    public var forceCli = false

    public init(cli: String = "claude", model: String = "", forceCli: Bool = false) {
        self.cli = cli
        self.model = model
        self.forceCli = forceCli
    }

    public init(settings: AgentSettings?) {
        self.init(cli: settings?.cli ?? "claude", model: settings?.model ?? "", forceCli: settings?.forceCli ?? false)
    }
}

/// The three choices of how a Worker runs, which follow one order (features/0085).
public enum RunSetting: Sendable {
    case cli, model, effort
}

extension TeamForm {
    /// What `setting` comes to for `member`, by the order of features/0085: the Member, the Team's
    /// entry for its Profile, the Team's Workers, then the Profile, then your defaults. With
    /// `forceCli` on, the CLI and model skip the Profile, as the daemon does. An empty value means
    /// no level names it, and the CLI's own choice stands.
    public func resolve(_ setting: RunSetting, for member: Team.Member, profile: WorkerProfile?,
                        defaults: MemberDefaults) -> MemberValue<String> {
        let apart = overrides.first { $0.profile == member.profile }
        let levels: [(String?, MemberValue<String>.Source)]
        let own: String?
        let fallback: String
        switch setting {
        case .cli:
            levels = [(member.cli, .member), (apart?.cli, .teamProfile(member.profile)), (workersCli, .teamWorkers)]
            own = profile?.ownCli
            fallback = defaults.cli
        case .model:
            levels = [(member.model, .member), (apart?.model, .teamProfile(member.profile)), (workersModel, .teamWorkers)]
            own = profile?.ownModel
            fallback = defaults.model
        case .effort:
            levels = [(member.effort, .member), (apart?.effort, .teamProfile(member.profile)), (workersEffort, .teamWorkers)]
            own = profile?.ownEffort
            fallback = ""
        }
        for (value, source) in levels {
            if let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                return MemberValue(value, from: source)
            }
        }
        let forced = defaults.forceCli && setting != .effort
        if !forced, let own, !own.isEmpty { return MemberValue(own, from: .profile(member.profile)) }
        return MemberValue(fallback, from: .defaults)
    }
}

extension Team.Member {
    /// The tools, skills or context the Worker gets: the Member's own list when it has one, else
    /// the Profile's. `field` must be one of those three; any other gives an empty list.
    public func listValue(_ field: MemberField, profile: WorkerProfile?) -> MemberValue<[String]> {
        let (own, inherited): ([String], [String]?)
        switch field {
        case .tools: (own, inherited) = (tools, profile?.tools)
        case .skills: (own, inherited) = (skills, profile?.skills)
        case .context: (own, inherited) = (context, profile?.context)
        default: return MemberValue([], from: .standard)
        }
        return own.isEmpty ? MemberValue(inherited ?? [], from: .profile(self.profile)) : MemberValue(own, from: .member)
    }

    /// Whether the Lessons of the repo go into the Worker's prompt; on unless the Member says no.
    public var lessonsValue: MemberValue<Bool> {
        lessons.map { MemberValue($0, from: .member) } ?? MemberValue(true, from: .standard)
    }

    /// Whether the Member writes, for the reader: its own word, else its Profile's.
    public func writesValue(profile: WorkerProfile?) -> MemberValue<Bool> {
        if let writes { return MemberValue(writes, from: .member) }
        return MemberValue(profile?.writes ?? false, from: .profile(self.profile))
    }

    /// "current" or "new": its own word, else its Action's, else the current checkout.
    public func worktreeValue(actions: [Action] = Action.shipped) -> MemberValue<String> {
        if let worktree, !worktree.isEmpty { return MemberValue(worktree, from: .member) }
        if let found = actions.first(where: { $0.id == action }) { return MemberValue(found.worktree, from: .action(found.id)) }
        return MemberValue("current", from: .standard)
    }

    /// What the instruction does to the Profile's role, in one line.
    public func instructionNote(roleOf profile: String) -> String {
        let text = (instructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && replaceRole != true { return "Empty: \(profile)'s role is used as it is." }
        return replaceRole == true ? "Replaces \(profile)'s role." : "Added after \(profile)'s role."
    }
}

// MARK: Tools

/// The checklist of tools a Member can name, and what a CLI makes of a list.
public enum MemberTools {
    /// Claude's names for them, in the order the checklist shows.
    public static let all = ["Read", "Grep", "Glob", "Edit", "Write", "Bash", "WebFetch", "WebSearch"]

    /// What Kiro can do with a Claude-named tool (`cli.rs`'s `kiro_tools`); the others it leaves out.
    public static let kiroMapped: Set<String> = ["Bash", "Read", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch"]

    /// `tools` with `tool` checked or unchecked, in the checklist's order and with names the
    /// checklist does not know kept after it. The last tool is never unchecked: an empty list means
    /// the Member names none, and the Profile's list applies again.
    public static func toggled(_ tools: [String], _ tool: String, on: Bool) -> [String] {
        var chosen = Set(tools)
        if on { chosen.insert(tool) } else { chosen.remove(tool) }
        let result = all.filter(chosen.contains) + tools.filter { !all.contains($0) && chosen.contains($0) }
        return result.isEmpty ? tools : result
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

// MARK: Comma separated lists

/// Skills and context are typed as one line: names with commas between.
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

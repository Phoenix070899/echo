import Foundation

/// The Member inspector's pure parts (ui-ux/0101, ui-ux/0145, features/0094): editing one Member of
/// the draft, and working out what its CLI, model and effort come to and where that comes from.
/// Everything else about its Worker is its Profile's, edited in Settings > Profiles. The inspector
/// only draws what these return.

// MARK: Fields

/// A field of a Member that the Member itself may set, or leave to the level below.
public enum MemberField: CaseIterable, Sendable {
    case cli, model, effort
}

extension Team.Member {
    /// Whether the Member sets the field itself, rather than leaving it to the level below.
    public func isSet(_ field: MemberField) -> Bool {
        switch field {
        case .cli: !(cli ?? "").isEmpty
        case .model: !(model ?? "").isEmpty
        case .effort: !(effort ?? "").isEmpty
        }
    }

    /// Takes the Member's own value out, so the field follows the level below again.
    public mutating func clear(_ field: MemberField) {
        switch field {
        case .cli: cli = nil
        case .model: model = nil
        case .effort: effort = nil
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

    /// Gives the Member a new id and points the Hand-offs from it at the new one. A refusal names why in
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
            members[at].after = members[at].after?.map { $0.from == id ? Team.HandOff(from: name, auto: $0.auto) : $0 }
        }
        return nil
    }

    /// Makes the Member do `action`. A change that leaves the Team broken is refused with the
    /// reason and changes nothing: a `verify` Member comes only after `execute` Members, and an
    /// `execute` Member cannot change while a `verify` Member comes after it. The Profile stays as it is;
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

    /// Adds a `custom` Member on `profile` after `source` (the Orchestrator when nil), named after
    /// the Profile, and returns its id; nil when the Team already holds as many Members as it can
    /// or `profile` is empty.
    public mutating func addCustomMember(profile: String, after source: String? = nil) -> String? {
        let profile = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.isEmpty else { return nil }
        let added = TeamGraph.add(action: Action.custom, profile: profile, after: source, to: members)
        guard added.notice == nil, let addedID = added.selected else { return nil }
        members = added.members
        let id = TeamGraph.uniqueID(from: profile, taking: Set(members.map(\.id)))
        return renameMember(addedID, to: id) == nil ? id : addedID
    }
}

// MARK: Where a value comes from

/// What a field comes to for a Member, and which level said so.
public struct MemberValue<Value: Equatable & Sendable>: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case member
        case teamWorkers
        case profile(String)
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
        case .teamWorkers: "this Team's Workers"
        case .profile(let name): "from \(name)"
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

/// The three choices of how a Worker runs, which follow one order (features/0094).
public enum RunSetting: Sendable {
    case cli, model, effort
}

extension TeamForm {
    /// What `setting` comes to for `member`, by the order of features/0094: the Member, the Team's
    /// Workers, then the Profile, then your defaults. With `forceCli` on, the CLI and model skip the
    /// Profile, as the daemon does. An empty value means no level names it, and the CLI's own choice
    /// stands.
    public func resolve(_ setting: RunSetting, for member: Team.Member, profile: WorkerProfile?,
                        defaults: MemberDefaults) -> MemberValue<String> {
        let levels: [(String?, MemberValue<String>.Source)]
        let own: String?
        let fallback: String
        switch setting {
        case .cli:
            levels = [(member.cli, .member), (workersCli, .teamWorkers)]
            own = profile?.ownCli
            fallback = defaults.cli
        case .model:
            levels = [(member.model, .member), (workersModel, .teamWorkers)]
            own = profile?.ownModel
            fallback = defaults.model
        case .effort:
            levels = [(member.effort, .member), (workersEffort, .teamWorkers)]
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

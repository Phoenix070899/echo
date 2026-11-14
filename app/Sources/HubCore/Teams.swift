import Foundation

/// A Team from `team.list`: a named setup for an Orchestrator, its Workers and its rules
/// (features/0081). Every field the file leaves out is nil, unknown fields are ignored, and a file
/// that does not parse arrives with a `problem` and none of the fields.
public struct Team: Decodable, Equatable, Identifiable, Sendable {
    /// What one part of the Team runs with; nil leaves it to the settings or the Profile.
    public struct Setup: Decodable, Equatable, Sendable {
        public var cli: String?
        public var model: String?
        public var effort: String?
        /// Context tokens at which an Orchestrator is renewed; Orchestrator only.
        public var rotateAt: Int?

        public init(cli: String? = nil, model: String? = nil, effort: String? = nil, rotateAt: Int? = nil) {
            self.cli = cli
            self.model = model
            self.effort = effort
            self.rotateAt = rotateAt
        }
    }

    public struct Workers: Decodable, Equatable, Sendable {
        public var cli: String?
        public var model: String?
        public var effort: String?
        /// Overrides for single Profiles, by Profile name.
        public var profiles: [String: Setup]?

        public init(cli: String? = nil, model: String? = nil, effort: String? = nil, profiles: [String: Setup]? = nil) {
            self.cli = cli
            self.model = model
            self.effort = effort
            self.profiles = profiles
        }
    }

    public struct Rules: Decodable, Equatable, Sendable {
        public var maxWorkers: Int?
        public var planApproval: Bool?
        public var review: Bool?
        public var mergeWithoutAsking: Bool?

        public init(maxWorkers: Int? = nil, planApproval: Bool? = nil, review: Bool? = nil,
                    mergeWithoutAsking: Bool? = nil) {
            self.maxWorkers = maxWorkers
            self.planApproval = planApproval
            self.review = review
            self.mergeWithoutAsking = mergeWithoutAsking
        }
    }

    /// One Worker slot of the Team's tree (features/0084): an Action, the Profile it starts from,
    /// and the changes this Team makes to that Profile. A field left out is nil (or empty, for a
    /// list) and means the level below.
    public struct Member: Decodable, Equatable, Identifiable, Sendable {
        public var id: String
        public var action: String
        public var profile: String
        /// The `id` of the Member above; nil at level 1.
        public var parent: String?
        public var instructions: String?
        public var replaceRole: Bool?
        public var cli: String?
        public var model: String?
        public var effort: String?
        public var tools: [String]
        public var skills: [String]
        public var context: [String]
        public var lessons: Bool?
        public var writes: Bool?
        /// "current" or "new".
        public var worktree: String?

        public init(id: String, action: String, profile: String, parent: String? = nil,
                    instructions: String? = nil, replaceRole: Bool? = nil, cli: String? = nil,
                    model: String? = nil, effort: String? = nil, tools: [String] = [],
                    skills: [String] = [], context: [String] = [], lessons: Bool? = nil,
                    writes: Bool? = nil, worktree: String? = nil) {
            self.id = id
            self.action = action
            self.profile = profile
            self.parent = parent
            self.instructions = instructions
            self.replaceRole = replaceRole
            self.cli = cli
            self.model = model
            self.effort = effort
            self.tools = tools
            self.skills = skills
            self.context = context
            self.lessons = lessons
            self.writes = writes
            self.worktree = worktree
        }

        private enum Key: String, CodingKey {
            case id, action, profile, parent, instructions, replaceRole, cli, model, effort
            case tools, skills, context, lessons, writes, worktree
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Key.self)
            id = try values.decode(String.self, forKey: .id)
            action = try values.decode(String.self, forKey: .action)
            profile = try values.decode(String.self, forKey: .profile)
            parent = try values.decodeIfPresent(String.self, forKey: .parent)
            instructions = try values.decodeIfPresent(String.self, forKey: .instructions)
            replaceRole = try values.decodeIfPresent(Bool.self, forKey: .replaceRole)
            cli = try values.decodeIfPresent(String.self, forKey: .cli)
            model = try values.decodeIfPresent(String.self, forKey: .model)
            effort = try values.decodeIfPresent(String.self, forKey: .effort)
            tools = try values.decodeIfPresent([String].self, forKey: .tools) ?? []
            skills = try values.decodeIfPresent([String].self, forKey: .skills) ?? []
            context = try values.decodeIfPresent([String].self, forKey: .context) ?? []
            lessons = try values.decodeIfPresent(Bool.self, forKey: .lessons)
            writes = try values.decodeIfPresent(Bool.self, forKey: .writes)
            worktree = try values.decodeIfPresent(String.self, forKey: .worktree)
        }
    }

    public let name: String
    /// Where it comes from: "shipped", "user" or "repo".
    public let origin: String
    public let path: String?
    /// The levels below that it replaces.
    public let replaces: [String]
    /// Why it cannot be used, when its file does not parse or does not validate.
    public let problem: String?
    public let description: String?
    public let orchestrator: Setup?
    public let workers: Workers?
    public let rules: Rules?
    public let instructions: String?
    /// The tree of Workers, flat and in tree order; a Member's `parent` names the Member above.
    public let members: [Member]

    public var id: String { name }

    public init(name: String, origin: String = "shipped", path: String? = nil, replaces: [String] = [],
                problem: String? = nil, description: String? = nil, orchestrator: Setup? = nil,
                workers: Workers? = nil, rules: Rules? = nil, instructions: String? = nil,
                members: [Member] = []) {
        self.name = name
        self.origin = origin
        self.path = path
        self.replaces = replaces
        self.problem = problem
        self.description = description
        self.orchestrator = orchestrator
        self.workers = workers
        self.rules = rules
        self.instructions = instructions
        self.members = members
    }

    private enum Key: String, CodingKey {
        case name, origin, path, replaces, problem, description, orchestrator, workers, rules, instructions
        case members
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        name = try values.decode(String.self, forKey: .name)
        origin = try values.decodeIfPresent(String.self, forKey: .origin) ?? ""
        path = try values.decodeIfPresent(String.self, forKey: .path)
        replaces = try values.decodeIfPresent([String].self, forKey: .replaces) ?? []
        problem = try values.decodeIfPresent(String.self, forKey: .problem)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        orchestrator = try values.decodeIfPresent(Setup.self, forKey: .orchestrator)
        workers = try values.decodeIfPresent(Workers.self, forKey: .workers)
        rules = try values.decodeIfPresent(Rules.self, forKey: .rules)
        instructions = try values.decodeIfPresent(String.self, forKey: .instructions)
        members = try values.decodeIfPresent([Member].self, forKey: .members) ?? []
    }

    /// Whether a new Orchestrator can start with it.
    public var usable: Bool { problem == nil }

    /// One line of what it runs: "Orchestrator: kiro, claude-sonnet-5.5, medium. Workers: by their
    /// Profiles." Workers read "by their Profiles" unless the Team names a CLI, model or effort
    /// for all of them.
    public var summary: String {
        let orchestratorParts = Self.parts(orchestrator?.cli, orchestrator?.model, orchestrator?.effort)
        let workerParts = Self.parts(workers?.cli, workers?.model, workers?.effort)
        let overrides = workers?.profiles?.count ?? 0
        var workersLine = workerParts.isEmpty ? "by their Profiles" : workerParts.joined(separator: ", ")
        if overrides > 0 {
            workersLine += ", \(overrides) Profile\(overrides == 1 ? "" : "s") set apart"
        }
        let first = orchestratorParts.isEmpty ? "the settings" : orchestratorParts.joined(separator: ", ")
        return "Orchestrator: \(first). Workers: \(workersLine)."
    }

    private static func parts(_ values: String?...) -> [String] {
        values.compactMap { $0 }.filter { !$0.isEmpty }
    }
}

/// What a Member is for, from `team.actions` (features/0087): Echo ships six, and `custom` is the
/// `action` of a Member built on a Profile of the human's own.
public struct Action: Decodable, Equatable, Identifiable, Sendable {
    /// The shipped ids, in the order the palette lists them.
    public static let shippedIDs = ["scan", "research", "execute", "verify", "run", "scribe"]
    public static let custom = "custom"

    public let id: String
    public let title: String
    public let description: String
    /// The Profile a Member of this Action starts from.
    public let profile: String
    /// The sentence the Orchestrator reads to know what to send it.
    public let routing: String
    public let writes: Bool
    /// "current" or "new": where the Member works.
    public let worktree: String
    /// The Action its Member must sit under; only `verify` has one.
    public let under: String?

    public init(id: String, title: String, description: String, profile: String, routing: String = "",
                writes: Bool = false, worktree: String = "current", under: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.profile = profile
        self.routing = routing
        self.writes = writes
        self.worktree = worktree
        self.under = under
    }

    /// Whether `id` can be a Member's `action`: one of the six, or `custom`.
    public static func isAction(_ id: String) -> Bool {
        id == custom || shippedIDs.contains(id)
    }
}

/// Which Team the New session sheet starts on, and how it is remembered.
public enum TeamChoice {
    /// The Team of the first experience, used until one is remembered.
    public static let fallback = "claude-opus"
    public static let key = "lastTeam"

    /// The Team to show: the one `current` names, else the remembered one, else `claude-opus`,
    /// else the first usable one. A Team with a problem is never picked; nil when none is usable.
    public static func pick(from teams: [Team], current: String?, remembered: String?) -> String? {
        let usable = teams.filter(\.usable).map(\.name)
        for name in [current, remembered, fallback] {
            if let name, usable.contains(name) { return name }
        }
        return usable.first
    }

    public static func remembered(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key)
    }

    public static func remember(_ name: String, in defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: key)
    }
}

/// The parameters of `agent.open` for a new agent. A Team goes only with an Orchestrator, and
/// then no model: a model picked for an Orchestrator would override its Team.
public func openAgentParams(repo: String, kind: Agent.Kind, name: String? = nil, model: String? = nil,
                            team: String? = nil, request: String? = nil, branch: String? = nil,
                            newBranch: String? = nil, base: String? = nil) -> [String: Any] {
    var params: [String: Any] = ["repo": repo, "kind": kind.rawValue]
    if let branch { params["branch"] = branch }
    if let newBranch { params["new_branch"] = newBranch }
    if let base, !base.isEmpty { params["base"] = base }
    if let name, !name.isEmpty { params["name"] = name }
    let team = kind == .orchestrator ? team.flatMap { $0.isEmpty ? nil : $0 } : nil
    if let team { params["team"] = team }
    if team == nil, let model, !model.isEmpty { params["model"] = model }
    if let request, !request.isEmpty { params["request"] = request }
    return params
}

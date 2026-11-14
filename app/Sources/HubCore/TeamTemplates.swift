import Foundation

extension Action {
    /// Echo's six Actions as `actions/*.json` holds them, in the palette's order. HubCore carries
    /// them so the tree's operations and the starting points need no daemon call; a test keeps this
    /// table equal to the files.
    public static let shipped: [Action] = [
        Action(id: "scan", title: "Scan code",
               description: "Read the code and explain how it works, without changing anything.",
               profile: "hinata", routing: "Send questions about how existing code works here.",
               writes: false, worktree: "current"),
        Action(id: "research", title: "Research",
               description: "Search the web and answer a question with cited sources.",
               profile: "jiraiya",
               routing: "Send questions that need information from the web or from documentation here.",
               writes: false, worktree: "current"),
        Action(id: "execute", title: "Write code",
               description: "Do one coding Task and report whether it is done.",
               profile: "naruto",
               routing: "Send one coding Task that changes files here, with the command that checks it.",
               writes: true, worktree: "new"),
        Action(id: "verify", title: "Verify",
               description: "Review the commits of the Member above it and run its check.",
               profile: "sasuke",
               routing: "Reviews the commits of the writer above it; the daemon sends the work here, so do not send it yourself.",
               writes: false, worktree: "current", under: "execute"),
        Action(id: "run", title: "Run commands",
               description: "Run terminal commands such as tests and builds, and report the output.",
               profile: "lee",
               routing: "Send terminal commands to run, such as tests, builds, installs or git, and get their exit codes and output back.",
               writes: false, worktree: "current"),
        Action(id: "scribe", title: "Keep notes",
               description: "Merge stated preferences and lessons into the files that keep them.",
               profile: "ino",
               routing: "Send a preference the human stated, or lessons a Worker learned, to be merged into the right file.",
               writes: false, worktree: "current"),
    ]
}

/// What a new Team starts with, in the New Team sheet: the Members it holds. Each Member starts
/// from its Action's default Profile (`Action.shipped`) and carries the ids of the shipped Teams.
public enum TeamTemplate: String, CaseIterable, Sendable {
    /// Just the Orchestrator.
    case blank
    /// A writer and its verifier.
    case solo
    /// scan, a writer with its verifier, and run.
    case standard
    /// research and scan, a writer with its verifier, and run.
    case researchHeavy

    public var title: String {
        switch self {
        case .blank: "Blank"
        case .solo: "Solo"
        case .standard: "Standard"
        case .researchHeavy: "Research-heavy"
        }
    }

    /// The one plain line the sheet shows under the title.
    public var summary: String {
        switch self {
        case .blank: "Just the Orchestrator. Add Workers yourself."
        case .solo: "One Worker that writes code, and one that verifies it."
        case .standard: "Scan, write with a verifier, and run commands."
        case .researchHeavy: "Research and scan first, then write with a verifier, and run commands."
        }
    }

    /// The Members, in tree order.
    public var members: [Team.Member] {
        switch self {
        case .blank: []
        case .solo: Self.writer
        case .standard: Self.member("scan", "scan") + Self.writer + Self.member("run", "run")
        case .researchHeavy:
            Self.member("research", "research") + Self.member("scan", "scan") + Self.writer
                + Self.member("run", "run")
        }
    }

    private static var writer: [Team.Member] {
        member("build", "execute") + member("check", "verify", under: "build")
    }

    private static func member(_ id: String, _ action: String, under parent: String? = nil) -> [Team.Member] {
        let profile = Action.shipped.first { $0.id == action }?.profile ?? ""
        return [Team.Member(id: id, action: action, profile: profile, parent: parent)]
    }
}

/// The CLI, model and effort a new Team's Orchestrator and Workers start with, per provider, as the
/// shipped Teams set them (`claude-opus`, `kiro-lean`). An empty string leaves the field unset,
/// which means the Profile's own choice (Workers) or the settings (Orchestrator).
public enum ProviderPreset: String, CaseIterable, Sendable {
    case claude
    case kiro
    case codex

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .kiro: "Kiro"
        case .codex: "Codex"
        }
    }

    public var orchestratorCli: String { rawValue }

    public var orchestratorModel: String {
        switch self {
        case .claude: "anthropic/claude-opus-5-5"
        case .kiro: "claude-sonnet-5.5"
        case .codex: ""
        }
    }

    public var orchestratorEffort: String {
        switch self {
        case .claude: "high"
        case .kiro: "medium"
        case .codex: ""
        }
    }

    /// Claude's Workers run as their Profiles say, and every Profile Echo ships is a Claude one.
    public var workersCli: String {
        switch self {
        case .claude: ""
        case .kiro, .codex: rawValue
        }
    }

    public var workersModel: String { self == .kiro ? "claude-haiku-5.5" : "" }

    public var workersEffort: String { self == .kiro ? "low" : "" }

    /// What a Member of `profile` runs on instead of the Workers' setting: on Kiro, naruto writes
    /// and sasuke verifies on Sonnet, as `kiro-lean` has them. Nil for every other Member.
    public func memberChoice(profile: String) -> (model: String, effort: String)? {
        guard self == .kiro else { return nil }
        switch profile {
        case "naruto": return ("claude-sonnet-5.5", "high")
        case "sasuke": return ("claude-sonnet-5.5", "medium")
        default: return nil
        }
    }
}

extension TeamForm {
    /// An unsaved Team named `name` at `level`, with the Members of `template` and the CLI, model
    /// and effort of `preset`. It passes `blocker` once `name` is a name.
    public static func starting(template: TeamTemplate, preset: ProviderPreset, name: String,
                                level: String = TeamForm.userLevel) -> TeamForm {
        var form = TeamForm()
        form.name = name
        form.isNew = true
        form.level = level
        form.orchestratorCli = preset.orchestratorCli
        form.orchestratorModel = preset.orchestratorModel
        form.orchestratorEffort = preset.orchestratorEffort
        form.workersCli = preset.workersCli
        form.workersModel = preset.workersModel
        form.workersEffort = preset.workersEffort
        form.members = template.members.map { member in
            var member = member
            if let choice = preset.memberChoice(profile: member.profile) {
                member.model = choice.model
                member.effort = choice.effort
            }
            return member
        }
        return form
    }
}

import Foundation

/// The Teams page's editor, as plain values: a Team loaded into fields, and the fields turned
/// back into the `team.save` request. Only a missing name is checked here; the daemon validates
/// everything else and its message is shown as it is (features/0081).
public struct TeamForm: Equatable, Sendable {
    /// One Profile whose Worker setup differs from the Team's Workers.
    public struct Override: Equatable, Identifiable, Sendable {
        public let id: Int
        public var profile: String
        public var cli: String
        public var model: String
        public var effort: String

        public init(id: Int, profile: String, cli: String = "", model: String = "", effort: String = "") {
            self.id = id
            self.profile = profile
            self.cli = cli
            self.model = model
            self.effort = effort
        }
    }

    /// Where a Team can be kept, as `team.save` names the levels.
    public static let userLevel = "user"
    public static let repoLevel = "repo"

    /// The efforts a Team may name; the daemon refuses the ones a CLI does not take.
    public static let efforts = ["low", "medium", "high", "xhigh", "max"]

    /// Empty text means unset in every text field below.
    public var name = ""
    /// False once the Team has been saved: its name is then fixed.
    public var isNew = true
    public var level = TeamForm.userLevel
    public var description = ""
    public var orchestratorCli = ""
    public var orchestratorModel = ""
    public var orchestratorEffort = ""
    /// Tokens, as typed.
    public var rotateAt = ""
    public var workersCli = ""
    public var workersModel = ""
    public var workersEffort = ""
    public var overrides: [Override] = []
    /// nil leaves a rule to the human's Orchestrator settings.
    public var maxWorkers: Int?
    public var planApproval: Bool?
    public var review: Bool?
    public var mergeWithoutAsking: Bool?
    public var instructions = ""
    private var nextOverrideID = 0

    public init() {}

    /// A saved Team in the fields. Its overrides come in Profile order, so the rows keep still.
    public init(team: Team) {
        name = team.name
        isNew = false
        level = team.origin == "repo" ? Self.repoLevel : Self.userLevel
        description = team.description ?? ""
        orchestratorCli = team.orchestrator?.cli ?? ""
        orchestratorModel = team.orchestrator?.model ?? ""
        orchestratorEffort = team.orchestrator?.effort ?? ""
        rotateAt = team.orchestrator?.rotateAt.map(String.init) ?? ""
        workersCli = team.workers?.cli ?? ""
        workersModel = team.workers?.model ?? ""
        workersEffort = team.workers?.effort ?? ""
        for (profile, setup) in (team.workers?.profiles ?? [:]).sorted(by: { $0.key < $1.key }) {
            overrides.append(Override(id: nextOverrideID, profile: profile, cli: setup.cli ?? "",
                                      model: setup.model ?? "", effort: setup.effort ?? ""))
            nextOverrideID += 1
        }
        maxWorkers = team.rules?.maxWorkers
        planApproval = team.rules?.planApproval
        review = team.rules?.review
        mergeWithoutAsking = team.rules?.mergeWithoutAsking
        instructions = team.instructions ?? ""
    }

    /// An unsaved copy of `team` under a free name. Echo's own Teams are copied into the human's
    /// level, which then replaces them; a repo's stays in its repo.
    public init(copying team: Team, taking names: [String]) {
        self.init(team: team)
        name = Self.copyName(of: team.name, taking: names)
        isNew = true
    }

    /// `name-copy`, else `name-copy-2`, `name-copy-3`, and so on, the first not in `taken`. A
    /// long name gives up its tail so the result stays within a Team's 40 characters.
    public static func copyName(of name: String, taking taken: [String]) -> String {
        var number = 1
        while true {
            let suffix = number == 1 ? "-copy" : "-copy-\(number)"
            let candidate = String(name.prefix(40 - suffix.count)) + suffix
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// Adds a row for the first Profile in `profiles` that has none yet; no row when all have one.
    public mutating func addOverride(from profiles: [String]) {
        let used = Set(overrides.map(\.profile))
        guard let profile = profiles.first(where: { !used.contains($0) }) else { return }
        overrides.append(Override(id: nextOverrideID, profile: profile))
        nextOverrideID += 1
    }

    public mutating func removeOverride(_ id: Int) {
        overrides.removeAll { $0.id == id }
    }

    /// Why the Team cannot be sent yet, in the words for the human; nil when it can.
    public var blocker: String? {
        if trimmed(name).isEmpty { return "Name the Team." }
        if let named = Dictionary(grouping: overrides, by: \.profile).first(where: { $0.value.count > 1 }) {
            return "\(named.key) is set twice. Keep one row for each Profile."
        }
        if !trimmed(rotateAt).isEmpty, rotateAtTokens == nil {
            return "Renew at is a number of tokens, like 150000."
        }
        return nil
    }

    private var rotateAtTokens: Int? {
        Int(trimmed(rotateAt)).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// The Team's fields as the file holds them: what is unset is left out, and so is a group
    /// with nothing in it.
    public var fields: [String: Any] {
        var out: [String: Any] = [:]
        if let text = present(description) { out["description"] = text }
        let orchestrator = setup(orchestratorCli, orchestratorModel, orchestratorEffort, rotateAt: rotateAtTokens)
        if !orchestrator.isEmpty { out["orchestrator"] = orchestrator }
        var workers = setup(workersCli, workersModel, workersEffort)
        if !overrides.isEmpty {
            workers["profiles"] = Dictionary(
                overrides.map { ($0.profile, setup($0.cli, $0.model, $0.effort)) },
                uniquingKeysWith: { _, last in last })
        }
        if !workers.isEmpty { out["workers"] = workers }
        var rules: [String: Any] = [:]
        if let maxWorkers { rules["maxWorkers"] = maxWorkers }
        if let planApproval { rules["planApproval"] = planApproval }
        if let review { rules["review"] = review }
        if let mergeWithoutAsking { rules["mergeWithoutAsking"] = mergeWithoutAsking }
        if !rules.isEmpty { out["rules"] = rules }
        if let text = present(instructions) { out["instructions"] = text }
        return out
    }

    /// The `team.save` parameters. A repo-level Team needs the repo it belongs to.
    public func saveParams(repo: String?) -> [String: Any] {
        var params: [String: Any] = ["name": trimmed(name), "team": fields, "level": level]
        if level == Self.repoLevel, let repo { params["repo"] = repo }
        return params
    }

    /// What a model field expects for `cli`, as a hint in the empty field.
    public static func modelHint(cli: String) -> String {
        switch cli {
        case "kiro": "a Kiro id, like claude-sonnet-5.5"
        case "codex": "an OpenAI model, like openai/gpt-5.6-terra"
        default: "an Anthropic model, like anthropic/claude-sonnet-5-5"
        }
    }

    private func setup(_ cli: String, _ model: String, _ effort: String, rotateAt: Int? = nil) -> [String: Any] {
        var out: [String: Any] = [:]
        if let text = present(cli) { out["cli"] = text }
        if let text = present(model) { out["model"] = text }
        if let text = present(effort) { out["effort"] = text }
        if let rotateAt { out["rotateAt"] = rotateAt }
        return out
    }

    private func present(_ text: String) -> String? {
        let text = trimmed(text)
        return text.isEmpty ? nil : text
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

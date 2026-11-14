import Foundation

/// The Teams page's editor, as plain values: a Team loaded into fields, and the fields turned
/// back into the `team.save` request. The name and the shape of the tree of Members are checked
/// here, the same way the daemon checks them (features/0084); the daemon validates everything
/// else and its message is shown as it is (features/0081).
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
    /// The Team's Members in tree order. The form keeps every field a Member came with, so a Team
    /// saved without edits sends them all back; `team.save` replaces the file with what it gets.
    public var members: [Team.Member] = []
    private var nextOverrideID = 0

    public init() {}

    /// Equal when every field the human can edit is equal; the counter that numbers new rows is
    /// not one of them, so a form edited and edited back is not changed.
    public static func == (a: TeamForm, b: TeamForm) -> Bool {
        a.name == b.name && a.isNew == b.isNew && a.level == b.level && a.description == b.description
            && a.orchestratorCli == b.orchestratorCli && a.orchestratorModel == b.orchestratorModel
            && a.orchestratorEffort == b.orchestratorEffort && a.rotateAt == b.rotateAt
            && a.workersCli == b.workersCli && a.workersModel == b.workersModel
            && a.workersEffort == b.workersEffort && a.overrides == b.overrides
            && a.maxWorkers == b.maxWorkers && a.planApproval == b.planApproval && a.review == b.review
            && a.mergeWithoutAsking == b.mergeWithoutAsking && a.instructions == b.instructions
            && a.members == b.members
    }

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
        members = team.members
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
        return membersBlocker
    }

    /// The most Members a Team holds, and the deepest its tree goes (level 1 is depth 1).
    public static let maxMembers = 24
    public static let maxDepth = 3

    /// The daemon's checks of the tree, in its order: the count, then each id, then each Action
    /// and Profile, then each parent, verifier and depth. Each message names the Member.
    private var membersBlocker: String? {
        if members.count > Self.maxMembers {
            return "A Team holds at most \(Self.maxMembers) Members; this one has \(members.count)."
        }
        for (at, member) in members.enumerated() {
            if !Self.validID(member.id) {
                return "Member \(at + 1) has the id \"\(member.id)\". An id is 1 to 32 lowercase letters, digits and -, "
                    + "not starting with -, like build-2."
            }
            if members[..<at].contains(where: { $0.id == member.id }) {
                return "\(member.id): another Member has this id. Give each Member its own."
            }
        }
        for member in members {
            if !Action.isAction(member.action) {
                return "\(member.id): \"\(member.action)\" is not an Action. Use "
                    + (Action.shippedIDs + [Action.custom]).joined(separator: ", ") + "."
            }
            if trimmed(member.profile).isEmpty {
                return "\(member.id): name the Profile it starts from."
            }
        }
        for member in members {
            let parent = member.parent.flatMap { id in members.first { $0.id == id } }
            if let id = member.parent, parent == nil {
                return "\(member.id): its parent \"\(id)\" is not a Member of this Team."
            }
            if member.action == "verify", parent?.action != "execute" {
                return "\(member.id): a verify Member sits under an execute Member."
            }
            var depth = 1
            var above = parent
            while let up = above {
                if up.id == member.id || depth > members.count {
                    return "\(member.id): its parents lead back to itself."
                }
                depth += 1
                above = up.parent.flatMap { id in members.first { $0.id == id } }
            }
            if depth > Self.maxDepth {
                return "\(member.id): the tree is \(depth) deep here; at most \(Self.maxDepth)."
            }
        }
        return nil
    }

    /// Why `members` cannot be a Team's tree, in the words of `blocker`; nil when they can.
    public static func problem(with members: [Team.Member]) -> String? {
        var form = TeamForm()
        form.name = "team"
        form.members = members
        return form.blocker
    }

    /// 1 to 32 lowercase letters, digits and `-`, not starting with `-`, as for a Profile's name.
    public static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 32 && !id.hasPrefix("-")
            && id.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
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
        if !members.isEmpty { out["members"] = members.map(memberFields) }
        return out
    }

    /// One Member as the file holds it: `id`, `action` and `profile` always, the rest only when set.
    private func memberFields(_ member: Team.Member) -> [String: Any] {
        var out: [String: Any] = ["id": member.id, "action": member.action, "profile": member.profile]
        if let text = member.parent, !text.isEmpty { out["parent"] = text }
        if let text = member.instructions, !trimmed(text).isEmpty { out["instructions"] = text }
        if let flag = member.replaceRole { out["replaceRole"] = flag }
        if let text = member.cli.flatMap(present) { out["cli"] = text }
        if let text = member.model.flatMap(present) { out["model"] = text }
        if let text = member.effort.flatMap(present) { out["effort"] = text }
        if !member.tools.isEmpty { out["tools"] = member.tools }
        if !member.skills.isEmpty { out["skills"] = member.skills }
        if !member.context.isEmpty { out["context"] = member.context }
        if let flag = member.lessons { out["lessons"] = flag }
        if let flag = member.writes { out["writes"] = flag }
        if let text = member.worktree, !text.isEmpty { out["worktree"] = text }
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

import Foundation

/// The Teams page's editor, as plain values: a Team loaded into fields, and the fields turned
/// back into the `team.save` request. The name and the Members with their Hand-offs are checked
/// here, the same way the daemon checks them (features/0084, 0092); the daemon validates everything
/// else and its message is shown as it is (features/0081).
public struct TeamForm: Equatable, Sendable {
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
    /// nil leaves a rule to the human's Orchestrator settings.
    public var maxWorkers: Int?
    public var planApproval: Bool?
    public var review: Bool?
    public var mergeWithoutAsking: Bool?
    /// nil sends a writer back once after a failed verification (features/0104).
    public var verifyRetries: Int?
    public var instructions = ""
    /// The Team's Members in file order. The form keeps every field a Member came with, so a Team
    /// saved without edits sends them all back; `team.save` replaces the file with what it gets.
    public var members: [Team.Member] = []

    public init() {}

    /// A saved Team in the fields.
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
        maxWorkers = team.rules?.maxWorkers
        planApproval = team.rules?.planApproval
        review = team.rules?.review
        mergeWithoutAsking = team.rules?.mergeWithoutAsking
        verifyRetries = team.rules?.verifyRetries
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

    /// Why the Team cannot be sent yet, in the words for the human; nil when it can.
    public var blocker: String? {
        if trimmed(name).isEmpty { return "Name the Team." }
        if !trimmed(rotateAt).isEmpty, rotateAtTokens == nil {
            return "Renew at is a number of tokens, like 150000."
        }
        return membersBlocker
    }

    /// The most Members a Team holds.
    public static let maxMembers = 24

    /// The daemon's checks of the Members, in its order: the count, then each id, then each Action
    /// and Profile, then each Member's Hand-offs, then loops. Each message names the Member.
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
            if member.id == Team.orchestratorID {
                return "\(member.id) is the Orchestrator's own id. Give the Member another."
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
            let handOffs = member.handOffs
            if handOffs.isEmpty {
                return "\(member.id): no Hand-off comes into it, so the Orchestrator cannot reach it."
            }
            for (at, handOff) in handOffs.enumerated() {
                if handOffs[..<at].contains(where: { $0.from == handOff.from }) {
                    return "\(member.id): two Hand-offs come from \(handOff.from)."
                }
                let source = handOff.from == Team.orchestratorID ? nil : members.first { $0.id == handOff.from }
                if handOff.from != Team.orchestratorID, source == nil {
                    return "\(member.id): it comes after \"\(handOff.from)\", which is not a Member of this Team."
                }
                if member.action == "verify", source?.action != "execute" {
                    return "\(member.id): a verify Member comes only after execute Members."
                }
                if handOff.auto, source == nil {
                    return "\(member.id): a Hand-off from the Orchestrator cannot be automatic."
                }
                if handOff.auto, member.action == "verify" {
                    return "\(member.id): a Hand-off into a verify Member runs through --verify and cannot be automatic."
                }
            }
            if handOffs.filter(\.auto).count > 1 {
                return "\(member.id): at most one automatic Hand-off comes into a Member."
            }
        }
        for member in members where Self.loops(from: member.id, in: members, path: []) {
            return "\(member.id): its Hand-offs lead back to itself."
        }
        return nil
    }

    /// Whether walking back from `id` along the Hand-offs into it ever comes to a Member on `path`.
    private static func loops(from id: String, in members: [Team.Member], path: [String]) -> Bool {
        if path.contains(id) { return true }
        guard let member = members.first(where: { $0.id == id }) else { return false }
        return (member.after ?? []).contains { loops(from: $0.from, in: members, path: path + [id]) }
    }

    /// Why `members` cannot be a Team's Members, in the words of `blocker`; nil when they can.
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
        let workers = setup(workersCli, workersModel, workersEffort)
        if !workers.isEmpty { out["workers"] = workers }
        var rules: [String: Any] = [:]
        if let maxWorkers { rules["maxWorkers"] = maxWorkers }
        if let planApproval { rules["planApproval"] = planApproval }
        if let review { rules["review"] = review }
        if let mergeWithoutAsking { rules["mergeWithoutAsking"] = mergeWithoutAsking }
        if let verifyRetries { rules["verifyRetries"] = verifyRetries }
        if !rules.isEmpty { out["rules"] = rules }
        if let text = present(instructions) { out["instructions"] = text }
        if !members.isEmpty { out["members"] = members.map(memberFields) }
        return out
    }

    /// One Member as the file holds it: `id`, `action` and `profile` always, the rest only when set
    /// (features/0094).
    private func memberFields(_ member: Team.Member) -> [String: Any] {
        var out: [String: Any] = ["id": member.id, "action": member.action, "profile": member.profile]
        if let after = member.after {
            out["after"] = after.map { handOff -> [String: Any] in
                handOff.auto ? ["from": handOff.from, "auto": true] : ["from": handOff.from]
            }
        }
        if let x = member.x { out["x"] = x }
        if let y = member.y { out["y"] = y }
        if let text = member.cli.flatMap(present) { out["cli"] = text }
        if let text = member.model.flatMap(present) { out["model"] = text }
        if let text = member.effort.flatMap(present) { out["effort"] = text }
        return out
    }

    /// The `team.save` parameters. A repo-level Team needs the repo it belongs to.
    public func saveParams(repo: String?) -> [String: Any] {
        var params: [String: Any] = ["name": trimmed(name), "team": fields, "level": level]
        if level == Self.repoLevel, let repo { params["repo"] = repo }
        return params
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

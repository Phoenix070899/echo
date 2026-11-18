import Foundation

/// What the Teams page reads off a Team at a glance (ui-ux/0121): how many edits are not saved, the
/// short names of the models its Members run on, and the two letters on a Member's node.
extension TeamForm {
    /// How many things differ from `saved`: each field of the Team's own, and each Member added,
    /// removed or changed; Members only put in another order count once. A Member that only gained
    /// the place Echo had laid it out at is not changed (`placedMembers`).
    public func changeCount(from saved: TeamForm) -> Int {
        let a = self, b = saved
        let fields: [Bool] = [
            a.name != b.name, a.level != b.level, a.description != b.description,
            a.orchestratorCli != b.orchestratorCli, a.orchestratorModel != b.orchestratorModel,
            a.orchestratorEffort != b.orchestratorEffort, a.rotateAt != b.rotateAt,
            a.workersCli != b.workersCli, a.workersModel != b.workersModel,
            a.workersEffort != b.workersEffort,
            a.maxWorkers != b.maxWorkers, a.planApproval != b.planApproval, a.review != b.review,
            a.mergeWithoutAsking != b.mergeWithoutAsking, a.verifyRetries != b.verifyRetries,
            a.instructions != b.instructions,
        ]
        var count = fields.filter { $0 }.count
        var ids = b.members.map(\.id)
        for member in a.members where !ids.contains(member.id) { ids.append(member.id) }
        let changedMembers = ids.filter { a.memberChanged($0, from: b) }.count
        count += changedMembers
        if changedMembers == 0, a.members.map(\.id) != b.members.map(\.id) { count += 1 }
        return count
    }

    /// Whether the Member `id` is new or differs from `saved`'s, its laid-out place aside.
    public func memberChanged(_ id: String, from saved: TeamForm) -> Bool {
        guard var now = member(id), let before = saved.member(id) else { return member(id) != saved.member(id) }
        // A saved Member without a place counts as at the place Echo laid it out at, which the
        // first edit on the canvas writes into every Member.
        if before.x == nil || before.y == nil, now.x != nil,
           let laid = TeamGraph.positions(saved.members)[id], now.x == laid.x, now.y == laid.y {
            now.x = nil
            now.y = nil
        }
        return now != before
    }
}

/// The models of a Team, by family, for the bar in its header.
public enum ModelMix {
    /// A model's family in a word: "anthropic/claude-sonnet-5-5" is "sonnet", "claude-haiku-5.5"
    /// "haiku", "openai/gpt-5.6-terra" "gpt"; nothing named is "default", the CLI's own.
    public static func family(_ model: String) -> String {
        var name = model.trimmingCharacters(in: .whitespaces).lowercased()
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if name.hasPrefix("claude-") { name = String(name.dropFirst("claude-".count)) }
        let word = name.split(separator: "-").first.map(String.init) ?? ""
        return word.isEmpty ? "default" : word
    }

    /// Each family and how many of `models` are in it, the most first, ties in the order met.
    public static func tally(_ models: [String]) -> [(family: String, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for model in models {
            let family = family(model)
            if counts[family] == nil { order.append(family) }
            counts[family, default: 0] += 1
        }
        return order.enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .map { ($0.element, counts[$0.element]!) }
    }
}

extension ActionLook {
    /// The two capitals on a node: the first letters of a two-word title ("Write code" is "WC"),
    /// else the first two letters of the one word ("Research" is "RE").
    public static func initials(_ title: String) -> String {
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String((words.first ?? "").prefix(2)).uppercased()
    }
}

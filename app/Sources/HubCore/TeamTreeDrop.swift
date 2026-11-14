import Foundation

/// Dragging in the Team's tree (ui-ux/0102) as pure functions: what a dragged string means, which
/// drop zone the pointer is in, and what the drop does to the draft's Members. The view only draws
/// the rows and the palette, and hands each string and pointer position here.

// MARK: Payloads

/// What is being dragged: a Member row, or a chip of the palette.
public enum DropPayload: Equatable, Sendable {
    /// A Member of the tree, by id.
    case member(String)
    /// A chip: a new Member of `action`, on `profile` or, when nil, the Action's default Profile.
    /// A `custom` chip has no Profile yet; the human names one when it is dropped.
    case chip(action: String, profile: String?)

    /// The string a drag carries: `member:<id>` or `chip:<action>:<profile>`.
    public var text: String {
        switch self {
        case .member(let id): "member:\(id)"
        case .chip(let action, let profile): "chip:\(action):\(profile ?? "")"
        }
    }

    /// The payload a string means; nil for anything else, such as a file's name, an id that is not
    /// one, a word that is no Action, or a Profile name that is not one.
    public static func parse(_ text: String) -> DropPayload? {
        let parts = text.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "member":
            guard parts.count == 2, TeamForm.validID(parts[1]) else { return nil }
            return .member(parts[1])
        case "chip":
            guard parts.count == 3, Action.isAction(parts[1]) else { return nil }
            if parts[2].isEmpty { return .chip(action: parts[1], profile: nil) }
            guard TeamForm.validID(parts[2]) else { return nil }
            return .chip(action: parts[1], profile: parts[2])
        default:
            return nil
        }
    }
}

/// One chip of the palette.
public struct PaletteChip: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable { case action, worker, custom }

    public let kind: Kind
    /// The text on the chip.
    public let title: String
    public let payload: DropPayload

    public var id: String { payload.text + (kind == .worker ? ":worker" : "") }

    /// The Action it adds.
    public var action: String {
        if case .chip(let action, _) = payload { return action }
        return Action.custom
    }
}

public enum Palette {
    /// The shipped Workers, in the order the palette lists them.
    public static let workers = ["naruto", "sasuke", "hinata", "jiraiya", "lee", "ino"]

    /// The six Actions, then the six shipped Workers (each added for the Action it is the default
    /// Profile of), then Custom.
    public static func chips(actions: [Action] = Action.shipped) -> [PaletteChip] {
        let byAction = actions.map {
            PaletteChip(kind: .action, title: $0.title, payload: .chip(action: $0.id, profile: $0.profile))
        }
        let byWorker = workers.compactMap { name in
            actions.first { $0.profile == name }.map {
                PaletteChip(kind: .worker, title: name, payload: .chip(action: $0.id, profile: name))
            }
        }
        return byAction + byWorker
            + [PaletteChip(kind: .custom, title: "Custom", payload: .chip(action: Action.custom, profile: nil))]
    }
}

// MARK: Where it lands

/// Where the pointer is over the tree.
public enum DropSpot: Equatable, Sendable {
    /// On a row, in its top quarter (before), middle (child) or bottom quarter (after).
    case onto(String, TeamTree.Position)
    /// At the left edge of a row: level 1.
    case leftEdge(String)
    /// Over the Orchestrator or empty space: level 1, last.
    case empty

    /// How far in from a row's left side the left edge reaches.
    public static let leftEdgeWidth = 14.0

    /// The spot for a pointer at (`x`, `y`) in the row of `row`, which is `height` tall.
    public static func at(row: String, x: Double, y: Double, height: Double) -> DropSpot {
        if x < leftEdgeWidth { return .leftEdge(row) }
        guard height > 0 else { return .onto(row, .child) }
        if y < height * 0.25 { return .onto(row, .before) }
        if y > height * 0.75 { return .onto(row, .after) }
        return .onto(row, .child)
    }
}

/// Where a drop would land, for the line or the filled row that shows it.
public enum DropMark: Equatable, Sendable {
    /// The row of a Member that would get a child.
    case fill(String)
    /// The Orchestrator, which holds level 1.
    case root
    /// A line above or below a row, indented to `depth`.
    case line(row: String, below: Bool, depth: Int)
}

/// Where a chip's new Member goes among the Members of its parent, once it has been added.
public struct DropPlacement: Equatable, Sendable {
    public let target: String
    public let position: TeamTree.Position
}

/// What a drop would do, or why it cannot be done.
public struct DropOutcome: Equatable, Sendable {
    /// The draft afterwards; the draft as it was when the drop is refused or still waits for a name.
    public var members: [Team.Member]
    /// The Member to select afterwards: the one moved, or the one added.
    public var selected: String?
    /// The one plain line to show when the drop is refused; nothing changes then.
    public var refusal: String?
    public var mark: DropMark?
    /// For a chip: the parent of the new Member, nil for level 1.
    public var parent: String?
    /// For a chip: where it goes among its siblings, when not last.
    public var placement: DropPlacement?
    /// A `custom` chip with no Profile yet: it is allowed so far, and the view asks for the Profile's
    /// name and adds the Member under `parent` at `placement`.
    public var asksForProfile = false

    public var isOK: Bool { refusal == nil }
}

public enum TeamTreeDrop {
    /// What dropping `payload` at `spot` does to `members`. `customProfile` is the Profile a `custom`
    /// chip has been given; without one the drop is judged and the outcome asks for a name.
    public static func evaluate(_ payload: DropPayload, at spot: DropSpot, in members: [Team.Member],
                                customProfile: String? = nil, actions: [Action] = Action.shipped) -> DropOutcome {
        switch payload {
        case .member(let id):
            return move(id, at: spot, in: members)
        case .chip(let action, let profile):
            return add(action: action, profile: profile ?? customProfile, at: spot, in: members, actions: actions)
        }
    }

    /// The level 1 Member that `id` is, or sits under; nil for an id no Member has.
    public static func levelOneAncestor(of id: String, in members: [Team.Member]) -> String? {
        let byID = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard var at = byID[id] else { return nil }
        var steps = 0
        while let parent = at.parent, let next = byID[parent], steps <= members.count {
            at = next
            steps += 1
        }
        return at.parent == nil ? at.id : nil
    }

    /// The Members `id` can be moved under: each Member that `canDrop` allows it as a child of, in
    /// tree order, and nil (level 1) when it is not at level 1 already. Offered as a menu, so the
    /// move does not need a drag.
    public static func moveDestinations(of id: String, in members: [Team.Member]) -> [String?] {
        guard let member = members.first(where: { $0.id == id }) else { return [] }
        var out: [String?] = []
        if member.parent != nil, evaluate(.member(id), at: .empty, in: members).isOK { out.append(nil) }
        for other in members where other.id != id && other.id != member.parent {
            if TeamTree.canDrop(id, onto: other.id, as: .child, in: members).isOK { out.append(other.id) }
        }
        return out
    }

    /// The drop of `parent` as the Member's new parent: nil for level 1.
    public static func move(_ id: String, under parent: String?, in members: [Team.Member]) -> DropOutcome {
        evaluate(.member(id), at: parent.map { .onto($0, .child) } ?? .empty, in: members)
    }

    // MARK: Internals

    private static func move(_ id: String, at spot: DropSpot, in members: [Team.Member]) -> DropOutcome {
        var outcome = DropOutcome(members: members)
        guard let dragged = members.first(where: { $0.id == id }) else {
            outcome.refusal = "That Member is not in the tree."
            return outcome
        }
        let target: String
        let position: TeamTree.Position
        switch spot {
        case .onto(let row, let at):
            (target, position) = (row, at)
        case .leftEdge:
            guard dragged.parent != nil, let top = levelOneAncestor(of: id, in: members) else {
                outcome.refusal = "\(id) is already at level 1."
                return outcome
            }
            (target, position) = (top, .after)
        case .empty:
            guard let last = members.last(where: { $0.parent == nil }) else {
                outcome.refusal = "That Member is not in the tree."
                return outcome
            }
            (target, position) = (last.id, .after)
        }
        outcome.mark = mark(of: target, position, in: members, endOfLevelOne: spot == .empty, leftEdge: spot.isLeftEdge)
        if let reason = TeamTree.canDrop(id, onto: target, as: position, in: members).reason {
            outcome.refusal = reason
            return outcome
        }
        guard let moved = TeamTree.drop(id, onto: target, as: position, in: members) else {
            outcome.refusal = TeamTreeEditing.unusable
            return outcome
        }
        outcome.members = moved
        outcome.selected = id
        return outcome
    }

    private static func add(action: String, profile: String?, at spot: DropSpot, in members: [Team.Member],
                            actions: [Action]) -> DropOutcome {
        var outcome = DropOutcome(members: members)
        let target: String
        let position: TeamTree.Position
        switch spot {
        case .onto(let row, let at):
            (target, position) = (row, at)
            guard let onto = members.first(where: { $0.id == row }) else {
                outcome.refusal = "That Member is not in the tree."
                return outcome
            }
            outcome.parent = at == .child ? row : onto.parent
            outcome.placement = at == .child ? nil : DropPlacement(target: row, position: at)
        case .leftEdge(let row):
            guard let top = levelOneAncestor(of: row, in: members) else {
                outcome.refusal = "That Member is not in the tree."
                return outcome
            }
            (target, position) = (top, .after)
            outcome.placement = DropPlacement(target: top, position: .after)
        case .empty:
            outcome.mark = members.last(where: { $0.parent == nil })
                .map { mark(of: $0.id, .after, in: members, endOfLevelOne: true, leftEdge: false) } ?? .root
            return finish(outcome, action: action, profile: profile, in: members, actions: actions)
        }
        outcome.mark = mark(of: target, position, in: members, endOfLevelOne: false, leftEdge: spot.isLeftEdge)
        return finish(outcome, action: action, profile: profile, in: members, actions: actions)
    }

    /// Checks the Action can be added under the outcome's parent, then adds it and puts it in place.
    private static func finish(_ start: DropOutcome, action: String, profile: String?,
                               in members: [Team.Member], actions: [Action]) -> DropOutcome {
        var outcome = start
        let parent = outcome.parent.flatMap { id in members.first { $0.id == id } }
        if let reason = TeamTreeEditing.addRefusal(action, under: parent, in: members, hasProfile: true, actions: actions) {
            outcome.refusal = reason
            return outcome
        }
        if action == Action.custom, (profile ?? "").isEmpty {
            outcome.asksForProfile = true
            return outcome
        }
        guard let added = TeamTree.add(action: action, profile: profile, under: outcome.parent, to: members, actions: actions) else {
            outcome.refusal = TeamTreeEditing.unusable
            return outcome
        }
        outcome.members = added.members
        if let place = outcome.placement {
            // Already last among its siblings reads as a refusal of the move; the Member is still added.
            outcome.members = TeamTree.drop(added.id, onto: place.target, as: place.position, in: added.members) ?? added.members
        }
        outcome.selected = added.id
        return outcome
    }

    /// The line or filled row for a drop at `position` of `target`; `endOfLevelOne` and `leftEdge`
    /// draw the line at level 1, below the whole subtree of `target`.
    private static func mark(of target: String, _ position: TeamTree.Position, in members: [Team.Member],
                             endOfLevelOne: Bool, leftEdge: Bool) -> DropMark {
        let depths = Dictionary(TeamTree.rows(members).map { ($0.member.id, $0.depth) }, uniquingKeysWith: { first, _ in first })
        if endOfLevelOne { return .line(row: lastRow(under: target, in: members), below: true, depth: 1) }
        switch position {
        case .child where !leftEdge:
            return .fill(target)
        case .before where !leftEdge:
            return .line(row: target, below: false, depth: depths[target] ?? 1)
        default:
            return .line(row: lastRow(under: target, in: members), below: true, depth: leftEdge ? 1 : depths[target] ?? 1)
        }
    }

    /// The last row of the subtree of `id`, where a line "after" it is drawn.
    private static func lastRow(under id: String, in members: [Team.Member]) -> String {
        TeamTree.descendants(of: id, in: members).last?.id ?? id
    }
}

extension DropSpot {
    fileprivate var isLeftEdge: Bool {
        if case .leftEdge = self { return true }
        return false
    }
}

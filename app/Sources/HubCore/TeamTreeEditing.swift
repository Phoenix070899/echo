import Foundation

/// The tree's keyboard and buttons as pure functions (ui-ux/0102): which key does which operation,
/// what each operation does to the draft's Members and to the selection, and why one is refused.
/// The tree view only draws the rows and hands each key or button here.

// MARK: Keys

/// The modifier keys that matter to the tree; Caps Lock, the numeric pad and the function flag that
/// arrow keys carry are not among them.
public struct TreeModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let option = TreeModifiers(rawValue: 1)
    public static let command = TreeModifiers(rawValue: 2)
    public static let control = TreeModifiers(rawValue: 4)
    public static let shift = TreeModifiers(rawValue: 8)
}

/// A key the tree may act on.
public enum TreeKey: Equatable, Sendable {
    case up, down, left, right
    /// Return.
    case enter
    /// Delete, and the forward delete key.
    case delete
    /// A letter or digit, as typed.
    case character(String)
}

/// What the tree can be asked to do, by key or by button.
public enum TreeCommand: Equatable, Sendable {
    /// Select the row above (-1) or below (+1); the Orchestrator is above the first Member.
    case select(Int)
    /// Move the Member one place up (-1) or down (+1) among its siblings.
    case move(Int)
    case indent, outdent
    /// Open the selected Member's name field.
    case rename
    case remove
    /// Add a Member of the Action under the selected Member, or at level 1 under the Orchestrator.
    case add(String)
    case duplicate
    /// Hand the keyboard back to the list of sections.
    case leave

    /// Whether it changes the draft; the rest only move the selection or the focus, so they work in
    /// a Team that cannot be edited.
    public var edits: Bool {
        switch self {
        case .select, .leave: false
        default: true
        }
    }
}

public enum TreeKeys {
    /// The Action the `a` key adds: the one most Teams grow by.
    public static let addedByKey = "execute"

    /// What a key does with the tree focused and no text field being edited (ui-ux/0102); nil for a
    /// key the tree leaves alone, so Esc, Tab and the Command keys reach the window as before.
    /// ⌘N and ⌘D are menu bindings and map to nothing here.
    public static func command(for key: TreeKey, modifiers: TreeModifiers) -> TreeCommand? {
        switch modifiers {
        case []:
            switch key {
            case .up: return .select(-1)
            case .down: return .select(1)
            case .left: return .leave
            case .enter: return .rename
            case .delete: return .remove
            case .character("a"): return .add(addedByKey)
            case .character("d"): return .duplicate
            default: return nil
            }
        case .option:
            switch key {
            case .up: return .move(-1)
            case .down: return .move(1)
            case .right: return .indent
            case .left: return .outdent
            default: return nil
            }
        default:
            return nil
        }
    }
}

// MARK: Looks

public enum ActionLook {
    /// The SF Symbol of an Action's rows and menu items.
    public static func symbol(for action: String) -> String {
        switch action {
        case "scan": "magnifyingglass"
        case "research": "globe"
        case "execute": "hammer"
        case "verify": "checkmark.seal"
        case "run": "terminal"
        case "scribe": "square.and.pencil"
        default: "slider.horizontal.3"
        }
    }

    /// The Action's name as the tree shows it: "Write code", or "Custom".
    public static func title(for action: String, actions: [Action] = Action.shipped) -> String {
        actions.first { $0.id == action }?.title ?? "Custom"
    }

    /// The grey line under a row: the Profile, then the model it runs on when one is known.
    public static func meta(profile: String, model: String) -> String {
        model.isEmpty ? profile : "\(profile), \(model)"
    }
}

// MARK: Operations

/// The draft after a command, and what the view does next.
public struct TreeEdit: Equatable, Sendable {
    public var members: [Team.Member]
    /// The Member selected afterwards; nil is the Orchestrator at the root.
    public var selected: String?
    /// The one plain line under the tree when the command was refused; nothing changed then.
    public var notice: String?
    /// How many Members a removal takes, the selected one and everything under it, when it has
    /// children and must be confirmed first; the draft is untouched until `apply` is called again
    /// with `confirmed`.
    public var asksToRemove: Int?
}

public enum TeamTreeEditing {
    static let unusable = "That would leave the Team with a tree it cannot use."

    /// `command` applied to the draft's `members` with `selected` picked (nil is the Orchestrator).
    /// A refused command returns the draft as it was with the reason in `notice`. `.rename` and
    /// `.leave` are the view's to carry out and change nothing here.
    public static func apply(_ command: TreeCommand, to members: [Team.Member], selected: String?,
                             confirmed: Bool = false, actions: [Action] = Action.shipped) -> TreeEdit {
        let keep = TreeEdit(members: members, selected: selected)
        func refuse(_ text: String) -> TreeEdit {
            var edit = keep
            edit.notice = text
            return edit
        }
        let member = selected.flatMap { id in members.first { $0.id == id } }
        let siblings = members.filter { $0.parent == member?.parent }.map(\.id)
        let place = member.flatMap { found in siblings.firstIndex(of: found.id) }

        switch command {
        case .select(let step):
            return TreeEdit(members: members, selected: select(step, from: member?.id, in: members))
        case .rename, .leave:
            return keep
        case .add(let action):
            if let reason = addRefusal(action, under: member, in: members, actions: actions) { return refuse(reason) }
            guard let added = TeamTree.add(action: action, under: member?.id, to: members, actions: actions) else {
                return refuse(unusable)
            }
            return TreeEdit(members: added.members, selected: added.id)
        default:
            break
        }
        guard let member, let place else {
            return refuse(selected == nil ? "The Orchestrator is the root of the tree. Pick a Member first." : "That Member is not in the tree.")
        }

        switch command {
        case .duplicate:
            let copies = 1 + TeamTree.descendants(of: member.id, in: members).count
            if members.count + copies > TeamForm.maxMembers {
                return refuse("Copying \(member.id) takes \(copies) more and a Team holds at most \(TeamForm.maxMembers) Members.")
            }
            guard let copy = TeamTree.duplicate(member.id, in: members) else { return refuse(unusable) }
            return TreeEdit(members: copy.members, selected: copy.id)
        case .remove:
            let below = TeamTree.descendants(of: member.id, in: members).count
            if below > 0, !confirmed {
                var edit = keep
                edit.asksToRemove = below + 1
                return edit
            }
            guard let gone = TeamTree.remove(member.id, from: members) else { return refuse(unusable) }
            let next = place + 1 < siblings.count ? siblings[place + 1] : (place > 0 ? siblings[place - 1] : member.parent)
            return TreeEdit(members: gone.members, selected: next)
        case .move(let step):
            let target = place + step
            if !siblings.indices.contains(target) {
                return refuse("\(member.id) is already \(step < 0 ? "first" : "last") among its siblings.")
            }
            guard let moved = TeamTree.move(member.id, by: step, in: members) else { return refuse(unusable) }
            return TreeEdit(members: moved, selected: member.id)
        case .indent:
            if place == 0 { return refuse("\(member.id) has no Member above it at its level to go under.") }
            if let reason = TeamTree.canDrop(member.id, onto: siblings[place - 1], as: .child, in: members).reason {
                return refuse(reason)
            }
            guard let moved = TeamTree.indent(member.id, in: members) else { return refuse(unusable) }
            return TreeEdit(members: moved, selected: member.id)
        case .outdent:
            guard let parent = member.parent else { return refuse("\(member.id) is already at level 1.") }
            if let reason = TeamTree.canDrop(member.id, onto: parent, as: .after, in: members).reason {
                return refuse(reason)
            }
            guard let moved = TeamTree.outdent(member.id, in: members) else { return refuse(unusable) }
            return TreeEdit(members: moved, selected: member.id)
        default:
            return keep
        }
    }

    /// The row `step` rows from `id` in the order shown; the Orchestrator is one above the first
    /// Member, and the selection stops at both ends.
    public static func select(_ step: Int, from id: String?, in members: [Team.Member]) -> String? {
        let rows = TeamTree.rows(members)
        let at = id.flatMap { id in rows.firstIndex { $0.member.id == id } } ?? -1
        let to = min(max(at + step, -1), rows.count - 1)
        return to < 0 ? nil : rows[to].member.id
    }

    /// Why a Member of `action` cannot be added under `parent` (the Orchestrator when nil); nil when
    /// it can. A `custom` Member needs a Profile of its own, which `hasProfile` says is at hand.
    public static func addRefusal(_ action: String, under parent: Team.Member?, in members: [Team.Member],
                                  hasProfile: Bool = false, actions: [Action] = Action.shipped) -> String? {
        guard Action.isAction(action) else { return "\"\(action)\" is not an Action." }
        if action == Action.custom, !hasProfile {
            return "A custom Member needs a Profile of its own. Use Add Member, Custom."
        }
        if members.count >= TeamForm.maxMembers {
            return "A Team holds at most \(TeamForm.maxMembers) Members."
        }
        if let parent {
            let depth = TeamTree.rows(members).first { $0.member.id == parent.id }?.depth ?? 1
            if depth >= TeamForm.maxDepth {
                return "\(parent.id) is at level \(depth), the deepest the tree goes, so nothing can go under it."
            }
        }
        if actions.first(where: { $0.id == action })?.under == "execute", parent?.action != "execute" {
            return "A \(action) Member needs an execute Member above it."
        }
        return nil
    }
}

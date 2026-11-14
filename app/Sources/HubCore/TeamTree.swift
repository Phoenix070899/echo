import Foundation

/// The operations of a Team's tree of Members (features/0084, ui-ux/0102), as pure functions on the
/// flat array a Team file holds. The array is in tree order: a Member's descendants follow it
/// contiguously and siblings keep their order. Every operation hands back a tree in that order that
/// passes the rules `TeamForm.blocker` checks, or nil and nothing changes.
public enum TeamTree {
    /// The longest a Member's id may be.
    public static let maxIDLength = 32

    /// One row of the tree as it is shown: a Member and how deep it sits (level 1 is depth 1).
    public struct Row: Equatable, Sendable {
        public let member: Team.Member
        public let depth: Int
    }

    /// Where a dropped Member lands relative to the Member it is dropped on.
    public enum Position: Equatable, Sendable {
        /// The last child of the target.
        case child
        /// Among the target's siblings, just above it.
        case before
        /// Among the target's siblings, just below its subtree.
        case after
    }

    /// Whether a drop is allowed; a refusal carries the one plain line the human is shown.
    public enum DropVerdict: Equatable, Sendable {
        case ok
        case refused(String)

        public var isOK: Bool { self == .ok }

        public var reason: String? {
            if case .refused(let text) = self { return text }
            return nil
        }
    }

    /// A tree after a Member was added or duplicated, and the id the new Member (or the copy of the
    /// top Member) has, so the UI can select it.
    public struct Insertion: Equatable, Sendable {
        public let members: [Team.Member]
        public let id: String
    }

    /// A tree after a Member was removed, with the Members that went with it (the Member first,
    /// then its descendants in tree order).
    public struct Removal: Equatable, Sendable {
        public let members: [Team.Member]
        public let removed: [Team.Member]
    }

    // MARK: Reading

    /// The Members with their depths, in the order they are listed.
    public static func rows(_ members: [Team.Member]) -> [Row] {
        var depths: [String: Int] = [:]
        return members.map { member in
            let depth = member.parent.flatMap { depths[$0] }.map { $0 + 1 } ?? 1
            depths[member.id] = depth
            return Row(member: member, depth: depth)
        }
    }

    /// Whether the tree passes every structural rule of `TeamForm.blocker`: ids, parents, cycles,
    /// depth, verifiers and size. It asks the form itself, so the two cannot disagree.
    public static func isValid(_ members: [Team.Member]) -> Bool {
        var form = TeamForm()
        form.name = "team"
        form.members = members
        return form.blocker == nil
    }

    /// The Members under `id`, at any depth, in tree order; empty for a Member with none or none by
    /// that id.
    public static func descendants(of id: String, in members: [Team.Member]) -> [Team.Member] {
        guard let forest = Forest(members) else { return [] }
        return forest.subtree(of: id).dropFirst().compactMap { forest.byID[$0] }
    }

    // MARK: Adding, removing, copying

    /// The tree with a new Member of `action` as the last child of `parent` (level 1 when nil). Its
    /// id comes from the Action and is made unique; its Profile is the Action's default, or the
    /// `profile` given (a `custom` Member has no default and needs one). It inherits nothing else.
    public static func add(action: String, profile: String? = nil, under parent: String? = nil,
                           to members: [Team.Member], actions: [Action] = Action.shipped) -> Insertion? {
        let chosen = profile ?? actions.first { $0.id == action }?.profile
        guard let chosen, !chosen.isEmpty, var forest = Forest(members) else { return nil }
        if let parent, forest.byID[parent] == nil { return nil }
        let id = uniqueID(from: action, taking: Set(forest.byID.keys))
        forest.insert(Team.Member(id: id, action: action, profile: chosen, parent: parent), under: parent, at: nil)
        return finish(forest).map { Insertion(members: $0, id: id) }
    }

    /// The tree without `id` and its descendants, and those Members, so the UI can ask first.
    public static func remove(_ id: String, from members: [Team.Member]) -> Removal? {
        guard var forest = Forest(members), forest.byID[id] != nil else { return nil }
        let gone = forest.subtree(of: id)
        let removed = gone.compactMap { forest.byID[$0] }
        forest.detach(id)
        for name in gone { forest.byID[name] = nil }
        return finish(forest).map { Removal(members: $0, removed: removed) }
    }

    /// The tree with a copy of `id` and its descendants right after the subtree of the original, in
    /// the same place under the same parent, every copy under a new unique id (`build`, `build-2`).
    public static func duplicate(_ id: String, in members: [Team.Member]) -> Insertion? {
        guard var forest = Forest(members), let original = forest.byID[id] else { return nil }
        var taken = Set(forest.byID.keys)
        var renamed: [String: String] = [:]
        let subtree = forest.subtree(of: id)
        for old in subtree {
            let new = uniqueID(from: old, taking: taken)
            taken.insert(new)
            renamed[old] = new
        }
        let after = forest.siblings(of: id).firstIndex(of: id).map { $0 + 1 }
        for old in subtree {
            guard var copy = forest.byID[old], let new = renamed[old] else { continue }
            copy.id = new
            copy.parent = old == id ? original.parent : copy.parent.flatMap { renamed[$0] }
            forest.insert(copy, under: copy.parent, at: old == id ? after : nil)
        }
        guard let top = renamed[id] else { return nil }
        return finish(forest).map { Insertion(members: $0, id: top) }
    }

    // MARK: Moving

    /// The tree with `id` one place up (-1) or down (+1) among its siblings; nil at the end.
    public static func move(_ id: String, by step: Int, in members: [Team.Member]) -> [Team.Member]? {
        guard abs(step) == 1, var forest = Forest(members), let member = forest.byID[id] else { return nil }
        let siblings = forest.siblings(of: id)
        guard let at = siblings.firstIndex(of: id), siblings.indices.contains(at + step) else { return nil }
        forest.detach(id)
        forest.insert(member, under: member.parent, at: at + step)
        return finish(forest)
    }

    /// The tree with `id` as the last child of the sibling above it; nil with no sibling above.
    public static func indent(_ id: String, in members: [Team.Member]) -> [Team.Member]? {
        guard var forest = Forest(members), let member = forest.byID[id] else { return nil }
        let siblings = forest.siblings(of: id)
        guard let at = siblings.firstIndex(of: id), at > 0 else { return nil }
        forest.detach(id)
        forest.insert(member, under: siblings[at - 1], at: nil)
        return finish(forest)
    }

    /// The tree with `id` right after its parent, among the parent's siblings; nil at level 1.
    public static func outdent(_ id: String, in members: [Team.Member]) -> [Team.Member]? {
        guard var forest = Forest(members), let member = forest.byID[id], let parentID = member.parent,
              let parent = forest.byID[parentID],
              let at = forest.siblings(of: parentID).firstIndex(of: parentID) else { return nil }
        forest.detach(id)
        forest.insert(member, under: parent.parent, at: at + 1)
        return finish(forest)
    }

    // MARK: Dropping

    /// Whether `id` can be dropped on `target` at `position`, and when not, why.
    public static func canDrop(_ id: String, onto target: String, as position: Position,
                               in members: [Team.Member]) -> DropVerdict {
        if case .refused(let reason) = plan(id, onto: target, as: position, in: members).verdict {
            return .refused(reason)
        }
        return .ok
    }

    /// The tree after the drop; nil, with nothing changed, when `canDrop` refuses it.
    public static func drop(_ id: String, onto target: String, as position: Position,
                            in members: [Team.Member]) -> [Team.Member]? {
        plan(id, onto: target, as: position, in: members).members
    }

    // MARK: Ids

    /// `base`, else `base-2`, `base-3` and so on, the first not in `taken`. A trailing number of
    /// `base` is counted on from, so a copy of `build-2` is `build-3`, and the result keeps within 32.
    public static func uniqueID(from base: String, taking taken: Set<String>) -> String {
        let name = Self.id(from: base)
        if !taken.contains(name) { return name }
        var stem = name
        var number = 2
        if let dash = name.lastIndex(of: "-"), let found = Int(name[name.index(after: dash)...]), found >= 2 {
            stem = String(name[..<dash])
            number = found + 1
        }
        while true {
            let suffix = "-\(number)"
            let candidate = String(stem.prefix(maxIDLength - suffix.count)) + suffix
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// `text` cut to a valid id: lowercase letters, digits and `-`, within 32, not starting with `-`.
    private static func id(from text: String) -> String {
        let kept = text.lowercased().unicodeScalars.filter {
            ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57) || $0 == "-"
        }
        let cleaned = String(String.UnicodeScalarView(kept)).drop { $0 == "-" }
        return cleaned.isEmpty ? "member" : String(cleaned.prefix(maxIDLength))
    }

    // MARK: Internals

    /// The tree after a drop, or why it cannot be dropped. One place decides both, so `canDrop`
    /// and `drop` agree.
    private static func plan(_ id: String, onto target: String, as position: Position,
                             in members: [Team.Member]) -> (members: [Team.Member]?, verdict: DropVerdict) {
        func refuse(_ reason: String) -> (members: [Team.Member]?, verdict: DropVerdict) { (nil, .refused(reason)) }
        guard var forest = Forest(members), let member = forest.byID[id], let onto = forest.byID[target] else {
            return refuse("That Member is not in the tree.")
        }
        if id == target {
            return position == .child
                ? refuse("\(id) cannot become its own child: its parents would lead back to itself.")
                : refuse("\(id) is already there.")
        }
        let subtree = forest.subtree(of: id)
        if subtree.contains(target) {
            return refuse("\(id) cannot move into its own subtree.")
        }
        let newParent = position == .child ? target : onto.parent
        let parent = newParent.flatMap { forest.byID[$0] }
        if member.action == "verify", parent?.action != "execute" {
            return refuse("\(id) is a verify Member and needs an execute Member above it.")
        }
        let above = newParent.map { forest.depth(of: $0) } ?? 0
        if above + forest.height(of: id) > TeamForm.maxDepth {
            return refuse("The tree can be at most \(TeamForm.maxDepth) deep; this drop would make it \(above + forest.height(of: id)).")
        }
        let at = forest.dropIndex(of: id, target: target, position: position)
        forest.detach(id)
        forest.insert(member, under: newParent, at: at)
        guard let result = finish(forest) else {
            return refuse("That would leave the Team with a tree it cannot use.")
        }
        if result == members { return refuse("\(id) is already there.") }
        return (result, .ok)
    }

    private static func finish(_ forest: Forest) -> [Team.Member]? {
        guard let members = forest.flattened, isValid(members) else { return nil }
        return members
    }

    /// The Members as a forest: each Member by id and each parent's children in order, so an
    /// operation edits the tree and then writes it out again in tree order.
    private struct Forest {
        var byID: [String: Team.Member] = [:]
        /// Child ids by parent id; level 1 is under nil.
        var children: [String?: [String]] = [:]

        /// Nil when two Members share an id, a parent is no Member, or the parents lead in a circle:
        /// no operation can make sense of such a tree.
        init?(_ members: [Team.Member]) {
            for member in members {
                if byID[member.id] != nil { return nil }
                byID[member.id] = member
                children[member.parent, default: []].append(member.id)
            }
            if flattened == nil { return nil }
        }

        /// The ids of `id` and everything under it, in tree order; empty for an unknown id.
        func subtree(of id: String) -> [String] {
            guard byID[id] != nil else { return [] }
            var out: [String] = []
            var pending = [id]
            while let next = pending.popLast() {
                out.append(next)
                pending.append(contentsOf: (children[next] ?? []).reversed())
            }
            return out
        }

        func siblings(of id: String) -> [String] {
            children[byID[id]?.parent] ?? []
        }

        /// 1 for a level 1 Member, plus one for each parent above.
        func depth(of id: String) -> Int {
            var depth = 1
            var above = byID[id]?.parent
            while let next = above, depth <= byID.count {
                depth += 1
                above = byID[next]?.parent
            }
            return depth
        }

        /// How many levels the subtree of `id` has, `id` included.
        func height(of id: String) -> Int {
            1 + ((children[id] ?? []).map { height(of: $0) }.max() ?? 0)
        }

        /// Takes `id` out of its parent's list of children; its entry stays until it is put back.
        mutating func detach(_ id: String) {
            guard let member = byID[id] else { return }
            children[member.parent]?.removeAll { $0 == id }
        }

        /// Puts `member` under `parent` at place `index` among its children, or last.
        mutating func insert(_ member: Team.Member, under parent: String?, at index: Int?) {
            var member = member
            member.parent = parent
            byID[member.id] = member
            var list = children[parent] ?? []
            list.insert(member.id, at: min(index ?? list.count, list.count))
            children[parent] = list
        }

        /// Where `id` goes among the children of the new parent once it is out of its old place:
        /// nil (last) under the target, else just above or below the target.
        func dropIndex(of id: String, target: String, position: Position) -> Int? {
            guard position != .child else { return nil }
            let others = siblings(of: target).filter { $0 != id }
            guard let at = others.firstIndex(of: target) else { return nil }
            return position == .before ? at : at + 1
        }

        /// The Members in tree order; nil when some are not reachable from level 1, as in a cycle,
        /// or a parent is missing.
        var flattened: [Team.Member]? {
            var out: [Team.Member] = []
            var pending = (children[nil] ?? []).reversed() as [String]
            while let next = pending.popLast() {
                guard let member = byID[next] else { return nil }
                out.append(member)
                pending.append(contentsOf: (children[next] ?? []).reversed())
            }
            return out.count == byID.count ? out : nil
        }
    }
}

import Foundation

/// A Team's Members and the Hand-offs between them as the Teams canvas shows and edits them
/// (features/0092, ui-ux/0144), as pure functions on the flat array a Team file holds. Every edit
/// hands back Members that pass the rules `TeamForm.blocker` checks, apart from a Member a removal
/// left with no Hand-off in, which stays flagged until the human draws one; a refused edit changes
/// nothing and says why in one plain line.
public enum TeamGraph {
    /// The longest a Member's id may be.
    public static let maxIDLength = 32
    /// Every place on the canvas is a multiple of this, in points.
    public static let grid = 8
    /// A node's size, in points.
    public static let nodeWidth = 192
    public static let nodeHeight = 64
    /// From one row's top to the next, and from one node's left to the next in a row.
    public static let rowStep = 136
    public static let columnStep = 216
    /// The most nodes Echo lays out side by side; more wrap onto a row below, set half a step
    /// over so the lines into them pass between the nodes above.
    public static let rowWidth = 3
    /// The Orchestrator's node: centred on x = 0, at the top.
    public static let orchestratorPoint = Point(x: -nodeWidth / 2, y: 0)

    /// A node's top-left corner on the canvas.
    public struct Point: Equatable, Hashable, Sendable {
        public var x: Int
        public var y: Int

        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    /// One Hand-off as a line: from a Member's id or `Team.orchestratorID`, to a Member's id.
    public struct Line: Equatable, Hashable, Sendable {
        public let from: String
        public let to: String
        public let auto: Bool
    }

    /// The draft after an edit, and what the canvas picks next; `notice` is the one line under the
    /// canvas when the edit was refused, and nothing changed then.
    public struct Edit: Equatable, Sendable {
        public var members: [Team.Member]
        /// The Member picked afterwards; nil is the Orchestrator.
        public var selected: String?
        public var notice: String?

        public init(members: [Team.Member], selected: String?, notice: String? = nil) {
            self.members = members
            self.selected = selected
            self.notice = notice
        }
    }

    // MARK: Reading

    /// `value` to the nearest multiple of the grid.
    public static func snap(_ value: Int) -> Int {
        Int((Double(value) / Double(grid)).rounded()) * grid
    }

    /// Where every Member's node sits: its own `x` and `y` when it has both, else laid out by Echo,
    /// in rows by the longest chain of Hand-offs from the Orchestrator and, within a row, in file
    /// order centred under the Orchestrator, at most `rowWidth` side by side.
    public static func positions(_ members: [Team.Member]) -> [String: Point] {
        let levels = levels(members)
        var out: [String: Point] = [:]
        var rows: [Int: [String]] = [:]
        for member in members {
            if let x = member.x, let y = member.y {
                out[member.id] = Point(x: x, y: y)
            } else {
                rows[levels[member.id] ?? 1, default: []].append(member.id)
            }
        }
        var y = 0
        for level in rows.keys.sorted() {
            let ids = rows[level]!
            for (wrap, start) in stride(from: 0, to: ids.count, by: rowWidth).enumerated() {
                y += rowStep
                let part = ids[start..<min(start + rowWidth, ids.count)]
                let width = (part.count - 1) * columnStep + nodeWidth
                // A wrapped row with an odd count would centre a node under one above; half a step over
                // puts each under a gap instead.
                let over = wrap > 0 && part.count % 2 == 1 ? columnStep / 2 : 0
                for (at, id) in part.enumerated() {
                    out[id] = Point(x: snap(-width / 2) + over + at * columnStep, y: y)
                }
            }
        }
        return out
    }

    /// The Members with every node's place written into `x` and `y`, so an edit to one does not move
    /// the ones Echo laid out.
    public static func placed(_ members: [Team.Member]) -> [Team.Member] {
        let at = positions(members)
        return members.map { member in
            var member = member
            member.x = at[member.id]?.x
            member.y = at[member.id]?.y
            return member
        }
    }

    /// Each Member's row: one more than the furthest of the Members it comes after, 1 under the
    /// Orchestrator alone. A loop or an unknown Member counts as the Orchestrator.
    static func levels(_ members: [Team.Member]) -> [String: Int] {
        var memo: [String: Int] = [:]
        func level(_ id: String, _ path: Set<String>) -> Int {
            if let known = memo[id] { return known }
            guard let member = members.first(where: { $0.id == id }), !path.contains(id) else { return 0 }
            let above = member.handOffs.map { level($0.from, path.union([id])) }.max() ?? 0
            memo[id] = above + 1
            return above + 1
        }
        for member in members { _ = level(member.id, []) }
        return memo
    }

    /// Every Hand-off as a line, in file order.
    public static func lines(_ members: [Team.Member]) -> [Line] {
        members.flatMap { member in
            member.handOffs.map { Line(from: $0.from, to: member.id, auto: $0.auto) }
        }
    }

    /// The right-angled path of a line from the node at `from` to the node at `to` (top-left
    /// corners): out of the source's bottom, into the target's top. A target not below the source
    /// is reached round the right of both nodes.
    ///
    /// A line that would pass down through another node (`nodes`, top-left corners) on its way to a
    /// lower row takes the nearest clear lane beside it, and turns in again just above its target.
    public static func route(from: Point, to: Point, avoiding nodes: [Point] = []) -> [Point] {
        let start = Point(x: from.x + nodeWidth / 2, y: from.y + nodeHeight)
        let end = Point(x: to.x + nodeWidth / 2, y: to.y)
        if end.y >= start.y + 2 * grid {
            // The bend sits just under the source, so a line into a lower row runs above the rows between.
            let middle = min(start.y + 4 * grid, (start.y + end.y) / 2)
            let last = max(middle, end.y - 4 * grid)
            let others = nodes.filter { $0 != from && $0 != to }
            func clear(_ x: Int) -> Bool {
                !others.contains { node in
                    x > node.x - grid && x < node.x + nodeWidth + grid && node.y < last && node.y + nodeHeight > middle
                }
            }
            if clear(end.x) {
                return [start, Point(x: start.x, y: middle), Point(x: end.x, y: middle), end]
            }
            let lanes = (1...8).flatMap { [end.x - $0 * columnStep / 2, end.x + $0 * columnStep / 2] }
            let lane = lanes.first(where: clear) ?? end.x
            return [start, Point(x: start.x, y: middle), Point(x: lane, y: middle), Point(x: lane, y: last),
                    Point(x: end.x, y: last), end]
        }
        let below = start.y + 2 * grid, above = end.y - 2 * grid
        let side = max(from.x, to.x) + nodeWidth + 2 * grid
        return [start, Point(x: start.x, y: below), Point(x: side, y: below), Point(x: side, y: above),
                Point(x: end.x, y: above), end]
    }

    /// The Members the Orchestrator cannot reach along Hand-offs.
    public static func unreachable(_ members: [Team.Member]) -> Set<String> {
        var reached: Set<String> = [Team.orchestratorID]
        var grew = true
        while grew {
            grew = false
            for member in members where !reached.contains(member.id) {
                if member.handOffs.contains(where: { reached.contains($0.from) }) {
                    reached.insert(member.id)
                    grew = true
                }
            }
        }
        return Set(members.map(\.id)).subtracting(reached)
    }

    /// The Member picked from `id` (nil is the Orchestrator) by an arrow key: the nearest node that
    /// way, weighing distance across the arrow twice; `id` itself when there is none.
    public static func nearest(_ direction: CanvasDirection, from id: String?, in members: [Team.Member]) -> String? {
        let at = positions(members)
        let here = id.flatMap { at[$0] } ?? orchestratorPoint
        var best: (id: String?, score: Int)?
        let nodes: [(String?, Point)] = [(nil, orchestratorPoint)] + members.compactMap { m in at[m.id].map { (m.id, $0) } }
        for (other, point) in nodes where other != id {
            let dx = point.x - here.x, dy = point.y - here.y
            let (along, across): (Int, Int)
            switch direction {
            case .up: (along, across) = (-dy, dx)
            case .down: (along, across) = (dy, dx)
            case .left: (along, across) = (-dx, dy)
            case .right: (along, across) = (dx, dy)
            }
            guard along > 0 else { continue }
            let score = along + 2 * abs(across)
            if best == nil || score < best!.score { best = (other, score) }
        }
        return best.map(\.id) ?? id
    }

    // MARK: Members

    /// A new Member of `action` after the picked one (`after`, nil for the Orchestrator), joined to
    /// it by a hint Hand-off and placed under it. Its id comes from the Action and is made unique;
    /// its Profile is the Action's default, or `profile` (a `custom` Member needs one).
    public static func add(action: String, profile: String? = nil, after source: String?,
                           to members: [Team.Member], actions: [Action] = Action.shipped) -> Edit {
        let keep = Edit(members: members, selected: source)
        func refuse(_ text: String) -> Edit { Edit(members: members, selected: source, notice: text) }
        guard Action.isAction(action) else { return refuse("\"\(action)\" is not an Action.") }
        guard let chosen = profile ?? actions.first(where: { $0.id == action })?.profile, !chosen.isEmpty else {
            return refuse("A custom Member needs a Profile of its own. Use Add Member, Custom.")
        }
        if members.count >= TeamForm.maxMembers {
            return refuse("A Team holds at most \(TeamForm.maxMembers) Members.")
        }
        let above = source.flatMap { id in members.first { $0.id == id } }
        if source != nil, above == nil { return refuse("That Member is not on the canvas.") }
        if actions.first(where: { $0.id == action })?.under == "execute", above?.action != "execute" {
            return refuse("A \(action) Member comes after an execute Member. Pick one first.")
        }
        var out = placed(members)
        let id = uniqueID(from: action, taking: Set(members.map(\.id)))
        let origin = above.flatMap { positions(members)[$0.id] } ?? orchestratorPoint
        let spot = free(near: Point(x: origin.x, y: origin.y + rowStep), in: out)
        out.append(Team.Member(id: id, action: action, profile: chosen,
                               after: above.map { [Team.HandOff(from: $0.id)] }, x: spot.x, y: spot.y))
        return checked(out, selected: id, else: keep)
    }

    /// A copy of `id` beside it under a new id (`build-2`), with the same Hand-offs in and none out.
    public static func duplicate(_ id: String, in members: [Team.Member]) -> Edit {
        let keep = Edit(members: members, selected: id)
        guard let original = members.first(where: { $0.id == id }) else { return keep }
        if members.count >= TeamForm.maxMembers {
            return Edit(members: members, selected: id,
                        notice: "Copying \(id) would make \(members.count + 1) and a Team holds at most \(TeamForm.maxMembers) Members.")
        }
        var out = placed(members)
        var copy = out.first { $0.id == id } ?? original
        copy.id = uniqueID(from: id, taking: Set(members.map(\.id)))
        // A second automatic Hand-off from the same Member would start both; the copy's is a hint.
        copy.after = copy.after?.map { Team.HandOff(from: $0.from) }
        let spot = free(near: Point(x: (copy.x ?? 0) + columnStep, y: copy.y ?? rowStep), in: out)
        copy.x = spot.x
        copy.y = spot.y
        let at = (out.firstIndex { $0.id == id } ?? out.count - 1) + 1
        out.insert(copy, at: at)
        return checked(out, selected: copy.id, else: keep)
    }

    /// The Members without `id` and its Hand-offs. A Member left with none coming in keeps an empty
    /// list and is flagged as unreachable until the human draws one (features/0092).
    public static func remove(_ id: String, from members: [Team.Member]) -> Edit {
        guard let gone = members.first(where: { $0.id == id }) else { return Edit(members: members, selected: nil) }
        let out: [Team.Member] = placed(members).filter { $0.id != id }.map { member in
            var member = member
            if let after = member.after, after.contains(where: { $0.from == id }) {
                member.after = after.filter { $0.from != id }
            }
            return member
        }
        let back = gone.handOffs.first { handOff in
            handOff.from != Team.orchestratorID && out.contains { $0.id == handOff.from }
        }
        return Edit(members: out, selected: back?.from)
    }

    /// The Members with `id`'s node at `point`, snapped to the grid.
    public static func move(_ id: String, to point: Point, in members: [Team.Member]) -> [Team.Member] {
        placed(members).map { member in
            guard member.id == id else { return member }
            var member = member
            member.x = snap(point.x)
            member.y = snap(point.y)
            return member
        }
    }

    /// The Members with `id`'s node one grid step `direction`.
    public static func nudge(_ id: String, _ direction: CanvasDirection, in members: [Team.Member]) -> [Team.Member] {
        guard let at = positions(members)[id] else { return members }
        let (dx, dy): (Int, Int)
        switch direction {
        case .up: (dx, dy) = (0, -grid)
        case .down: (dx, dy) = (0, grid)
        case .left: (dx, dy) = (-grid, 0)
        case .right: (dx, dy) = (grid, 0)
        }
        return move(id, to: Point(x: at.x + dx, y: at.y + dy), in: members)
    }

    // MARK: Hand-offs

    /// A hint Hand-off from `from` (a Member or `Team.orchestratorID`) to `to`. A Member that hung
    /// from the Orchestrator only by default (no `after`) now comes after `from` alone; one that
    /// names the Orchestrator itself keeps that line too.
    public static func connect(_ from: String, to: String, in members: [Team.Member]) -> Edit {
        let keep = Edit(members: members, selected: to)
        func refuse(_ text: String) -> Edit { Edit(members: members, selected: to, notice: text) }
        if to == Team.orchestratorID { return refuse("Nothing comes before the Orchestrator.") }
        if from == to { return refuse("\(to) cannot come after itself.") }
        guard let target = members.first(where: { $0.id == to }) else { return keep }
        let source = members.first { $0.id == from }
        if from != Team.orchestratorID, source == nil { return keep }
        if target.handOffs.contains(where: { $0.from == from }) {
            return refuse("\(to) already comes after \(from == Team.orchestratorID ? "the Orchestrator" : from).")
        }
        if target.action == "verify", source?.action != "execute" {
            return refuse("\(to) is a verify Member and comes only after execute Members.")
        }
        if leadsBack(from, to: to, in: members) {
            return refuse("\(from) already comes after \(to), so this Hand-off would make a loop.")
        }
        let out = members.map { member -> Team.Member in
            guard member.id == to else { return member }
            var member = member
            member.after = (member.after ?? []) + [Team.HandOff(from: from)]
            return member
        }
        return checked(out, selected: to, else: keep)
    }

    /// The Members without the Hand-off from `from` to `to`; one left with none is flagged.
    public static func disconnect(_ from: String, to: String, in members: [Team.Member]) -> Edit {
        let out = members.map { member -> Team.Member in
            guard member.id == to else { return member }
            var member = member
            member.after = member.handOffs.filter { $0.from != from }
            return member
        }
        return Edit(members: out, selected: to)
    }

    /// The Hand-off from `from` to `to` made automatic, or a hint again.
    public static func setAutomatic(_ on: Bool, from: String, to: String, in members: [Team.Member]) -> Edit {
        func refuse(_ text: String) -> Edit { Edit(members: members, selected: to, notice: text) }
        guard let target = members.first(where: { $0.id == to }),
              target.handOffs.contains(where: { $0.from == from }) else { return Edit(members: members, selected: to) }
        if on {
            if from == Team.orchestratorID {
                return refuse("A Hand-off from the Orchestrator cannot be automatic: the Orchestrator starts its own Workers.")
            }
            if target.action == "verify" {
                return refuse("A Hand-off into a verify Member runs through --verify and cannot be automatic.")
            }
            if let other = target.handOffs.first(where: { $0.auto && $0.from != from }) {
                return refuse("\(to) already has an automatic Hand-off in, from \(other.from). A Member has at most one.")
            }
        }
        let out = members.map { member -> Team.Member in
            guard member.id == to else { return member }
            var member = member
            member.after = member.handOffs.map { $0.from == from ? Team.HandOff(from: from, auto: on) : $0 }
            return member
        }
        return Edit(members: out, selected: to)
    }

    /// The Members and the Orchestrator that `to` could come after next: not itself, not one it
    /// already comes after, and not one that would make a loop; only execute Members for a verify.
    public static func sources(for to: String, in members: [Team.Member]) -> [String] {
        guard let target = members.first(where: { $0.id == to }) else { return [] }
        let taken = Set(target.handOffs.map(\.from))
        var out = [Team.orchestratorID] + members.map(\.id)
        out.removeAll { $0 == to || taken.contains($0) || leadsBack($0, to: to, in: members) }
        if target.action == "verify" {
            out.removeAll { id in members.first { $0.id == id }?.action != "execute" }
        }
        return out
    }

    /// Whether `from` already comes after `to`, at any distance, so a Hand-off from it to `to`
    /// would close a loop.
    static func leadsBack(_ from: String, to: String, in members: [Team.Member]) -> Bool {
        var seen: Set<String> = []
        var pending = [from]
        while let next = pending.popLast() {
            if next == to { return true }
            guard seen.insert(next).inserted, let member = members.first(where: { $0.id == next }) else { continue }
            pending += (member.after ?? []).map(\.from)
        }
        return false
    }

    // MARK: Keys

    /// What `command` does to the draft with `selected` picked (nil is the Orchestrator); `.rename`
    /// is the view's to carry out and changes nothing here.
    public static func apply(_ command: CanvasCommand, to members: [Team.Member], selected: String?,
                             actions: [Action] = Action.shipped) -> Edit {
        switch command {
        case .select(let direction):
            return Edit(members: members, selected: nearest(direction, from: selected, in: members))
        case .rename:
            return Edit(members: members, selected: selected)
        case .add(let action):
            return add(action: action, after: selected, to: members, actions: actions)
        default:
            break
        }
        guard let selected, members.contains(where: { $0.id == selected }) else {
            return Edit(members: members, selected: selected,
                        notice: "The Orchestrator stays where it is. Pick a Member first.")
        }
        switch command {
        case .nudge(let direction):
            return Edit(members: nudge(selected, direction, in: members), selected: selected)
        case .duplicate:
            return duplicate(selected, in: members)
        case .remove:
            return remove(selected, from: members)
        default:
            return Edit(members: members, selected: selected)
        }
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
        let id = cleaned.isEmpty ? "member" : String(cleaned.prefix(maxIDLength))
        return id == Team.orchestratorID ? "orchestrator-2" : id
    }

    // MARK: Internals

    /// The first place from `point` rightwards, a column at a time, where no node sits.
    private static func free(near point: Point, in members: [Team.Member]) -> Point {
        let taken = members.compactMap { m in m.x.flatMap { x in m.y.map { Point(x: x, y: $0) } } } + [orchestratorPoint]
        var spot = Point(x: snap(point.x), y: snap(point.y))
        while taken.contains(where: { abs($0.x - spot.x) < nodeWidth && abs($0.y - spot.y) < nodeHeight }) {
            spot.x += columnStep
        }
        return spot
    }

    /// `members` when they pass `TeamForm`'s checks, else `fallback` with the reason.
    private static func checked(_ members: [Team.Member], selected: String?, else fallback: Edit) -> Edit {
        if let problem = TeamForm.problem(with: members) {
            var edit = fallback
            edit.notice = problem
            return edit
        }
        return Edit(members: members, selected: selected)
    }
}

/// An arrow key's way.
public enum CanvasDirection: Equatable, Sendable {
    case up, down, left, right
}

/// The modifier keys that matter to the canvas.
public struct CanvasModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let option = CanvasModifiers(rawValue: 1)
    public static let command = CanvasModifiers(rawValue: 2)
    public static let control = CanvasModifiers(rawValue: 4)
    public static let shift = CanvasModifiers(rawValue: 8)
}

/// A key the canvas may act on.
public enum CanvasKey: Equatable, Sendable {
    case arrow(CanvasDirection)
    /// Return.
    case enter
    /// Delete, and the forward delete key.
    case delete
    /// A letter or digit, as typed.
    case character(String)
}

/// What the canvas can be asked to do, by key or by button.
public enum CanvasCommand: Equatable, Sendable {
    /// Pick the nearest node that way.
    case select(CanvasDirection)
    /// Move the picked Member one grid step that way.
    case nudge(CanvasDirection)
    /// Open the picked Member's name field.
    case rename
    case remove
    /// Add a Member of the Action after the picked one, or after the Orchestrator.
    case add(String)
    case duplicate

    /// Whether it changes the draft; picking works in a Team that cannot be edited.
    public var edits: Bool {
        if case .select = self { return false }
        return true
    }
}

public enum CanvasKeys {
    /// The Action the `a` key adds: the one most Teams grow by.
    public static let addedByKey = "execute"

    /// What a key does with the canvas focused and no text field being edited (ui-ux/0144); nil for
    /// a key the canvas leaves alone, so Esc, Tab and the Command keys reach the window.
    public static func command(for key: CanvasKey, modifiers: CanvasModifiers) -> CanvasCommand? {
        switch (key, modifiers) {
        case (.arrow(let direction), []): .select(direction)
        case (.arrow(let direction), .option): .nudge(direction)
        case (.enter, []): .rename
        case (.delete, []): .remove
        case (.character("a"), []): .add(addedByKey)
        case (.character("d"), []): .duplicate
        default: nil
        }
    }
}

// MARK: Looks

public enum ActionLook {
    /// The SF Symbol of an Action's nodes and menu items.
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

    /// The Action's name as the canvas shows it: "Write code", or "Custom".
    public static func title(for action: String, actions: [Action] = Action.shipped) -> String {
        actions.first { $0.id == action }?.title ?? "Custom"
    }

    /// The grey line under a node's name: the Profile, then the model it runs on when one is known.
    public static func meta(profile: String, model: String) -> String {
        model.isEmpty ? profile : "\(profile), \(model)"
    }
}

/// One entry of the Add Member menu: an Action, a shipped Profile for the Action it is the default
/// of, or Custom.
public struct AddChoice: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable { case action, worker, custom }

    public let kind: Kind
    public let title: String
    public let action: String
    public let profile: String?

    public var id: String { "\(kind):\(title)" }

    /// The shipped Workers, in the order the menu lists them.
    public static let workers = ["naruto", "sasuke", "hinata", "jiraiya", "lee", "ino"]

    /// The six Actions, then the six shipped Workers, then Custom.
    public static func all(actions: [Action] = Action.shipped) -> [AddChoice] {
        let byAction = actions.map { AddChoice(kind: .action, title: $0.title, action: $0.id, profile: $0.profile) }
        let byWorker = workers.compactMap { name in
            actions.first { $0.profile == name }.map { AddChoice(kind: .worker, title: name, action: $0.id, profile: name) }
        }
        return byAction + byWorker + [AddChoice(kind: .custom, title: "Custom", action: Action.custom, profile: nil)]
    }
}

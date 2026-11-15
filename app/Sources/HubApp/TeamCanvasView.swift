import AppKit
import Foundry
import HubCore
import SwiftUI

/// What the canvas's keys, drags and buttons do to the Team's draft (ui-ux/0144). The decisions are
/// `TeamGraph`'s; this carries them out and shows the one line when one is refused.
extension TeamSettingsModel {
    func perform(_ command: CanvasCommand) {
        if command.edits, readOnly {
            treeNotice = Self.readOnlyReason
            return
        }
        switch command {
        case .rename:
            if member == nil {
                treeNotice = "Pick a Member to rename it. The Orchestrator's fields are on the right."
            } else {
                treeNotice = nil
                nameFocusRequest += 1
            }
        case .add(Action.custom):
            treeNotice = nil
            newCustomWorker(after: member?.id)
        default:
            apply(TeamGraph.apply(command, to: form.members, selected: selectedMember))
        }
    }

    /// Moves a Member's node to `point`, on the grid.
    func moveNode(_ id: String, to point: TeamGraph.Point) {
        guard !refuseReadOnly() else { return }
        form.members = TeamGraph.move(id, to: point, in: form.members)
        selectedMember = id
        treeNotice = nil
    }

    /// Draws a hint Hand-off from `from` (a Member or the Orchestrator) to `to`.
    func connect(_ from: String, to: String) {
        guard !refuseReadOnly() else { return }
        apply(TeamGraph.connect(from, to: to, in: form.members))
    }

    func disconnect(_ from: String, to: String) {
        guard !refuseReadOnly() else { return }
        apply(TeamGraph.disconnect(from, to: to, in: form.members))
    }

    func setAutomatic(_ on: Bool, from: String, to: String) {
        guard !refuseReadOnly() else { return }
        apply(TeamGraph.setAutomatic(on, from: from, to: to, in: form.members))
    }

    private func apply(_ edit: TeamGraph.Edit) {
        form.members = edit.members
        selectedMember = edit.selected
        treeNotice = edit.notice
        memberNotice = nil
    }

    private func refuseReadOnly() -> Bool {
        if readOnly { treeNotice = Self.readOnlyReason }
        return readOnly
    }

    /// Why nothing on Echo's own Teams can be changed.
    static let readOnlyReason = "Echo's own Team. Duplicate it to change it."
}

/// The zoom, and the drag in progress, held outside the views (no `@State` here): a node being moved
/// shows at its new place until the drag ends, and a Hand-off being drawn follows the pointer.
@MainActor
final class CanvasState: ObservableObject {
    static let zooms: ClosedRange<CGFloat> = 0.5...2

    @Published var zoom: CGFloat = 1
    /// The Member being moved and how far, on the canvas.
    @Published var moving: (id: String, by: CGSize)?
    /// Where a Hand-off being drawn starts, and the pointer, on the canvas.
    @Published var linking: (from: String, to: CGPoint)?
    /// The zoom when a pinch began.
    var pinchStart: CGFloat?

    func zoom(by step: CGFloat) { zoom = Self.clamped(zoom + step) }

    static func clamped(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, zooms.lowerBound), zooms.upperBound)
    }

    /// The zoom that frames all of `members` in `room`, within 50% to 200%.
    static func fit(_ members: [Team.Member], in room: CGSize) -> CGFloat? {
        let whole = CanvasFrame(points: Array(TeamGraph.positions(members).values), room: .zero, zoom: 1)
        guard whole.size.width > 0, whole.size.height > 0, room.width > 0, room.height > 0 else { return nil }
        return clamped(min(room.width / whole.size.width, room.height / whole.size.height))
    }
}

/// The Team's canvas (ui-ux/0144): the Team's head, then the Orchestrator's node at the top and every
/// Member's node where it was put or where Echo laid it out, joined by Hand-off lines; then the one
/// line of a refusal and the bar with Add Member, the lines' key, the zoom and the More menu.
struct TeamCanvasColumn: View {
    @ObservedObject var teams: TeamSettingsModel
    @StateObject private var canvas = CanvasState()
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 600
            VStack(alignment: .leading, spacing: 0) {
                TeamHead(teams: teams, mix: TeamMix(teams: teams), compact: compact)
                GeometryReader { area in
                    ScrollViewReader { scroller in
                    ScrollView([.horizontal, .vertical]) {
                        CanvasBoard(teams: teams, canvas: canvas, room: area.size, focused: focused) { id in
                            teams.selectMember(id)
                            focused = true
                        }
                    }
                    .scrollIndicators(.automatic)
                    .background(Ledger.desk)
                    .gesture(MagnifyGesture()
                        .onChanged { value in
                            let start = canvas.pinchStart ?? canvas.zoom
                            canvas.pinchStart = start
                            canvas.zoom = CanvasState.clamped(start * value.magnification)
                        }
                        .onEnded { _ in canvas.pinchStart = nil })
                    // A Team opens at 100%, or smaller when it is wider than the room, with its
                    // Orchestrator at the top centre.
                    .onAppear { open(scroller, room: area.size) }
                    .onChange(of: teams.picked) { open(scroller, room: area.size) }
                    .background(FitRequest(canvas: canvas, teams: teams, room: area.size) {
                        scroller.scrollTo(CanvasBoard.top, anchor: .top)
                    })
                    }
                }
                // The keys act only here, and a text field is never inside this view.
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
                .onChange(of: focused) { teams.treeFocused = focused }
                .onChange(of: teams.treeFocusRequest) { focused = true }
                .onDisappear { teams.treeFocused = false }
                .accessibilityLabel("Team canvas")
                CanvasCaption(teams: teams, pad: compact ? 20 : 28)
                CanvasBar(teams: teams, canvas: canvas, compact: compact)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func open(_ scroller: ScrollViewProxy, room: CGSize) {
        // By its width only: a tall Team scrolls rather than shrinking past reading.
        canvas.zoom = min(1, CanvasState.fit(teams.form.members, in: CGSize(width: room.width, height: .infinity)) ?? 1)
        DispatchQueue.main.async { scroller.scrollTo(CanvasBoard.top, anchor: .top) }
    }

    /// The arrows are always the canvas's while it has the keyboard, so they never reach the page's
    /// section keys; Esc hands the keyboard back to the sections.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            teams.pageFocusRequest += 1
            return .handled
        }
        guard let key = Self.key(of: press),
              let command = CanvasKeys.command(for: key, modifiers: Self.modifiers(of: press.modifiers)) else {
            return .ignored
        }
        teams.perform(command)
        return .handled
    }

    private static func key(of press: KeyPress) -> CanvasKey? {
        switch press.key {
        case .upArrow: .arrow(.up)
        case .downArrow: .arrow(.down)
        case .leftArrow: .arrow(.left)
        case .rightArrow: .arrow(.right)
        case .return: .enter
        case .delete, .deleteForward: .delete
        default: press.characters.isEmpty ? nil : .character(press.characters)
        }
    }

    private static func modifiers(of flags: EventModifiers) -> CanvasModifiers {
        var out: CanvasModifiers = []
        if flags.contains(.option) { out.insert(.option) }
        if flags.contains(.command) { out.insert(.command) }
        if flags.contains(.control) { out.insert(.control) }
        if flags.contains(.shift) { out.insert(.shift) }
        return out
    }
}

/// What the canvas covers: every node with a margin round it, and at least the room it is shown in.
struct CanvasFrame {
    static let margin = 48
    let origin: TeamGraph.Point
    let size: CGSize

    init(points: [TeamGraph.Point], room: CGSize, zoom: CGFloat) {
        let all = points + [TeamGraph.orchestratorPoint]
        let minX = (all.map(\.x).min() ?? 0) - Self.margin
        let minY = (all.map(\.y).min() ?? 0) - Self.margin
        let maxX = (all.map(\.x).max() ?? 0) + TeamGraph.nodeWidth + Self.margin
        let maxY = (all.map(\.y).max() ?? 0) + TeamGraph.nodeHeight + Self.margin
        let width = max(CGFloat(maxX - minX), room.width / zoom)
        let height = max(CGFloat(maxY - minY), room.height / zoom)
        // Extra room is shared either side, so the Orchestrator stays centred.
        origin = TeamGraph.Point(x: minX - Int((width - CGFloat(maxX - minX)) / 2), y: minY)
        size = CGSize(width: width, height: height)
    }

    /// Where a canvas point is drawn in the board.
    func place(_ point: TeamGraph.Point) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    /// The canvas point under a board point.
    func point(at place: CGPoint) -> TeamGraph.Point {
        TeamGraph.Point(x: Int(place.x) + origin.x, y: Int(place.y) + origin.y)
    }
}

/// The board inside the scroll view: the grid, the lines, then the nodes, drawn at canvas size and
/// scaled by the zoom.
private struct CanvasBoard: View {
    @ObservedObject var teams: TeamSettingsModel
    @ObservedObject var canvas: CanvasState
    let room: CGSize
    let focused: Bool
    let pick: (String?) -> Void

    static let space = "team-canvas"
    /// The scroll target at the top of the Orchestrator's node, in the scaled board.
    static let top = "team-canvas-top"

    var body: some View {
        let members = teams.form.members
        let at = TeamGraph.positions(members)
        let frame = CanvasFrame(points: Array(at.values), room: room, zoom: canvas.zoom)
        let unreachable = TeamGraph.unreachable(members)
        let mix = TeamMix(teams: teams)
        ZStack(alignment: .topLeading) {
            CanvasGrid()
            CanvasLines(lines: TeamGraph.lines(members), at: shown(at), frame: frame, linking: canvas.linking)
            NodeView(teams: teams, canvas: canvas, frame: frame, id: nil, point: TeamGraph.orchestratorPoint,
                     mix: mix, unreachable: false, picked: teams.member == nil, focused: focused, pick: pick)
            ForEach(members) { member in
                NodeView(teams: teams, canvas: canvas, frame: frame, id: member.id,
                         point: at[member.id] ?? TeamGraph.orchestratorPoint, mix: mix,
                         unreachable: unreachable.contains(member.id),
                         picked: member.id == teams.selectedMember, focused: focused, pick: pick)
            }
        }
        .frame(width: frame.size.width, height: frame.size.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .contentShape(Rectangle())
        .onTapGesture { pick(nil) }
        .scaleEffect(canvas.zoom, anchor: .topLeading)
        .frame(width: frame.size.width * canvas.zoom, height: frame.size.height * canvas.zoom, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            // Outside the scale, so scrolling to it lands where the node is drawn.
            let place = frame.place(TeamGraph.orchestratorPoint)
            Color.clear
                .frame(width: CGFloat(TeamGraph.nodeWidth) * canvas.zoom, height: 1)
                .id(Self.top)
                .padding(.leading, place.x * canvas.zoom)
                .padding(.top, max(0, place.y * canvas.zoom - 24))
        }
    }

    /// The places with the node being moved where the pointer has it, so its lines follow.
    private func shown(_ at: [String: TeamGraph.Point]) -> [String: TeamGraph.Point] {
        guard let moving = canvas.moving, let from = at[moving.id] else { return at }
        var out = at
        out[moving.id] = TeamGraph.Point(x: from.x + Int(moving.by.width), y: from.y + Int(moving.by.height))
        return out
    }
}

/// The 8 pt grid as faint dots every other step, so the snapping can be seen.
private struct CanvasGrid: View {
    var body: some View {
        Canvas { context, size in
            let step = CGFloat(TeamGraph.grid * 2)
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(Ledger.rule))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Every Hand-off as a right-angled line with an arrowhead into its target's top: a hint is a
/// hairline in the rule's grey, an automatic one 2 pt in the accent; a line being drawn is dashed.
private struct CanvasLines: View {
    let lines: [TeamGraph.Line]
    let at: [String: TeamGraph.Point]
    let frame: CanvasFrame
    let linking: (from: String, to: CGPoint)?

    var body: some View {
        let nodes = Array(at.values) + [TeamGraph.orchestratorPoint]
        Canvas { context, _ in
            for line in lines {
                guard let from = point(line.from), let to = point(line.to) else { continue }
                let route = TeamGraph.route(from: from, to: to, avoiding: nodes).map(frame.place)
                let color = line.auto ? Ledger.accent : Ledger.rule
                var path = Path()
                path.addLines(route)
                context.stroke(path, with: .color(color), lineWidth: line.auto ? Ledger.ruleStrong : Ledger.hairline)
                if let end = route.last {
                    context.fill(Self.head(at: end), with: .color(line.auto ? Ledger.accent : Ledger.ink3))
                }
            }
            if let linking, let from = point(linking.from) {
                let start = frame.place(TeamGraph.Point(x: from.x + TeamGraph.nodeWidth / 2, y: from.y + TeamGraph.nodeHeight))
                var path = Path()
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x, y: (start.y + linking.to.y) / 2))
                path.addLine(to: CGPoint(x: linking.to.x, y: (start.y + linking.to.y) / 2))
                path.addLine(to: linking.to)
                context.stroke(path, with: .color(Ledger.accent), style: StrokeStyle(lineWidth: Ledger.ruleStrong, dash: [5, 4]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func point(_ id: String) -> TeamGraph.Point? {
        id == Team.orchestratorID ? TeamGraph.orchestratorPoint : at[id]
    }

    /// A small triangle pointing down, its tip on the target's top edge.
    static func head(at tip: CGPoint) -> Path {
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - 4.5, y: tip.y - 7))
        path.addLine(to: CGPoint(x: tip.x + 4.5, y: tip.y - 7))
        path.closeSubpath()
        return path
    }
}

/// One node: the Action's two capitals in a square, the id in bold and the effort, then the Profile
/// with its model's family mark. The Orchestrator's is solid ink and does not move. The picked one
/// has a 3 pt accent edge and an accent frame; an unreachable one is framed in the failed red. A
/// drag moves it on the grid; a drag from the port under it draws a Hand-off to the node it ends on.
private struct NodeView: View {
    @ObservedObject var teams: TeamSettingsModel
    @ObservedObject var canvas: CanvasState
    let frame: CanvasFrame
    /// nil is the Orchestrator.
    let id: String?
    let point: TeamGraph.Point
    let mix: TeamMix
    let unreachable: Bool
    let picked: Bool
    let focused: Bool
    let pick: (String?) -> Void

    @StateObject private var hover = Flag()

    private var root: Bool { id == nil }
    private var width: CGFloat { CGFloat(TeamGraph.nodeWidth) }
    private var height: CGFloat { CGFloat(TeamGraph.nodeHeight) }

    var body: some View {
        let place = frame.place(point)
        let offset = id.flatMap { id in canvas.moving?.id == id ? canvas.moving?.by : nil } ?? .zero
        card
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) { port }
            .offset(x: place.x + offset.width, y: place.y + offset.height)
    }

    private var look: (title: String, line: String, effort: String, model: String, changed: Bool) {
        let form = teams.form
        guard let id, let member = form.member(id) else {
            let model = form.orchestratorModel.isEmpty ? teams.defaults.model : form.orchestratorModel
            let cli = teams.effectiveCli(form.orchestratorCli)
            // Its effort goes on the second line: "Orchestrator" leaves no room beside it.
            let runs = model.isEmpty ? "\(cli) · default" : TeamMix.shortModel(model)
            let effort = form.orchestratorEffort
            return ("Orchestrator", effort.isEmpty ? runs : "\(runs) · \(effort)", "", model, false)
        }
        let profile = teams.profile(named: member.profile)
        let model = form.resolve(.model, for: member, profile: profile, defaults: teams.defaults).value
        let effort = form.resolve(.effort, for: member, profile: profile, defaults: teams.defaults).value
        let line = model.isEmpty ? member.profile : "\(member.profile) · \(TeamMix.shortModel(model))"
        return (id, line, effort, model, teams.memberChanged(id))
    }

    private var card: some View {
        let look = look
        let action = id.flatMap { teams.form.member($0)?.action }
        let initials = root ? "OR" : ActionLook.initials(ActionLook.title(for: action ?? ""))
        let ink = root ? Ledger.paper : Ledger.ink
        return HStack(alignment: .center, spacing: 10) {
            Text(initials)
                .font(Ledger.monoFont(11, .bold))
                .foregroundStyle(root ? Ledger.ink : Ledger.ink)
                .frame(width: 30, height: 30)
                .background(root ? Ledger.paper : Ledger.paper)
                .overlay(Rectangle().strokeBorder(picked && !root ? Ledger.accent : (root ? Ledger.paper : Ledger.square),
                                                  lineWidth: Ledger.hairline))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(look.title)
                        .font(Ledger.font(13, .bold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if look.changed {
                        Rectangle().fill(Ledger.accent).frame(width: 6, height: 6)
                            .accessibilityLabel("Changed")
                    }
                    if !root { Text(look.effort.isEmpty ? "-" : look.effort)
                        .font(Ledger.monoFont(10))
                        .foregroundStyle(root ? Ledger.paper.opacity(0.75) : Ledger.ink3)
                        .lineLimit(1)
                        .fixedSize() }
                }
                HStack(spacing: 6) {
                    MixDot(index: mix.index(of: look.model), size: 6)
                    Text(look.line)
                        .font(Ledger.monoFont(10))
                        .foregroundStyle(root ? Ledger.paper.opacity(0.75) : Ledger.ink3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: height, alignment: .leading)
        .background(background)
        .overlay(Rectangle().strokeBorder(frameColor, lineWidth: picked || unreachable ? Ledger.ruleStrong : Ledger.hairline))
        .overlay(alignment: .leading) {
            if picked && !root { Rectangle().fill(Ledger.accent).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .onTapGesture { pick(id) }
        .onHover { hover.on = $0 }
        .gesture(moveGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([root ? "Orchestrator" : "\(ActionLook.title(for: action ?? "")) \(look.title)", look.line,
                             look.effort.isEmpty ? nil : "effort \(look.effort)",
                             unreachable ? "cannot be reached" : nil, look.changed ? "changed" : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { pick(id) }
    }

    private var background: Color {
        if root { return Ledger.ink }
        if unreachable { return Ledger.failWash }
        if picked { return focused ? Ledger.chosen : Ledger.paper }
        return hover.on ? Ledger.wash : Ledger.paper
    }

    private var frameColor: Color {
        if root { return picked ? Ledger.accent : Ledger.ink }
        if unreachable { return Ledger.fail }
        return picked ? Ledger.accent : Ledger.rule
    }

    /// The square under the node a Hand-off is drawn from.
    @ViewBuilder
    private var port: some View {
        if !teams.readOnly {
            Rectangle()
                .fill(root ? Ledger.ink : Ledger.paper)
                .overlay(Rectangle().strokeBorder(root ? Ledger.paper : Ledger.ink3, lineWidth: Ledger.hairline))
                .frame(width: 10, height: 10)
                .offset(y: 5)
                .opacity(hover.on || picked || canvas.linking != nil ? 1 : 0.35)
                .gesture(linkGesture)
                .help("Drag to another node to draw a Hand-off to it")
                .accessibilityHidden(true)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(CanvasBoard.space))
            .onChanged { value in
                guard let id, !teams.readOnly else { return }
                canvas.moving = (id, value.translation)
            }
            .onEnded { value in
                guard let id, !teams.readOnly else { return }
                canvas.moving = nil
                teams.moveNode(id, to: TeamGraph.Point(x: point.x + Int(value.translation.width),
                                                       y: point.y + Int(value.translation.height)))
            }
    }

    private var linkGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(CanvasBoard.space))
            .onChanged { value in
                canvas.linking = (id ?? Team.orchestratorID, value.location)
            }
            .onEnded { value in
                canvas.linking = nil
                let target = frame.point(at: value.location)
                let at = TeamGraph.positions(teams.form.members)
                let hit = teams.form.members.first { member in
                    guard let p = at[member.id] else { return false }
                    return target.x >= p.x && target.x <= p.x + TeamGraph.nodeWidth
                        && target.y >= p.y && target.y <= p.y + TeamGraph.nodeHeight
                }
                if let hit {
                    teams.connect(id ?? Team.orchestratorID, to: hit.id)
                } else {
                    teams.treeNotice = "End the line on the node that comes next."
                }
            }
    }
}

/// Fit frames the whole Team in the room the canvas has: the zoom that fits it, within 50% to 200%.
private struct FitRequest: View {
    @ObservedObject var canvas: CanvasState
    @ObservedObject var teams: TeamSettingsModel
    let room: CGSize
    let framed: () -> Void

    var body: some View {
        Color.clear.onChange(of: teams.fitRequest) {
            guard let zoom = CanvasState.fit(teams.form.members, in: room) else { return }
            canvas.zoom = zoom
            DispatchQueue.main.async(execute: framed)
        }
    }
}

/// The models the Orchestrator and the Members run on, by family, and the mark of each family.
struct TeamMix {
    let families: [(family: String, count: Int)]

    @MainActor
    init(teams: TeamSettingsModel) {
        let form = teams.form
        let lead = form.orchestratorModel.isEmpty ? teams.defaults.model : form.orchestratorModel
        let models = [lead] + form.members.map { member in
            form.resolve(.model, for: member, profile: teams.profile(named: member.profile), defaults: teams.defaults).value
        }
        families = ModelMix.tally(models)
    }

    /// The family's place in the mix: its colour in the bar and the dot on a node.
    func index(of model: String) -> Int {
        families.firstIndex { $0.family == ModelMix.family(model) } ?? 0
    }

    /// The accent, its deep shade, its soft tint, then greys.
    static func color(_ index: Int) -> Color {
        [Ledger.accent, SettingsLook.accentDeep, Ledger.marker, Ledger.ink3, Ledger.rule][min(index, 4)]
    }

    /// A model without its provider and Claude's prefix, its version in dots: "sonnet 5.5".
    static func shortModel(_ model: String) -> String {
        var name = model
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if name.hasPrefix("claude-") { name = String(name.dropFirst("claude-".count)) }
        let parts = name.split(separator: "-").map(String.init)
        guard parts.count > 1, parts.dropFirst().allSatisfy({ $0.allSatisfy { $0.isNumber || $0 == "." } }) else {
            return name
        }
        return parts[0] + " " + parts.dropFirst().joined(separator: ".")
    }
}

/// A family's mark: a small square in its colour; the soft tint is framed in the accent so it shows.
private struct MixDot: View {
    let index: Int
    var size: CGFloat = 7

    var body: some View {
        Rectangle()
            .fill(TeamMix.color(index))
            .overlay(Rectangle().strokeBorder(index == 2 ? Ledger.accent : .clear, lineWidth: 1))
            .frame(width: size, height: size)
    }
}

/// The Team's head: its name in condensed capitals with where it comes from, how many Members it
/// has, and the bar of the models they run on.
private struct TeamHead: View {
    @ObservedObject var teams: TeamSettingsModel
    let mix: TeamMix
    let compact: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: compact ? 14 : 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SettingsLabel("Team", size: 11)
                        .fixedSize()
                    badge
                }
                Text(teams.form.name.isEmpty ? "New Team" : teams.form.name)
                    .font(Ledger.display(40))
                    .textCase(.uppercase)
                    .foregroundStyle(Ledger.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityAddTraits(.isHeader)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: compact ? 14 : 22) {
                VStack(alignment: .leading, spacing: 2) {
                    SettingsLabel("Members", size: 11)
                    Text("\(teams.form.members.count)")
                        .font(Ledger.display(28))
                        .foregroundStyle(Ledger.ink)
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 6) {
                    SettingsLabel("Models", size: 11)
                    MixBar(mix: mix)
                    // Each family keeps its name whole; more than fit wrap onto a second line.
                    Text(mix.families.map { "\($0.family.capitalized)\u{00A0}\($0.count)" }.joined(separator: "   "))
                        .font(Ledger.monoFont(10))
                        .foregroundStyle(Ledger.ink3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: compact ? 150 : 200, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            // The counts keep their room; a long name scales down first.
            .fixedSize()
            .layoutPriority(2)
        }
        .padding(.horizontal, compact ? 20 : 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Ledger.ink).frame(height: Ledger.ruleStrong) }
    }

    /// Where the Team comes from, as Foundry's badge: solid ink for a saved Team, dashed for one not
    /// saved yet.
    private var badge: some View {
        let fresh = teams.form.isNew
        let title: String
        switch teams.team?.origin {
        case _ where fresh: title = "Not saved"
        case "shipped": title = "Shipped"
        case "repo": title = "This repo"
        default: title = "Yours"
        }
        return Text(title)
            .font(Ledger.monoFont(11, .bold))
            .tracking(0.88)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(fresh ? Ledger.ink3 : Ledger.desk)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(fresh ? Color.clear : Ledger.ink)
            .overlay {
                if fresh {
                    Rectangle().strokeBorder(Ledger.ink3, style: StrokeStyle(lineWidth: Ledger.ruleStrong, dash: [4, 3]))
                }
            }
            .fixedSize()
    }
}

/// The models as one 10 pt bar, a part per family as wide as its share, 2 pt apart.
private struct MixBar: View {
    let mix: TeamMix

    var body: some View {
        GeometryReader { proxy in
            let total = CGFloat(max(1, mix.families.reduce(0) { $0 + $1.count }))
            let room = proxy.size.width - CGFloat(max(0, mix.families.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(Array(mix.families.enumerated()), id: \.offset) { index, family in
                    Rectangle()
                        .fill(TeamMix.color(index))
                        .frame(width: room * CGFloat(family.count) / total)
                }
            }
        }
        .frame(height: 10)
    }
}

/// What the Add menus offer, in Foundry's popover (ui-ux/0125): the six Actions, each with its
/// initials as the canvas draws its node and what it does; the six shipped Profiles (each for the
/// Action it starts); then Custom, which asks for a Profile's name first.
@MainActor
enum AddEntries {
    static let width: CGFloat = 500

    static func menu(_ teams: TeamSettingsModel) -> FoundryMenu {
        let after = teams.member.map { "after \(ActionLook.title(for: $0.action)) \($0.id)" } ?? "after the Orchestrator"
        return FoundryMenu(label: "Add a Member", head: "Add a Member", detail: after, entries: all(teams))
    }

    static func all(_ teams: TeamSettingsModel) -> [FoundryMenuEntry] {
        let choices = AddChoice.all()
        var entries: [FoundryMenuEntry] = choices.filter { $0.kind == .action }.map { choice in
            .item(choice.title, note: Action.shipped.first { $0.id == choice.action }?.description,
                  icon: AnyView(Text(ActionLook.initials(choice.title)).font(Ledger.monoFont(11, .bold)))) {
                teams.perform(.add(choice.action))
            }
        }
        entries += [.rule, .label("Profiles")]
        entries += choices.filter { $0.kind == .worker }.map { choice in
            .item(choice.title, note: "for \(ActionLook.title(for: choice.action))") { teams.perform(.add(choice.action)) }
        }
        entries += [.rule, .item("Custom…", note: "names its Profile first") { teams.perform(.add(Action.custom)) }]
        return entries
    }
}

/// The keys that only pick or go, and the drags, at the foot of the More menu.
private struct KeysFoot: View {
    private static let keys = [("↑ ↓ ← →", "Pick the nearest node that way"), ("↩", "Rename"), ("A", "Add a Member"),
                               ("Esc", "Back to the sections")]
    private static let drags = ["A node, to move it on the grid", "From the square under a node to another, to draw a Hand-off"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Keys, while the canvas is picked")
            ForEach(Self.keys, id: \.0) { key, what in
                HStack(spacing: 10) {
                    Text(key)
                        .font(Ledger.monoFont(10, .bold))
                        .frame(width: 64, height: 22)
                        .overlay(Rectangle().strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
                    Text(what)
                }
                .accessibilityElement(children: .combine)
            }
            MonoLabel("Drag").padding(.top, 6)
            ForEach(Self.drags, id: \.self) { Text($0) }
            Text("The inspector's After list draws and removes Hand-offs too.")
                .foregroundStyle(Ledger.ink3)
        }
    }
}

/// The one line under the canvas: why the last command or drag was refused, else nothing.
private struct CanvasCaption: View {
    @ObservedObject var teams: TeamSettingsModel
    let pad: CGFloat

    var body: some View {
        let unreachable = TeamGraph.unreachable(teams.form.members).sorted()
        if let notice = teams.treeNotice ?? unreachable.first.map({ "\($0) can't be reached from the Orchestrator. Draw a Hand-off into it, or remove it." }) {
            Text(notice)
                .font(Ledger.font(13))
                .foregroundStyle(SettingsLook.problem)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, pad)
                .padding(.vertical, 8)
                .overlay(alignment: .top) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// The bar under the canvas: Add Member, the key of the two kinds of line, the zoom and Fit, and
/// the More menu with Duplicate, Remove and the keys (ui-ux/0144).
private struct CanvasBar: View {
    @ObservedObject var teams: TeamSettingsModel
    @ObservedObject var canvas: CanvasState
    let compact: Bool

    @StateObject private var addMenu = Flag()
    @StateObject private var moreMenu = Flag()

    var body: some View {
        HStack(spacing: 10) {
            Button { addMenu.on.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .heavy))
                    Text("Add Member")
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .heavy))
                }
            }
            .buttonStyle(.settings)
            .disabled(teams.readOnly)
            .foundryPopover(isPresented: $addMenu.on, width: AddEntries.width) { AddEntries.menu(teams) }
            .help("Add a Member after the picked one (a)")
            if !compact {
                LineKey(auto: false, title: "Hint")
                LineKey(auto: true, title: "Automatic")
            }
            Spacer(minLength: 0)
            Button { canvas.zoom(by: -0.25) } label: { Image(systemName: "minus") }
                .buttonStyle(.settings)
                .keyboardShortcut("-", modifiers: .command)
                .disabled(canvas.zoom <= CanvasState.zooms.lowerBound)
                .accessibilityLabel("Zoom out")
            Text("\(Int((canvas.zoom * 100).rounded()))%")
                .font(Ledger.monoFont(11))
                .foregroundStyle(Ledger.ink3)
                .frame(width: 40)
            Button { canvas.zoom(by: 0.25) } label: { Image(systemName: "plus") }
                .buttonStyle(.settings)
                .keyboardShortcut("=", modifiers: .command)
                .disabled(canvas.zoom >= CanvasState.zooms.upperBound)
                .accessibilityLabel("Zoom in")
            Button("Fit") { teams.fitRequest += 1 }
                .buttonStyle(.settings)
                .help("Frame the whole Team")
            Button { moreMenu.on.toggle() } label: {
                HStack(spacing: 4.5) {
                    ForEach(0..<3, id: \.self) { _ in Rectangle().frame(width: 3, height: 3) }
                }
                .foregroundStyle(Ledger.ink)
                .frame(width: 34, height: 34)
                .overlay(Rectangle().strokeBorder(Ledger.rule, lineWidth: Ledger.ruleStrong))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foundryPopover(isPresented: $moreMenu.on, width: 380, trailing: true) { more }
            .help("More: duplicate, remove, and the keys")
            .accessibilityLabel("More: duplicate, remove, and keyboard shortcuts")
        }
        .padding(.horizontal, compact ? 20 : 28)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
    }

    /// Duplicate and Remove with their keys beside them, so a key is never the only way (ui-ux/0008),
    /// then the keys that only pick or go and the drags, told in the foot.
    private var more: FoundryMenu {
        let canEdit = !teams.readOnly && teams.member != nil
        let entries: [FoundryMenuEntry] = [
            .item("Duplicate", key: "D", enabled: canEdit) { teams.perform(.duplicate) },
            .item("Remove", key: "⌫", enabled: canEdit) { teams.perform(.remove) },
        ]
        return FoundryMenu(label: "More", head: "Member", detail: teams.member.map { ActionLook.title(for: $0.action) },
                           entries: entries, foot: AnyView(KeysFoot()))
    }
}

/// One kind of line in the bar's key: a short stretch of it and its name.
private struct LineKey: View {
    let auto: Bool
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(auto ? Ledger.accent : Ledger.rule)
                .frame(width: 24, height: auto ? Ledger.ruleStrong : Ledger.hairline)
            Text(title)
                .font(Ledger.monoFont(10, .bold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Ledger.ink3)
        }
        .accessibilityElement(children: .combine)
    }
}

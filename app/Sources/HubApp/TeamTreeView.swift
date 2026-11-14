import AppKit
import HubCore
import SwiftUI
import UniformTypeIdentifiers

/// What the tree's keys and buttons do to the Team's draft (ui-ux/0102). The decisions are
/// `TeamTreeEditing`'s; this carries them out and shows the one line when one is refused.
extension TeamSettingsModel {
    func perform(_ command: TreeCommand) {
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
        case .leave:
            pageFocusRequest += 1
        case .add(Action.custom):
            let parent = member
            if let reason = TeamTreeEditing.addRefusal(Action.custom, under: parent, in: form.members, hasProfile: true) {
                treeNotice = reason
            } else {
                treeNotice = nil
                newCustomWorker(under: parent?.id)
            }
        default:
            var edit = TeamTreeEditing.apply(command, to: form.members, selected: selectedMember)
            if let count = edit.asksToRemove, let id = selectedMember {
                guard confirmRemoval(of: id, count: count) else { return }
                edit = TeamTreeEditing.apply(command, to: form.members, selected: selectedMember, confirmed: true)
            }
            form.members = edit.members
            selectedMember = edit.selected
            treeNotice = edit.notice
            memberNotice = nil
        }
    }

    /// Why nothing can be dropped on Echo's own Teams.
    static let readOnlyReason = "Echo's own Team. Duplicate it to change it."

    /// What dropping `payload` at `spot` would do to the draft, for the line or fill that shows it
    /// and for the drop itself; a Team that cannot be edited refuses every drop. Over the
    /// Orchestrator row the mark is the Orchestrator, not the end of level 1.
    func judge(_ payload: DropPayload, at spot: DropSpot, onOrchestrator: Bool = false) -> DropOutcome {
        var outcome = TeamTreeDrop.evaluate(payload, at: spot, in: form.members)
        if onOrchestrator { outcome.mark = .root }
        if readOnly { outcome.refusal = Self.readOnlyReason }
        return outcome
    }

    /// Carries out a drop of the string `text` (the Member or chip a drag carried) at `spot`: it
    /// changes the draft, or says in one line under the tree why it cannot.
    func drop(_ text: String?, at spot: DropSpot) {
        guard let text, let payload = DropPayload.parse(text) else {
            treeNotice = "Drop a Member row or a chip from the palette here."
            return
        }
        carryOut(judge(payload, at: spot))
    }

    /// Moves the Member under `parent` (level 1 when nil): the Move to menu, for what a drag does.
    func move(_ id: String, under parent: String?) {
        var outcome = TeamTreeDrop.move(id, under: parent, in: form.members)
        if readOnly { outcome.refusal = Self.readOnlyReason }
        carryOut(outcome)
    }

    private func carryOut(_ outcome: DropOutcome) {
        if let reason = outcome.refusal {
            treeNotice = reason
            return
        }
        if outcome.asksForProfile {
            treeNotice = nil
            newCustomWorker(under: outcome.parent, placed: outcome.placement)
            return
        }
        form.members = outcome.members
        selectedMember = outcome.selected
        treeNotice = nil
        memberNotice = nil
    }

    /// Asks before a Member goes with the Members under it.
    private func confirmRemoval(of id: String, count: Int) -> Bool {
        let below = count - 1
        let alert = NSAlert()
        alert.messageText = "Remove \(id) and the \(below) \(below == 1 ? "Member" : "Members") under it?"
        alert.informativeText = "They go from this Team's draft. Revert brings them back until you save."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Where a drag over the tree would land and the heights of the rows, held outside the views
/// (no `@State` here): the row or line that shows the target follows `mark`.
@MainActor
final class TreeDragState: ObservableObject {
    @Published private(set) var mark: DropMark?
    /// The drop at `mark` is refused, so the line or fill shows that.
    @Published private(set) var refused = false
    /// What the drag in progress carries, told when it starts, so a drop can be judged as the
    /// pointer enters and not only when it is let go. A drag from outside has none until it drops.
    private(set) var dragging: DropPayload?
    /// The height of each Member's row, for the zones of a row.
    var heights: [String: CGFloat] = [:]
    /// The line under the tree is the drag's own, so it goes when the drag leaves.
    private var noticed = false

    func begin(_ payload: DropPayload) {
        dragging = payload
    }

    func show(_ mark: DropMark?, refused: Bool) {
        if self.mark != mark { self.mark = mark }
        if self.refused != refused { self.refused = refused }
    }

    /// The caption the drag put under the tree: shown while a refused drop is hovered.
    func notice(_ reason: String?, in teams: TeamSettingsModel) {
        if let reason {
            if teams.treeNotice != reason { teams.treeNotice = reason }
            noticed = true
        } else if noticed {
            teams.treeNotice = nil
            noticed = false
        }
    }

    /// The drag left the tree or was dropped.
    func end(in teams: TeamSettingsModel) {
        show(nil, refused: false)
        notice(nil, in: teams)
        dragging = nil
    }
}

/// Takes a drop on one Member's row, or on the Orchestrator and the empty space (`row` nil). The
/// zone under the pointer comes from `DropSpot`, the verdict from `TeamTreeDrop`; this reads the
/// pointer, draws the answer and hands the string to the model when it is let go.
@MainActor
struct TreeDropDelegate: DropDelegate {
    let teams: TeamSettingsModel
    let drag: TreeDragState
    /// The Member whose row this is; nil for the Orchestrator row and the space around the rows.
    let row: String?
    var onOrchestrator = false

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        _ = judge(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: judge(info) ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
        drag.show(nil, refused: false)
        drag.notice(nil, in: teams)
    }

    func performDrop(info: DropInfo) -> Bool {
        let spot = self.spot(info)
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            drag.end(in: teams)
            return false
        }
        drag.end(in: teams)
        let model = teams
        _ = provider.loadObject(ofClass: String.self) { text, _ in
            DispatchQueue.main.async { model.drop(text, at: spot) }
        }
        return true
    }

    private func spot(_ info: DropInfo) -> DropSpot {
        guard let row else { return .empty }
        return DropSpot.at(row: row, x: info.location.x, y: info.location.y, height: drag.heights[row] ?? 36)
    }

    /// Draws where the drop would land and, once it is known what is dragged, whether it may; a
    /// refusal is the caption. A drag whose payload is not known is let in and judged on the drop.
    private func judge(_ info: DropInfo) -> Bool {
        guard let payload = drag.dragging else {
            drag.show(nil, refused: teams.readOnly)
            drag.notice(teams.readOnly ? TeamSettingsModel.readOnlyReason : nil, in: teams)
            return !teams.readOnly
        }
        let outcome = teams.judge(payload, at: spot(info), onOrchestrator: onOrchestrator)
        drag.show(outcome.mark, refused: !outcome.isOK)
        drag.notice(outcome.refusal, in: teams)
        return outcome.isOK
    }
}

/// The Team's tree (ui-ux/0121): the Team's head with its Members and models, then the Orchestrator
/// at the root and its Members stepped in under it, one row each in fixed columns (Member and id,
/// Profile and model, effort), then the bar with Add Member and the More menu. The keys and drags of
/// ui-ux/0102 work as before. The rows are drawn from `TeamTree.rows`; the operations are
/// `TeamTreeEditing`'s.
struct TeamTreeColumn: View {
    @ObservedObject var teams: TeamSettingsModel
    @StateObject private var drag = TreeDragState()
    @FocusState private var focused: Bool

    private static let rootID = "orchestrator"

    var body: some View {
        // The column takes the width it is offered and lays its rows out for it, so a narrow window
        // never pushes the sections list or the inspector off the window.
        GeometryReader { proxy in
            column(width: proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func column(width: CGFloat) -> some View {
        let rows = TeamTree.rows(teams.form.members)
        let layout = TreeLayout(deepest: rows.map(\.depth).max() ?? 1, width: width)
        let mix = TreeMix(teams: teams)
        return VStack(alignment: .leading, spacing: 0) {
            TeamHead(teams: teams, mix: mix, layout: layout)
            TreeColumnHeads(layout: layout)
                .padding(.horizontal, layout.pad)
                .padding(.top, 14)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        OrchestratorRow(teams: teams, drag: drag, layout: layout, mix: mix,
                                        picked: teams.member == nil, focused: focused) { pick(nil) }
                            .id(Self.rootID)
                        ForEach(rows, id: \.member.id) { row in
                            MemberRow(teams: teams, drag: drag, row: row, layout: layout, mix: mix,
                                      picked: row.member.id == teams.selectedMember, focused: focused) {
                                pick(row.member.id)
                            }
                            .id(row.member.id)
                        }
                        if !teams.readOnly {
                            AddRow(teams: teams, layout: layout)
                        }
                        if teams.form.members.isEmpty {
                            Text("This Team has no Members yet. A Worker can still be started by its Profile's name.")
                                .font(Ledger.font(13))
                                .foregroundStyle(Ledger.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, layout.body)
                                .padding(.top, 10)
                        }
                    }
                    .padding(.horizontal, layout.pad)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .onChange(of: teams.selectedMember) { proxy.scrollTo(teams.selectedMember ?? Self.rootID) }
                // Over the space around the rows (a row's own drop takes the pointer over it): level 1, last.
                .onDrop(of: [.plainText], delegate: TreeDropDelegate(teams: teams, drag: drag, row: nil))
            }
            // The keys act only here, and a text field is never inside this view, so none is being edited.
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
            .onChange(of: focused) { teams.treeFocused = focused }
            .onChange(of: teams.treeFocusRequest) { focused = true }
            .onDisappear { teams.treeFocused = false }
            .accessibilityLabel("Team tree")
            TreeCaption(teams: teams, pad: layout.pad)
            TreeBar(teams: teams, layout: layout)
        }
    }

    private func pick(_ id: String?) {
        teams.selectMember(id)
        focused = true
    }

    /// Up and Down are always the tree's while it has the keyboard, even at the ends, so they never
    /// reach the page's section keys; keys the tree does not own are left to the window.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let key = Self.key(of: press),
              let command = TreeKeys.command(for: key, modifiers: Self.modifiers(of: press.modifiers)) else {
            return .ignored
        }
        teams.perform(command)
        return .handled
    }

    private static func key(of press: KeyPress) -> TreeKey? {
        switch press.key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        case .return: .enter
        case .delete, .deleteForward: .delete
        default: press.characters.isEmpty ? nil : .character(press.characters)
        }
    }

    private static func modifiers(of flags: EventModifiers) -> TreeModifiers {
        var out: TreeModifiers = []
        if flags.contains(.option) { out.insert(.option) }
        if flags.contains(.command) { out.insert(.command) }
        if flags.contains(.control) { out.insert(.control) }
        if flags.contains(.shift) { out.insert(.shift) }
        return out
    }
}

/// Where the parts of a row sit: a node steps 30 pt right per level, and the text columns start at
/// one place for every row, after the deepest node. Under 600 pt wide the margins and the Profile
/// and effort columns narrow, so the Member's name keeps its room.
struct TreeLayout {
    static let node: CGFloat = 32
    static let gap: CGFloat = 12
    /// The deepest level shown; the columns make room for its node.
    let deepest: Int
    let width: CGFloat

    var compact: Bool { width < 600 }
    var pad: CGFloat { compact ? 20 : 28 }
    var profile: CGFloat { compact ? 136 : 150 }
    var effort: CGFloat { compact ? 48 : 74 }
    var step: CGFloat { compact ? 22 : 30 }

    /// Where the text columns start: 106 pt, as Foundry's tree has it, until a third level needs more.
    var body: CGFloat { Self.node + (compact ? 10 : 14) + step * CGFloat(max(2, deepest)) }

    func indent(_ depth: Int) -> CGFloat { step * CGFloat(depth) }
}

/// The models the Orchestrator and the Members run on, by family, and the mark of each family.
struct TreeMix {
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

    /// The family's place in the mix: its colour in the bar and the dot in a row.
    func index(of model: String) -> Int {
        families.firstIndex { $0.family == ModelMix.family(model) } ?? 0
    }

    /// The accent, its deep shade, its soft tint, then greys.
    static func color(_ index: Int) -> Color {
        [Ledger.accent, SettingsLook.accentDeep, Ledger.marker, Ledger.ink3, Ledger.rule][min(index, 4)]
    }
}

/// A family's mark: a 7 pt square in its colour; the soft tint is framed in the accent so it shows.
private struct MixDot: View {
    let index: Int
    var size: CGFloat = 7

    var body: some View {
        Rectangle()
            .fill(TreeMix.color(index))
            .overlay(Rectangle().strokeBorder(index == 2 ? Ledger.accent : .clear, lineWidth: 1))
            .frame(width: size, height: size)
    }
}

/// The Team's head: its name in condensed capitals with where it comes from, how many Members it
/// has, and the bar of the models they run on.
private struct TeamHead: View {
    @ObservedObject var teams: TeamSettingsModel
    let mix: TreeMix
    let layout: TreeLayout

    var body: some View {
        HStack(alignment: .bottom, spacing: layout.compact ? 14 : 20) {
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
            HStack(alignment: .top, spacing: layout.compact ? 14 : 22) {
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
                    HStack(spacing: 10) {
                        ForEach(mix.families, id: \.family) { family in
                            Text("\(family.family.capitalized) \(family.count)")
                        }
                    }
                    .font(Ledger.monoFont(10))
                    .foregroundStyle(Ledger.ink3)
                    .lineLimit(1)
                }
                .frame(width: layout.compact ? 150 : 200, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            // The counts keep their room; a long name scales down first.
            .fixedSize()
            .layoutPriority(2)
        }
        .padding(.horizontal, layout.pad)
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
    let mix: TreeMix

    var body: some View {
        GeometryReader { proxy in
            let total = CGFloat(max(1, mix.families.reduce(0) { $0 + $1.count }))
            let room = proxy.size.width - CGFloat(max(0, mix.families.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(Array(mix.families.enumerated()), id: \.offset) { index, family in
                    Rectangle()
                        .fill(TreeMix.color(index))
                        .frame(width: room * CGFloat(family.count) / total)
                }
            }
        }
        .frame(height: 10)
    }
}

/// The columns' names over the rows, in mono capitals.
private struct TreeColumnHeads: View {
    let layout: TreeLayout

    var body: some View {
        HStack(spacing: TreeLayout.gap) {
            Text("Member · id").frame(maxWidth: .infinity, alignment: .leading)
            Text("Profile · model").frame(width: layout.profile, alignment: .leading)
            Text("Effort").frame(width: layout.effort, alignment: .trailing)
        }
        .font(Ledger.monoFont(10, .bold))
        .tracking(1)
        .textCase(.uppercase)
        .foregroundStyle(Ledger.ink3)
        .lineLimit(1)
        .padding(.leading, layout.body)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }
}

/// The Orchestrator, at the root: picking it shows the Team's own fields. A drop on it is level 1.
private struct OrchestratorRow: View {
    @ObservedObject var teams: TeamSettingsModel
    @ObservedObject var drag: TreeDragState
    let layout: TreeLayout
    let mix: TreeMix
    let picked: Bool
    let focused: Bool
    let pick: () -> Void

    var body: some View {
        let form = teams.form
        let cli = teams.effectiveCli(form.orchestratorCli)
        let model = form.orchestratorModel.isEmpty ? teams.defaults.model : form.orchestratorModel
        TeamTreeRow(initials: ActionLook.initials("Orchestrator"), root: true, title: "Orchestrator", id: nil,
                pill: model.isEmpty ? "\(cli) · default" : TeamTreeRow.shortModel(model), mix: mix.index(of: model),
                effort: form.orchestratorEffort, changed: false, depth: 0, layout: layout,
                picked: picked, focused: focused,
                marked: drag.mark == .root ? DropLook.fill(refused: drag.refused) : nil, pick: pick)
            .dropLine(drag.mark, on: nil, refused: drag.refused)
            .onDrop(of: [.plainText], delegate: TreeDropDelegate(teams: teams, drag: drag, row: nil, onOrchestrator: true))
    }
}

/// A Member: its Action and id, its Profile and the model it runs on, its effort. It can be dragged,
/// and is dropped on at its top quarter, middle, bottom quarter or left edge.
private struct MemberRow: View {
    @ObservedObject var teams: TeamSettingsModel
    @ObservedObject var drag: TreeDragState
    let row: TeamTree.Row
    let layout: TreeLayout
    let mix: TreeMix
    let picked: Bool
    let focused: Bool
    let pick: () -> Void

    var body: some View {
        let member = row.member
        let id = member.id
        let profile = teams.profile(named: member.profile)
        let model = teams.form.resolve(.model, for: member, profile: profile, defaults: teams.defaults).value
        let effort = teams.form.resolve(.effort, for: member, profile: profile, defaults: teams.defaults).value
        let title = ActionLook.title(for: member.action)
        TeamTreeRow(initials: ActionLook.initials(title), root: false, title: title, id: id,
                pill: model.isEmpty ? member.profile : "\(member.profile) · \(ModelMix.family(model))",
                mix: mix.index(of: model), effort: effort, changed: teams.memberChanged(id),
                depth: row.depth, layout: layout, picked: picked, focused: focused,
                marked: drag.mark == .fill(id) ? DropLook.fill(refused: drag.refused) : nil, pick: pick)
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear { drag.heights[id] = geometry.size.height }
                    .onChange(of: geometry.size.height) { drag.heights[id] = geometry.size.height }
            })
            .dropLine(drag.mark, on: id, refused: drag.refused)
            .onDrag {
                drag.begin(.member(id))
                return NSItemProvider(object: DropPayload.member(id).text as NSString)
            }
            .onDrop(of: [.plainText], delegate: TreeDropDelegate(teams: teams, drag: drag, row: id))
            .contextMenu { MoveToMenu(teams: teams, id: id) }
    }
}

/// What a drop target looks like: fills only, no outline and no shadow.
private enum DropLook {
    static func fill(refused: Bool) -> Color { refused ? Ledger.failWash : Ledger.markerWash }
    static func line(refused: Bool) -> Color { refused ? Ledger.fail : Ledger.run }
}

extension View {
    /// The thin line above or below a row where a drop would land, when `mark` says so for `row`
    /// (nil for the Orchestrator's row, which is never the row of a line).
    fileprivate func dropLine(_ mark: DropMark?, on row: String?, refused: Bool) -> some View {
        modifier(DropLine(mark: mark, row: row, refused: refused))
    }
}

private struct DropLine: ViewModifier {
    let mark: DropMark?
    let row: String?
    let refused: Bool

    private var line: (below: Bool, depth: Int)? {
        if let row, case .line(let at, let below, let depth) = mark, at == row { return (below, depth) }
        return nil
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: line?.below == true ? .bottom : .top) {
            if let line {
                Rectangle()
                    .fill(DropLook.line(refused: refused))
                    .frame(height: 2)
                    .padding(.leading, CGFloat(line.depth) * 16 + 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// One row of the tree: a square node with two capitals, stepped in by depth, then the text columns
/// over a 1 pt rule. A Member's row starts with a small square under its parent's node, centred on
/// its own node: the accent when picked or hovered, grey otherwise; there is no spine (ui-ux/0124,
/// ui-ux/0127). The picked
/// row is the sunk grey with an accent node frame; while the tree has the keyboard its fill is the soft accent instead, so the
/// keyboard's place shows without an outline. A drag over it fills it with where the drop lands.
private struct TeamTreeRow: View {
    let initials: String
    let root: Bool
    let title: String
    let id: String?
    let pill: String
    let mix: Int
    let effort: String
    let changed: Bool
    let depth: Int
    let layout: TreeLayout
    let picked: Bool
    let focused: Bool
    /// The fill a drag over this row gives it, which wins over the picked fill.
    var marked: Color?
    let pick: () -> Void

    /// A Member's square sits 12 pt in from its parent's node, centred on its own node's line.
    static let markerInset: CGFloat = 12

    /// A model without its provider and Claude's prefix: "sonnet-5-5".
    static func shortModel(_ model: String) -> String {
        var name = model
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        return name.hasPrefix("claude-") ? String(name.dropFirst("claude-".count)) : name
    }

    var body: some View {
        Button(action: pick) {
            HStack(alignment: .top, spacing: 0) {
                node
                    .padding(.leading, layout.indent(depth))
                    .frame(width: layout.body, alignment: .leading)
                HStack(spacing: TreeLayout.gap) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title)
                            .font(Ledger.font(15, .bold))
                            .foregroundStyle(Ledger.ink)
                            .lineLimit(1)
                            .layoutPriority(2)
                        if let id {
                            Text(id)
                                .font(Ledger.monoFont(11))
                                .foregroundStyle(Ledger.ink3)
                                .lineLimit(1)
                        }
                        if changed && layout.compact {
                            Rectangle().fill(Ledger.accent).frame(width: 7, height: 7)
                                .layoutPriority(2)
                        } else if changed {
                            Text("Changed")
                                .font(Ledger.monoFont(10, .bold))
                                .tracking(1)
                                .textCase(.uppercase)
                                .foregroundStyle(Ledger.markerInk)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Ledger.marker)
                                .padding(.leading, 2)
                                .fixedSize()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        MixDot(index: mix)
                        Text(pill)
                            .font(Ledger.monoFont(11))
                            .foregroundStyle(Ledger.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: layout.profile, height: 24, alignment: .leading)
                    .overlay(Rectangle().strokeBorder(picked ? Ledger.ink : Ledger.rule, lineWidth: Ledger.hairline))
                    Text(effort.isEmpty ? "-" : effort)
                        .font(Ledger.monoFont(11))
                        .foregroundStyle(picked ? Ledger.ink : Ledger.ink3)
                        .lineLimit(1)
                        .frame(width: layout.effort, alignment: .trailing)
                }
                .padding(.top, 4)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(picked ? .clear : Ledger.rule).frame(height: Ledger.hairline)
                }
            }
            .padding(.vertical, 10)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(alignment: .topLeading) {
                if !root {
                    ListMarker(picked: picked)
                        .offset(x: layout.indent(depth - 1) + Self.markerInset,
                                y: 10 + (TreeLayout.node - ListMarker.size) / 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowHover()
        .accessibilityLabel([title, id, pill, effort.isEmpty ? nil : "effort \(effort)", changed ? "changed" : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private var node: some View {
        Text(initials)
            .font(Ledger.monoFont(10, .bold))
            .foregroundStyle(root ? Ledger.paper : Ledger.ink)
            .frame(width: TreeLayout.node, height: TreeLayout.node)
            .background(root ? Ledger.ink : Ledger.paper)
            .overlay(Rectangle().strokeBorder(picked && !root ? Ledger.accent : Ledger.ink, lineWidth: Ledger.ruleStrong))
    }

    private var background: Color {
        if let marked { return marked }
        guard picked else { return .clear }
        return focused ? Ledger.chosen : Ledger.selected
    }
}

/// The row after the last: a grey square, a dashed node and "Add a Member under …", which opens
/// the Add menu.
private struct AddRow: View {
    @ObservedObject var teams: TeamSettingsModel
    let layout: TreeLayout

    @StateObject private var menu = Flag()

    var body: some View {
        Button { menu.on.toggle() } label: {
            HStack(spacing: 14) {
                Text("+")
                    .font(Ledger.monoFont(14, .bold))
                    .foregroundStyle(Ledger.ink3)
                    .frame(width: TreeLayout.node, height: TreeLayout.node)
                    .background(Ledger.paper)
                    .overlay(Rectangle().strokeBorder(Ledger.ink3, style: StrokeStyle(lineWidth: Ledger.ruleStrong, dash: [4, 3])))
                Text("Add a Member under \(teams.member.map { ActionLook.title(for: $0.action) } ?? "the Orchestrator")")
                    .font(Ledger.font(14))
                    .foregroundStyle(Ledger.ink3)
                Spacer(minLength: 0)
            }
            .padding(.leading, layout.indent(1))
            .padding(.top, 8)
            // Like a level 1 Member's, its square sits under the Orchestrator's node.
            .overlay(alignment: .topLeading) {
                ListMarker(picked: false)
                    .offset(x: TeamTreeRow.markerInset, y: 8 + (TreeLayout.node - ListMarker.size) / 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowHover()
        .foundryPopover(isPresented: $menu.on, width: AddEntries.width) { AddEntries.menu(teams) }
        .help("Add a Member under the picked one (a)")
    }
}

/// What the Add menus offer, in Foundry's popover (ui-ux/0125): the six Actions, each with its
/// initials in the framed square as the tree draws its node and what it does; the six shipped
/// Profiles (each for the Action it starts); then Custom, which asks for a Profile's name first.
@MainActor
enum AddEntries {
    static let width: CGFloat = 500

    static func menu(_ teams: TeamSettingsModel) -> FoundryMenu {
        let under = teams.member.map { "under \(ActionLook.title(for: $0.action)) \($0.id)" } ?? "under the Orchestrator"
        return FoundryMenu(label: "Add a Member", head: "Add a Member", detail: under, entries: all(teams))
    }

    static func all(_ teams: TeamSettingsModel) -> [FoundryMenuEntry] {
        let chips = Palette.chips()
        var entries: [FoundryMenuEntry] = chips.filter { $0.kind == .action }.map { chip in
            .item(chip.title, note: Action.shipped.first { $0.id == chip.action }?.description,
                  icon: AnyView(Text(ActionLook.initials(chip.title)).font(Ledger.monoFont(11, .bold)))) {
                teams.perform(.add(chip.action))
            }
        }
        entries += [.rule, .label("Profiles")]
        entries += chips.filter { $0.kind == .worker }.map { chip in
            .item(chip.title, note: "for \(ActionLook.title(for: chip.action))") { teams.perform(.add(chip.action)) }
        }
        entries += [.rule, .item("Custom…", note: "names its Profile first") { teams.perform(.add(Action.custom)) }]
        return entries
    }
}

/// "Move to…" in a row's context menu: the Members the Member may go under, and level 1. It does
/// what a drop on a Member does, so a move never needs a drag (ui-ux/0008); the More menu under the
/// tree has the same list for the picked Member.
private struct MoveToMenu: View {
    @ObservedObject var teams: TeamSettingsModel
    let id: String

    var body: some View {
        let places = TeamTreeDrop.moveDestinations(of: id, in: teams.form.members)
        Menu("Move to…") {
            ForEach(places, id: \.self) { parent in
                Button(Self.title(of: parent, in: teams.form)) { teams.move(id, under: parent) }
            }
        }
        .disabled(teams.readOnly || places.isEmpty)
    }

    static func title(of parent: String?, in form: TeamForm) -> String {
        guard let parent, let member = form.member(parent) else { return "Level 1, under the Orchestrator" }
        return "Under \(ActionLook.title(for: member.action)) \(member.id)"
    }
}

/// The keys that only pick or go, and the drags, at the foot of the More menu.
private struct KeysFoot: View {
    private static let keys = [("↑ ↓", "Pick the row above or below"), ("↩", "Rename"), ("A", "Add a Member"),
                               ("←", "Back to the sections")]
    private static let drags = ["Onto a Member to put it under it", "Between rows to put it there",
                                "To the left edge for level 1"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Keys, while the tree is picked")
            ForEach(Self.keys, id: \.0) { key, what in
                HStack(spacing: 10) {
                    Text(key)
                        .font(Ledger.monoFont(10, .bold))
                        .frame(width: 40, height: 22)
                        .overlay(Rectangle().strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
                    Text(what)
                }
                .accessibilityElement(children: .combine)
            }
            MonoLabel("Drag a row").padding(.top, 6)
            ForEach(Self.drags, id: \.self) { Text($0) }
        }
    }
}

/// The one line under the tree: why the last command or drop was refused, else nothing.
private struct TreeCaption: View {
    @ObservedObject var teams: TeamSettingsModel
    let pad: CGFloat

    var body: some View {
        if let notice = teams.treeNotice {
            Text(notice)
                .font(Ledger.font(13))
                .foregroundStyle(SettingsLook.problem)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, pad)
                .padding(.vertical, 8)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// The bar under the tree: Add Member, a line on what it adds, and the More menu with the moves
/// and the keys (ui-ux/0121); the keys themselves still work wherever the tree has the keyboard.
private struct TreeBar: View {
    @ObservedObject var teams: TeamSettingsModel
    let layout: TreeLayout

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
            .help("Add a Member under the picked one (a)")
            if !layout.compact {
                Text("Actions or Profiles, under the picked Member")
                    .font(Ledger.font(12))
                    .foregroundStyle(Ledger.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
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
            .help("More: duplicate, remove, move, and the keys")
            .accessibilityLabel("More: duplicate, remove, move, and keyboard shortcuts")
        }
        .padding(.horizontal, layout.pad)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
    }

    /// The moves of ui-ux/0102 with their keys beside them, so a drag or a key is never the only way
    /// (ui-ux/0008), the places Move To offers, then the keys that only pick or go and the drags,
    /// told in the foot.
    private var more: FoundryMenu {
        let canEdit = !teams.readOnly && teams.member != nil
        let id = teams.selectedMember ?? ""
        let places = canEdit ? TeamTreeDrop.moveDestinations(of: id, in: teams.form.members) : []
        var entries: [FoundryMenuEntry] = [
            .item("Duplicate", key: "D", enabled: canEdit) { teams.perform(.duplicate) },
            .item("Remove…", key: "⌫", enabled: canEdit) { teams.perform(.remove) },
            .rule,
            .item("Move Up", key: "⌥↑", enabled: canEdit) { teams.perform(.move(-1)) },
            .item("Move Down", key: "⌥↓", enabled: canEdit) { teams.perform(.move(1)) },
            .item("Indent", key: "⌥→", enabled: canEdit) { teams.perform(.indent) },
            .item("Outdent", key: "⌥←", enabled: canEdit) { teams.perform(.outdent) },
        ]
        if !places.isEmpty {
            entries += [.rule, .label("Move to")]
            entries += places.map { parent in
                .item(MoveToMenu.title(of: parent, in: teams.form)) { teams.move(id, under: parent) }
            }
        }
        return FoundryMenu(label: "More", head: "Member", detail: teams.member.map { ActionLook.title(for: $0.action) },
                           entries: entries, foot: AnyView(KeysFoot()))
    }

}

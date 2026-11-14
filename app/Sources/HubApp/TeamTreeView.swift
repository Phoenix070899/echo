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

/// The Team's tree: the Orchestrator at the root and its Members under it, indented by depth, with
/// the buttons and the keys of ui-ux/0102 and the one-line reason under it when a command is
/// refused. The rows are drawn from `TeamTree.rows`; the operations are `TeamTreeEditing`'s.
struct TeamTreeColumn: View {
    @ObservedObject var teams: TeamSettingsModel
    @StateObject private var drag = TreeDragState()
    @FocusState private var focused: Bool

    private static let rootID = "orchestrator"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TeamPalette(teams: teams, drag: drag)
            Rectangle()
                .fill(Ledger.rule)
                .frame(height: Ledger.hairline)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        OrchestratorRow(teams: teams, drag: drag, picked: teams.member == nil, focused: focused) { pick(nil) }
                            .id(Self.rootID)
                        ForEach(TeamTree.rows(teams.form.members), id: \.member.id) { row in
                            MemberRow(teams: teams, drag: drag, row: row, picked: row.member.id == teams.selectedMember, focused: focused) {
                                pick(row.member.id)
                            }
                            .id(row.member.id)
                        }
                        if teams.form.members.isEmpty {
                            Text("This Team has no Members yet. Add one below. A Worker can still be started by its Profile's name.")
                                .font(Ledger.font(11))
                                .foregroundStyle(Ledger.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                                .padding(.top, 6)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            TreeCaption(teams: teams)
            TreeButtons(teams: teams)
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

/// The Orchestrator, at the root: picking it shows the Team's own fields. A drop on it is level 1.
private struct OrchestratorRow: View {
    @ObservedObject var teams: TeamSettingsModel
    @ObservedObject var drag: TreeDragState
    let picked: Bool
    let focused: Bool
    let pick: () -> Void

    private var meta: String {
        let form = teams.form
        return ActionLook.meta(profile: teams.effectiveCli(form.orchestratorCli), model: form.orchestratorModel)
    }

    var body: some View {
        HStack(spacing: 0) {
            TreeRowButton(symbol: "person.crop.circle", title: "Orchestrator",
                          name: teams.form.name.isEmpty ? "New Team" : teams.form.name,
                          meta: meta, depth: 0, picked: picked, focused: focused,
                          marked: drag.mark == .root ? DropLook.fill(refused: drag.refused) : nil, pick: pick)
            if picked {
                AddMemberMenu(teams: teams, compact: true)
            }
        }
        .padding(.vertical, 1)
        .dropLine(drag.mark, on: nil, refused: drag.refused)
        .onDrop(of: [.plainText], delegate: TreeDropDelegate(teams: teams, drag: drag, row: nil, onOrchestrator: true))
    }
}

/// A Member: its Action's icon and title, its id, its Profile and the model it runs on. It can be
/// dragged, and is dropped on at its top quarter, middle, bottom quarter or left edge.
private struct MemberRow: View {
    @ObservedObject var teams: TeamSettingsModel
    @ObservedObject var drag: TreeDragState
    let row: TeamTree.Row
    let picked: Bool
    let focused: Bool
    let pick: () -> Void

    private var model: String {
        let profile = teams.profile(named: row.member.profile)
        return teams.form.resolve(.model, for: row.member, profile: profile, defaults: teams.defaults).value
    }

    var body: some View {
        let id = row.member.id
        HStack(spacing: 0) {
            TreeRowButton(symbol: ActionLook.symbol(for: row.member.action),
                          title: ActionLook.title(for: row.member.action), name: id,
                          meta: ActionLook.meta(profile: row.member.profile, model: model),
                          depth: row.depth, picked: picked, focused: focused,
                          marked: drag.mark == .fill(id) ? DropLook.fill(refused: drag.refused) : nil, pick: pick)
            if picked {
                AddMemberMenu(teams: teams, compact: true)
            }
        }
        .padding(.vertical, 1)
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

/// One row, flat: indented by depth, the picked one on the selected fill (the chosen fill while the
/// tree has the keyboard, so the keyboard's place shows without an outline or a shadow).
private struct TreeRowButton: View {
    let symbol: String
    let title: String
    let name: String
    let meta: String
    let depth: Int
    let picked: Bool
    let focused: Bool
    /// The fill a drag over this row gives it, which wins over the picked fill.
    var marked: Color?
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(Ledger.font(13))
                    .foregroundStyle(picked ? Ledger.ink : Ledger.ink2)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title)
                            .fontWeight(picked ? .medium : .regular)
                            .foregroundStyle(Ledger.ink)
                        Text(name)
                            .font(Ledger.font(12))
                            .foregroundStyle(Ledger.ink2)
                    }
                    .lineLimit(1)
                    Text(meta)
                        .font(Ledger.font(11))
                        .foregroundStyle(Ledger.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 16 + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(name), \(meta)")
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private var background: Color {
        if let marked { return marked }
        guard picked else { return .clear }
        return focused ? Ledger.chosen : Ledger.selected
    }
}

/// Adds a Member under the picked one, or at level 1 under the Orchestrator: the six Actions, then
/// Custom, which asks for a Profile's name first. `compact` is the "+" on the picked row.
private struct AddMemberMenu: View {
    @ObservedObject var teams: TeamSettingsModel
    var compact = false

    var body: some View {
        Menu {
            ForEach(Action.shipped) { action in
                Button { teams.perform(.add(action.id)) } label: {
                    Label(action.title, systemImage: ActionLook.symbol(for: action.id))
                }
            }
            Divider()
            Button { teams.perform(.add(Action.custom)) } label: {
                Label("Custom…", systemImage: ActionLook.symbol(for: Action.custom))
            }
        } label: {
            if compact {
                Image(systemName: "plus")
                    .font(Ledger.font(13, .medium))
                    .foregroundStyle(Ledger.ink2)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            } else {
                Text("Add Member")
                    .font(Ledger.font(14, .medium))
                    .foregroundStyle(Ledger.ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(Ledger.fill, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(teams.readOnly)
        .help("Add a Member under the picked one (a)")
        .accessibilityLabel(compact ? "Add a Member under this one" : "Add Member")
    }
}

/// "Move to…": the Members the Member may go under, and level 1, as a menu. It does what a drop on
/// a Member does, so a move never needs a drag (ui-ux/0008). As a button under the tree it moves
/// the picked Member; in a row's context menu, that row's.
private struct MoveToMenu: View {
    @ObservedObject var teams: TeamSettingsModel
    let id: String
    var asButton = false

    private var destinations: [String?] {
        TeamTreeDrop.moveDestinations(of: id, in: teams.form.members)
    }

    var body: some View {
        let places = destinations
        if asButton {
            Menu { items(places) } label: {
                Text("Move to…")
                    .font(Ledger.font(14, .medium))
                    .foregroundStyle(Ledger.ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(Ledger.fill, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(teams.readOnly || places.isEmpty)
            .help("Move the picked Member under another Member, or to level 1")
            .accessibilityLabel("Move to")
        } else {
            Menu("Move to…") { items(places) }
                .disabled(teams.readOnly || places.isEmpty)
        }
    }

    @ViewBuilder
    private func items(_ places: [String?]) -> some View {
        ForEach(places, id: \.self) { parent in
            Button(title(of: parent)) { teams.move(id, under: parent) }
        }
    }

    private func title(of parent: String?) -> String {
        guard let parent, let member = teams.form.member(parent) else { return "Level 1, under the Orchestrator" }
        return "Under \(ActionLook.title(for: member.action)) \(member.id)"
    }
}

/// The one line under the tree: why the last command or drop was refused, else nothing.
private struct TreeCaption: View {
    @ObservedObject var teams: TeamSettingsModel

    var body: some View {
        if let notice = teams.treeNotice {
            Text(notice)
                .font(Ledger.font(11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// The same moves as the keys, as buttons (ui-ux/0008): add, duplicate, remove, and the four moves.
private struct TreeButtons: View {
    @ObservedObject var teams: TeamSettingsModel

    private var noMember: Bool { teams.member == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Add Member needs no pick: under the Orchestrator it adds at level 1.
                AddMemberMenu(teams: teams)
                Button("Duplicate") { teams.perform(.duplicate) }
                    .help("Copy the picked Member and the Members under it (d)")
                    .disabled(teams.readOnly || noMember)
                Button("Remove") { teams.perform(.remove) }
                    .help("Remove the picked Member, asking first when it has Members under it (Delete)")
                    .disabled(teams.readOnly || noMember)
                Spacer(minLength: 0)
            }
            .buttonStyle(.ledger)
            HStack(spacing: 8) {
                moveButton("arrow.up", "Move up", "Move up among its siblings (Option Up)", .move(-1))
                moveButton("arrow.down", "Move down", "Move down among its siblings (Option Down)", .move(1))
                moveButton("increase.indent", "Indent", "Put it under the Member above (Option Right)", .indent)
                moveButton("decrease.indent", "Outdent", "Put it after its parent (Option Left)", .outdent)
                MoveToMenu(teams: teams, id: teams.selectedMember ?? "", asButton: true)
                Spacer(minLength: 0)
            }
            .buttonStyle(.ledger)
            .disabled(teams.readOnly || noMember)
            Text("Up and Down pick a row. Option with an arrow moves, indents or outdents it. Return renames, Delete removes, a adds, d duplicates. Left goes back to the sections. Drag a row onto another to put it under it, between two rows to put it there, or to the left edge to make it level 1. Move to… does the same without a drag.")
                .font(Ledger.font(11))
                .foregroundStyle(Ledger.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private func moveButton(_ symbol: String, _ label: String, _ help: String, _ command: TreeCommand) -> some View {
        Button { teams.perform(command) } label: {
            Image(systemName: symbol)
                .frame(width: 18)
        }
        .help(help)
        .accessibilityLabel(label)
    }
}

import AppKit
import HubCore
import SwiftUI

/// What the tree's keys and buttons do to the Team's draft (ui-ux/0102). The decisions are
/// `TeamTreeEditing`'s; this carries them out and shows the one line when one is refused.
extension TeamSettingsModel {
    func perform(_ command: TreeCommand) {
        if command.edits, readOnly {
            treeNotice = "Echo's own Team. Duplicate it to change it."
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

/// The Team's tree: the Orchestrator at the root and its Members under it, indented by depth, with
/// the buttons and the keys of ui-ux/0102 and the one-line reason under it when a command is
/// refused. The rows are drawn from `TeamTree.rows`; the operations are `TeamTreeEditing`'s.
struct TeamTreeColumn: View {
    @ObservedObject var teams: TeamSettingsModel
    @FocusState private var focused: Bool

    private static let rootID = "orchestrator"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        OrchestratorRow(teams: teams, picked: teams.member == nil, focused: focused) { pick(nil) }
                            .id(Self.rootID)
                        ForEach(TeamTree.rows(teams.form.members), id: \.member.id) { row in
                            MemberRow(teams: teams, row: row, picked: row.member.id == teams.selectedMember, focused: focused) {
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

/// The Orchestrator, at the root: picking it shows the Team's own fields.
private struct OrchestratorRow: View {
    @ObservedObject var teams: TeamSettingsModel
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
                          meta: meta, depth: 0, picked: picked, focused: focused, pick: pick)
            if picked {
                AddMemberMenu(teams: teams, compact: true)
            }
        }
    }
}

/// A Member: its Action's icon and title, its id, its Profile and the model it runs on.
private struct MemberRow: View {
    @ObservedObject var teams: TeamSettingsModel
    let row: TeamTree.Row
    let picked: Bool
    let focused: Bool
    let pick: () -> Void

    private var model: String {
        let profile = teams.profile(named: row.member.profile)
        return teams.form.resolve(.model, for: row.member, profile: profile, defaults: teams.defaults).value
    }

    var body: some View {
        HStack(spacing: 0) {
            TreeRowButton(symbol: ActionLook.symbol(for: row.member.action),
                          title: ActionLook.title(for: row.member.action), name: row.member.id,
                          meta: ActionLook.meta(profile: row.member.profile, model: model),
                          depth: row.depth, picked: picked, focused: focused, pick: pick)
            if picked {
                AddMemberMenu(teams: teams, compact: true)
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

/// The one line under the tree: why the last command was refused, else nothing.
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
                Spacer(minLength: 0)
            }
            .buttonStyle(.ledger)
            .disabled(teams.readOnly || noMember)
            Text("Up and Down pick a row. Option with an arrow moves, indents or outdents it. Return renames, Delete removes, a adds, d duplicates. Left goes back to the sections.")
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

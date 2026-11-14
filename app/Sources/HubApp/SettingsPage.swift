import HubCore
import SwiftUI

/// One part of Settings, listed down the page's left side.
enum SettingsSection: String, CaseIterable, Identifiable {
    case window, theme, background, font, multiplexer, teams, worktrees, memory, remote

    var id: String { rawValue }

    /// The section a name asks for; a name that was retired goes to the section that took its place
    /// (`agents` shows Teams).
    init?(named name: String) {
        self.init(rawValue: SettingsSectionName.canonical(name))
    }

    /// Teams fill the whole width beside the list (ui-ux/0101); every other section is one column.
    var fillsWidth: Bool { self == .teams }

    var title: String {
        switch self {
        case .window: "Window"
        case .theme: "Terminal Theme"
        case .background: "Background"
        case .font: "Font"
        case .multiplexer: "Multiplexer"
        case .teams: "Teams"
        case .worktrees: "Worktrees"
        case .memory: "Preferences and Lessons"
        case .remote: "Echo Remote"
        }
    }

    var icon: String {
        switch self {
        case .window: "macwindow"
        case .theme: "paintpalette"
        case .background: "photo"
        case .font: "textformat"
        case .multiplexer: "rectangle.split.2x1"
        case .teams: "person.3"
        case .worktrees: "arrow.triangle.branch"
        case .memory: "text.book.closed"
        case .remote: "iphone"
        }
    }
}

/// Settings filling the window below the title bar: the sections on the left, the picked one on
/// the right. Done or Esc goes back to the agents, which keep running meanwhile.
struct SettingsPage: View {
    let section: SettingsSection
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(Ledger.font(13, .semibold))
                    Spacer()
                    Button("Done") { model.hideSettings() }
                        .buttonStyle(.ledgerLink)
                        .help("Back to your agents (Esc)")
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                ForEach(SettingsSection.allCases) { item in
                    SectionRow(item: item, picked: item == section) { model.showSettingsSection(item) }
                }
                Spacer(minLength: 0)
            }
            // As wide as the ledger, so the panel beside it stays put when Settings open.
            .frame(width: model.ledgerWidth)
            .frame(maxHeight: .infinity)
            // The section's column sits in the middle of the space beside the list.
            VStack(alignment: .leading, spacing: 0) {
                Text(section.title)
                    .font(Ledger.font(20, .semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 4)
                SettingsView(section: section)
                    .id(section)
            }
            .frame(maxWidth: section.fillsWidth ? .infinity : 680)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ledgerSheet()
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        // The card that asks about unsaved edits takes the keyboard; the page takes it back after.
        .onReceive(model.teamSettings.$asking) { asking in
            if !asking { DispatchQueue.main.async { focused = true } }
        }
        .onKeyPress(.escape) {
            guard !model.teamSettings.asking else { return .ignored }
            model.hideSettings()
            return .handled
        }
        // The Team's tree takes the keyboard back from the page, and gives it back on Left.
        .onReceive(model.teamSettings.$pageFocusRequest.dropFirst()) { _ in focused = true }
        // SwiftUI hands a key to the focused view first, so a focused tree acts on Up and Down and
        // the page never sees them; the guard keeps the page out even if one is ignored (ui-ux/0102).
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            let teams = model.teamSettings
            guard SettingsKeys.pageTakesUpDown(treeFocused: teams.treeFocused, asking: teams.asking,
                                               hasModifiers: !press.modifiers.isEmpty) else { return .ignored }
            let all = SettingsSection.allCases
            let at = all.firstIndex(of: section) ?? 0
            let next = press.key == .downArrow ? min(at + 1, all.count - 1) : max(at - 1, 0)
            model.showSettingsSection(all[next])
            return .handled
        }
        // Right goes from the list of sections into the Team's tree, which has its own keys. Only
        // while the page itself has the keyboard: Right in a text field moves its caret.
        .onKeyPress(keys: [.rightArrow]) { press in
            let teams = model.teamSettings
            guard focused, SettingsKeys.pageEntersTree(treeShown: section == .teams && teams.pane == .team,
                                              treeFocused: teams.treeFocused, asking: teams.asking,
                                              hasModifiers: !press.modifiers.isEmpty) else { return .ignored }
            teams.treeFocusRequest += 1
            return .handled
        }
    }
}

/// A section in the list: flat and full width, the picked one on the selected fill.
private struct SectionRow: View {
    let item: SettingsSection
    let picked: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(Ledger.font(13))
                    .foregroundStyle(picked ? Ledger.ink : Ledger.ink2)
                    .frame(width: 20)
                Text(item.title)
                    .fontWeight(picked ? .medium : .regular)
                    .foregroundStyle(Ledger.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            // Claude's rows: a rounded fill inset from the column's edges, no bar.
            .background(picked ? Ledger.selected : .clear, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

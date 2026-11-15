import Foundry
import HubCore
import SwiftUI

/// One part of Settings, listed down the page's left side.
enum SettingsSection: String, CaseIterable, Identifiable {
    case window, theme, background, font, multiplexer, teams, providers, worktrees, memory, remote

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
        case .providers: "Providers"
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
        case .providers: "person.crop.circle"
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
                HStack(alignment: .firstTextBaseline) {
                    SettingsLabel("Settings", color: Ledger.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { model.hideSettings() }
                        .buttonStyle(DoneLinkStyle())
                        .help("Back to your agents (Esc)")
                }
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .padding(.top, 6)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(Ledger.ink).frame(height: Ledger.ruleStrong) }
                ForEach(SettingsSection.allCases) { item in
                    SectionRow(item: item, picked: item == section) { model.showSettingsSection(item) }
                }
                Spacer(minLength: 0)
            }
            // Foundry's 260 pt list (ui-ux/0120), narrower when the ledger is, so the Teams section's
            // three columns have room beside it.
            .frame(width: min(model.ledgerWidth, 260))
            .frame(maxHeight: .infinity)
            // Teams lay out their own head across the sheet (ui-ux/0101); every other section is a
            // page centred in the sheet (ui-ux/0045, ui-ux/0120).
            SettingsView(section: section)
                .id(section)
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
        .onReceive(model.$newTeamShown) { shown in
            if !shown { DispatchQueue.main.async { focused = true } }
        }
        .onKeyPress(.escape) {
            guard !model.teamSettings.asking, !model.newTeamShown else { return .ignored }
            model.hideSettings()
            return .handled
        }
        // The Team's tree takes the keyboard back from the page, and gives it back on Left.
        .onReceive(model.teamSettings.$pageFocusRequest.dropFirst()) { _ in focused = true }
        // SwiftUI hands a key to the focused view first, so a focused tree acts on Up and Down and
        // the page never sees them; the guard keeps the page out even if one is ignored (ui-ux/0102).
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            let teams = model.teamSettings
            guard SettingsKeys.pageTakesUpDown(treeFocused: teams.treeFocused,
                                               asking: teams.asking || model.newTeamShown,
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
                                              treeFocused: teams.treeFocused,
                                              asking: teams.asking || model.newTeamShown,
                                              hasModifiers: !press.modifiers.isEmpty) else { return .ignored }
            teams.treeFocusRequest += 1
            return .handled
        }
    }
}

/// A section in the list (ui-ux/0120): its number in mono and its name, 44 pt tall over a 1 pt rule;
/// the picked one in ink and bold on the sheet's grey; no row has a square (ui-ux/0132).
private struct SectionRow: View {
    let item: SettingsSection
    let picked: Bool
    let pick: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                Text(SettingsLook.number(item))
                    .font(Ledger.monoFont(11, .bold))
                    .tracking(0.66)
                    .foregroundStyle(picked ? Ledger.ink : Ledger.ink3)
                    .frame(width: 28, alignment: .leading)
                Text(item.title)
                    .font(Ledger.font(15, picked ? .bold : .regular))
                    .foregroundStyle(picked || hover.on ? Ledger.ink : Ledger.ink3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 15)
            .padding(.trailing, 12)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(picked || hover.on ? Ledger.paper : .clear)
            // The list has no squares, so the picked section shows by its fill alone (ui-ux/0132).
            .overlay(alignment: .bottom) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// Done: Archivo semibold in ink, underlined 2 pt in the accent, 4 pt below the text; hovered or
/// pressed, the muted ink, as Foundry's link.
private struct DoneLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @StateObject private var hover = Flag()

        var body: some View {
            configuration.label
                .font(Ledger.font(14, .semibold))
                .foregroundStyle(configuration.isPressed || hover.on ? Ledger.ink3 : Ledger.ink)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(Ledger.accent).frame(height: 2) }
                .contentShape(Rectangle())
                .onHover { hover.on = $0 }
        }
    }
}

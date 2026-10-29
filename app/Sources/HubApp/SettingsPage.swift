import HubCore
import SwiftUI

/// One part of Settings, listed down the page's left side.
enum SettingsSection: String, CaseIterable, Identifiable {
    case window, theme, background, font, multiplexer, agents, worktrees, memory, remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .window: "Window"
        case .theme: "Terminal Theme"
        case .background: "Background"
        case .font: "Font"
        case .multiplexer: "Multiplexer"
        case .agents: "Agents"
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
        case .agents: "person.2"
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
                .background(Ledger.band)
                ForEach(SettingsSection.allCases) { item in
                    SectionRow(item: item, picked: item == section) { model.settingsSection = item }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 232)
            .frame(maxHeight: .infinity)
            .ledgerSheet()
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
            .frame(maxWidth: 680)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ledgerSheet()
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            model.hideSettings()
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            let all = SettingsSection.allCases
            let at = all.firstIndex(of: section) ?? 0
            let next = press.key == .downArrow ? min(at + 1, all.count - 1) : max(at - 1, 0)
            model.settingsSection = all[next]
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
            // Lanh's rows: a rounded fill inset from the column's edges, no bar.
            .background(picked ? Ledger.selected : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

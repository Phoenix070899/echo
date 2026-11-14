import HubCore
import SwiftUI

/// Echo's own New session menu, opened under the ledger's New session button (ui-ux/0113): a sheet
/// in a 2 pt ink frame casting a hard ink offset, with an Orchestrator and a Terminal, each with
/// what it does and its shortcut, and a way to start in another repo. ↑ ↓ pick, Return starts,
/// Esc or a click outside closes. Fan Out a Task stays in the File menu and Quick open.
struct NewSessionPopup: View {
    @EnvironmentObject private var model: AppModel
    /// The New session button's frame, in this view's space.
    let anchor: CGRect
    @StateObject private var pick = MenuPick()
    @FocusState private var focused: Bool

    private struct Option {
        let kind: Agent.Kind
        let title: String
        let detail: String
        let key: String
        let enabled: Bool
    }

    private var options: [Option] {
        [Option(kind: .orchestrator, title: "Orchestrator", detail: "Hands Tasks to Workers and reports back", key: "⌘N", enabled: true),
         Option(kind: .terminal, title: "Terminal", detail: "A plain shell in the repo, in your multiplexer", key: "⇧⌘N",
                enabled: model.selectedRepo != nil)]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            card
                .frame(width: 392)
                .offset(x: anchor.minX, y: anchor.maxY + 16)
        }
        .onAppear {
            pick.index = 0
            DispatchQueue.main.async { focused = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                MonoLabel(repoName.map { "Start in \($0)" } ?? "New session")
                Spacer(minLength: 8)
                if let branch {
                    Text(branch).font(Ledger.monoFont(11)).foregroundStyle(Ledger.ink3).lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rule() }
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                row(option, on: index == pick.index)
                    .onHover { if $0 { pick.index = index } }
            }
            HStack(spacing: 4) {
                Text("In another repo?").foregroundStyle(Ledger.ink3)
                Button("Choose a repo…") {
                    close()
                    model.showNewSession(repo: nil, kind: .orchestrator)
                }
                .buttonStyle(.ledgerLink)
                .font(Ledger.font(12))
            }
            .font(Ledger.font(12))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rule() }
        }
        .background(Ledger.paper)
        .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
        // A hard ink block, not a blur: Foundry's raised sheet (ui-ux/0113).
        .background(Rectangle().fill(Ledger.cast).offset(x: 6, y: 6))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.downArrow) { pick.index = min(pick.index + 1, options.count - 1); return .handled }
        .onKeyPress(.upArrow) { pick.index = max(pick.index - 1, 0); return .handled }
        .onKeyPress(.return) { start(options[pick.index]); return .handled }
        .onExitCommand(perform: close)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New session")
    }

    private func row(_ option: Option, on: Bool) -> some View {
        Button { start(option) } label: {
            HStack(spacing: 14) {
                AgentGlyph(kind: option.kind, size: 16)
                    .foregroundStyle(Ledger.ink)
                    .frame(width: 36, height: 36)
                    .background(Ledger.paper)
                    .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
                VStack(alignment: .leading, spacing: 0) {
                    Text(option.title).font(Ledger.font(15, .bold)).foregroundStyle(Ledger.ink)
                    Text(option.detail).font(Ledger.font(13)).foregroundStyle(Ledger.ink3).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(option.key)
                    .font(Ledger.monoFont(10, .bold))
                    .foregroundStyle(Ledger.ink3)
                    .frame(width: 40, height: 22)
                    .overlay(Rectangle().strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on && option.enabled ? Ledger.selected : Color.clear)
            .overlay(alignment: .leading) {
                if on && option.enabled { Rectangle().fill(Ledger.accent).frame(width: 3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!option.enabled)
        .opacity(option.enabled ? 1 : 0.45)
    }

    private var repoName: String? {
        model.selectedRepo.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// The branch the selected agent or Worker is on, when Echo knows it.
    private var branch: String? {
        switch model.selection {
        case .agent(let repo, let id)?:
            let agent = model.agents(repo).first { $0.id == id }
            return agent?.head ?? agent?.branch
        case .worker(let repo, let id)?:
            return model.snapshot(repo).workers.first { $0.id == id }?.branch
        case nil:
            return nil
        }
    }

    private func start(_ option: Option) {
        guard option.enabled else { return }
        close()
        if option.kind == .terminal {
            model.openTerminal()
        } else {
            model.showNewSession(repo: model.selectedRepo, kind: .orchestrator)
        }
    }

    private func close() {
        model.newSessionMenuShown = false
    }
}

final class MenuPick: ObservableObject {
    @Published var index = 0
}

/// A 1 pt rule across its container.
struct Rule: View {
    var body: some View {
        Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline)
    }
}

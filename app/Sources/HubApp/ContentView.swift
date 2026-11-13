import AppKit
import HubCore
import SwiftUI

/// The Echo window: one tab per repo across the top, the ledger on the left (one group per
/// agent), and one terminal (or a Final Report) on the right. The ledger is how you move between
/// a repo's Orchestrators, its Claude Code sessions, and their Workers.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            if model.daemonDown {
                DisconnectedBanner()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else if let error = model.error {
                ErrorBanner(text: error)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else if let notice = model.notice {
                NoticeBanner(text: notice)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
            if let section = model.settingsSection {
                SettingsPage(section: section)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                agents
            }
        }
        .font(Ledger.font(13))
        .foregroundStyle(Ledger.ink)
        .tint(Ledger.run)
        .background(Ledger.desk)
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if model.newSession != nil {
                NewSessionModal()
            } else if let agent = model.renaming {
                RenameModal(agent: agent)
            } else if model.quickOpenShown {
                QuickOpen()
            } else if model.fanOutShown {
                FanOutModal()
            }
        }
        .confirmationDialog(closeTitle, isPresented: closingShown, presenting: model.closing) { agent in
            Button("Close \(agent.kindName)", role: .destructive) {
                model.forgetAgent(agent.id)
            }
        } message: { agent in
            Text(agent.live
                 ? "It stops now and leaves the ledger. Echo cannot start it again."
                 : "It leaves the ledger. Echo cannot start it again.")
        }
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
        .background(TrafficLightInset(barHeight: TitleBar.height))
    }

    /// The ledger, the agent or Worker shown, and its files.
    private var agents: some View {
        GeometryReader { geo in
            let showFiles = model.filesShown && model.selectedCheckout != nil
            // The ledger's resizer (or the rail's gap), the Files resizer, and the side padding.
            let widths = ColumnLayout.fit(
                total: geo.size.width, fixed: 24 + 12 + (showFiles ? 12 : 0),
                ledger: model.ledgerCollapsed ? 48 : model.ledgerWidth, files: showFiles ? model.filesWidth : nil,
                ledgerMin: model.ledgerCollapsed ? 48 : 300)
            HStack(alignment: .top, spacing: 0) {
                if model.ledgerCollapsed {
                    LedgerRail()
                        .frame(width: 48)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Color.clear.frame(width: 12)
                } else {
                    LedgerColumn()
                        .clippedToOffer()
                        .frame(width: widths.ledger)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    ColumnResizer(width: $model.ledgerWidth, range: 300...640, grows: .right, fallback: 392)
                }
                MainPanel()
                    .clippedToOffer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showFiles, let root = model.selectedCheckout {
                    ColumnResizer(width: $model.filesWidth, range: 220...600, grows: .left, fallback: 280)
                    FilesColumn(root: root)
                        .frame(width: widths.files ?? model.filesWidth)
                        .frame(maxHeight: .infinity)
                        .ledgerSheet()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var closeTitle: String {
        model.closing.map { "Close \($0.displayName)?" } ?? ""
    }

    private var closingShown: Binding<Bool> {
        Binding(get: { model.closing != nil }, set: { if !$0 { model.closing = nil } })
    }
}

// MARK: - Title bar and repo tabs

/// The top bar beside the traffic lights: Echo's mark and name, search in the middle, then how
/// many Workers are running and the plan limits.
struct TitleBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // The search field sits between the two sides, so a long right side never covers it;
        // the spacers share the room, which keeps it centred while the sides are about even.
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                EchoMark().frame(width: 22, height: 22)
                Text("Echo").font(Ledger.font(14, .semibold)).foregroundStyle(Ledger.ink)
            }
            .fixedSize()
            Spacer(minLength: 0)
            SearchField()
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                if model.sessions.isEmpty && !model.daemonDown {
                    // Before the first session there is nothing to count: say the daemon is up.
                    HStack(spacing: 8) {
                        Circle().fill(Ledger.done).frame(width: 7, height: 7)
                        Text("Echo daemon running").foregroundStyle(Ledger.ink2)
                    }
                } else {
                    if model.runningCount > 0 {
                        Text(workers(model.runningCount, "running")).foregroundStyle(Ledger.ink2)
                    }
                    UsageInline(usage: model.usage)
                    if let stats = model.workerStats, stats.withTranscript > 0 {
                        StatsInline(stats: stats)
                    }
                }
            }
            // The search field gives up room first.
            .fixedSize()
        }
        // Past the traffic lights, which full screen hides.
        .padding(.leading, model.fullScreen ? 16 : 86)
        .padding(.trailing, 16)
        .font(Ledger.font(12.5))
        .frame(height: Self.height)
    }

    static let height: CGFloat = 52
}

/// What looks like a search field at the top of the window: it opens Quick open (⌘K).
struct SearchField: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var hovering = Flag()

    var body: some View {
        Button { model.quickOpenShown = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(Ledger.font(13, .semibold))
                Text("Search repos, agents, Workers and commands")
                Spacer(minLength: 8)
                Text("⌘K")
                    .font(Ledger.font(11.5, .semibold))
                    .foregroundStyle(Ledger.ink2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Ledger.strip, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
            }
            .font(Ledger.font(13.5))
            .foregroundStyle(Ledger.ink2)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: 220, maxWidth: 520, minHeight: 30, maxHeight: 30)
            // Fill alone sets it apart, a shade darker on hover; no shadow.
            .background(hovering.on ? Ledger.band : Ledger.pill, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering.on = $0 }
        .help("Go to a repo, agent, Worker or command (⌘K)")
        .accessibilityLabel("Search")
    }
}

/// The ledger as a tree: each repo, its agents beneath, and each agent's Workers beneath that,
/// one line apiece (ui-ux/0084). A Worker that finished leaves it; one that needs you stays.
struct LedgerTree: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var stoppedOpen = Flag()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                NewSessionMenu(row: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                Text("Sessions")
                    .font(Ledger.font(12))
                    .foregroundStyle(Ledger.ink3)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                let tabs = model.tabSessions
                if tabs.isEmpty {
                    Hint("No repos yet. Start a session with +.")
                }
                ForEach(tabs) { session in
                    RepoGroup(session: session)
                }
                let stopped = model.stoppedSessions
                if !stopped.isEmpty {
                    Button { stoppedOpen.on.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(Ledger.font(9, .semibold))
                                .rotationEffect(.degrees(stoppedOpen.on ? 90 : 0))
                                .frame(width: 16)
                            Text("Stopped")
                            Text("\(stopped.count)").monospacedDigit()
                            Spacer()
                        }
                        .font(Ledger.font(12, .medium))
                        .foregroundStyle(Ledger.ink3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    if stoppedOpen.on {
                        ForEach(stopped) { session in
                            TreeRow(selected: false, indent: 0) {
                                model.selectSession(session.repo)
                            } label: {
                                Image(systemName: "folder").font(Ledger.font(13)).foregroundStyle(Ledger.ink3).frame(width: 16)
                                Text(session.name).foregroundStyle(Ledger.ink2).fadedEnd()
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }
}

/// A line of the tree: a rounded fill when picked or hovered, the same height everywhere.
struct TreeRow<Label: View>: View {
    let selected: Bool
    /// 0 for a repo, 1 for an agent, 2 for a Worker.
    let indent: Int
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @StateObject private var hovering = Flag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { label() }
                .font(Ledger.font(14))
                .padding(.leading, 12 + CGFloat(indent) * 22)
                .padding(.trailing, 12)
                .frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Ledger.selected : hovering.on ? Ledger.wash : Color.clear,
                            in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
                .overlay(alignment: .leading) {
                    // Beneath a repo or an agent, a small dot marks the row as its child (ui-ux/0086).
                    if indent > 0 {
                        Circle().fill(Ledger.ink3.opacity(0.55)).frame(width: 3, height: 3)
                            .padding(.leading, CGFloat(indent) * 20 - 1.5)
                    }
                }
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering.on = $0 }
    }
}

/// One repo: its header line, and under it an indent guide beside its agents.
struct RepoGroup: View {
    @EnvironmentObject private var model: AppModel
    let session: SessionInfo

    var body: some View {
        let snapshot = model.snapshot(session.repo)
        let groups = snapshot.groups
        VStack(alignment: .leading, spacing: 2) {
            TreeRow(selected: false, indent: 0) {
                model.selectSession(session.repo)
            } label: {
                Image(systemName: "folder").font(Ledger.font(13)).foregroundStyle(Ledger.ink3).frame(width: 16)
                Text(session.name)
                    .font(Ledger.font(14, .semibold))
                    .foregroundStyle(Ledger.ink)
                    .fadedEnd()
            }
            .help("\(session.name): \(workers(model.activeCount(session.repo), "at work"))")
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        AgentBranch(group: group, snapshot: snapshot, repo: session.repo, number: index + 1)
                    }
                }
            }
        }
        .padding(.bottom, 10)
    }
}

/// The amber count of what waits on the human.
struct NeedsBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(Ledger.font(11, .semibold))
            .foregroundStyle(Ledger.markerInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Ledger.marker, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
    }
}

/// The + at the end of the tabs: an Orchestrator, or a Terminal (a plain shell in the repo).
struct NewSessionMenu: View {
    @EnvironmentObject private var model: AppModel
    /// The sidebar's "New session" row, as Claude's "New chat"; else the bare +.
    var row = false

    var body: some View {
        Menu {
            Button { model.showNewSession(repo: model.selectedRepo, kind: .orchestrator) } label: {
                Text("Orchestrator")
                Text("Hands Tasks to Workers and reports back")
            }
            Button { model.openTerminal() } label: {
                Text("Terminal")
                Text("A plain shell in the repo, in your multiplexer")
            }
            .disabled(model.selectedRepo == nil)
            Divider()
            Button { model.showFanOut() } label: {
                Text("Fan Out a Task")
                Text("Several Workers try it; you keep one")
            }
            .disabled(model.selectedRepo == nil)
        } label: {
            if row {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Ledger.onPrimary)
                        .frame(width: 22, height: 22)
                        .background(Ledger.primary, in: Circle())
                    Text("New session").font(Ledger.font(14, .medium)).foregroundStyle(Ledger.ink)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 6)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
            } else {
                Image(systemName: "plus")
                    .font(Ledger.font(12, .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: !row, vertical: false)
        .foregroundStyle(Ledger.ink2)
        .help("New session")
        .accessibilityLabel("New session")
    }
}

/// An agent's mark: three dots for an Orchestrator, a prompt for a Claude Code session, a framed
/// prompt for a Terminal.
struct AgentGlyph: View {
    let kind: Agent.Kind

    var body: some View {
        Group {
            if kind == .orchestrator {
                Canvas { context, size in
                    let s = min(size.width, size.height) / 16
                    for (x, y, r) in [(8.0, 8.0, 2.6), (8.0, 2.4, 1.4), (12.85, 10.8, 1.4), (3.15, 10.8, 1.4)] {
                        let rect = CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)
                        context.fill(Path(ellipseIn: rect), with: .foreground)
                    }
                }
            } else if kind == .terminal {
                Canvas { context, size in
                    let s = min(size.width, size.height) / 16
                    let frame = CGRect(x: 1 * s, y: 2 * s, width: 14 * s, height: 12 * s)
                    context.stroke(Path(roundedRect: frame, cornerRadius: 2.5 * s), with: .foreground, lineWidth: 1.4 * s)
                    var chevron = Path()
                    chevron.move(to: CGPoint(x: 4.2 * s, y: 5.8 * s))
                    chevron.addLine(to: CGPoint(x: 6.6 * s, y: 8 * s))
                    chevron.addLine(to: CGPoint(x: 4.2 * s, y: 10.2 * s))
                    context.stroke(chevron, with: .foreground,
                                   style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round, lineJoin: .round))
                    let bar = CGRect(x: 8 * s, y: 9.5 * s, width: 3.6 * s, height: 1.4 * s)
                    context.fill(Path(roundedRect: bar, cornerRadius: 0.7 * s), with: .foreground)
                }
            } else {
                Canvas { context, size in
                    let s = min(size.width, size.height) / 16
                    var chevron = Path()
                    chevron.move(to: CGPoint(x: 2.6 * s, y: 4.2 * s))
                    chevron.addLine(to: CGPoint(x: 6.4 * s, y: 8 * s))
                    chevron.addLine(to: CGPoint(x: 2.6 * s, y: 11.8 * s))
                    context.stroke(chevron, with: .foreground,
                                   style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
                    let bar = CGRect(x: 8.6 * s, y: 10 * s, width: 5 * s, height: 2 * s)
                    context.fill(Path(roundedRect: bar, cornerRadius: s), with: .foreground)
                }
            }
        }
        .frame(width: 13, height: 13)
        .accessibilityLabel(kind == .orchestrator ? "Orchestrator" : kind == .terminal ? "Terminal" : "Claude Code session")
    }
}

// MARK: - The ledger

struct LedgerColumn: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            LedgerTree()
            Spacer(minLength: 0)
            HStack {
                LedgerToggle()
                Spacer()
                SettingsButton()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Collapses or expands the ledger; it sits at the ledger's foot in both shapes.
struct LedgerToggle: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let title = model.ledgerCollapsed ? "Expand ledger" : "Collapse ledger"
        Button { model.toggleLedger() } label: {
            Image(systemName: "sidebar.left")
                .font(Ledger.font(14))
                .foregroundStyle(Ledger.ink2)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help("\(title) (⌘L)")
    }
}

/// Opens Settings over the whole window; it sits at the ledger's foot beside the collapse button.
struct SettingsButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.showSettings() } label: {
            Image(systemName: "gearshape")
                .font(Ledger.font(14))
                .foregroundStyle(Ledger.ink2)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .help("Settings (⌘,)")
    }
}

/// The collapsed ledger: the repo's needs-you count, then each agent and a mark per Worker in its
/// state colour. Clicking one shows it, as its row in the full ledger would.
struct LedgerRail: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let repo = model.selectedRepo {
                let snapshot = model.snapshot(repo)
                ScrollView {
                    VStack(spacing: 2) {
                        if snapshot.needsYouCount > 0 {
                            Text("\(snapshot.needsYouCount)")
                                .font(Ledger.font(11, .semibold))
                                .foregroundStyle(Ledger.markerInk)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Ledger.marker, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
                                .help("\(snapshot.needsYouCount) need you")
                                .padding(.bottom, 6)
                        }
                        ForEach(Array(snapshot.groups.enumerated()), id: \.element.id) { index, group in
                            if index > 0 {
                                Rectangle().fill(Ledger.rule).frame(width: 20, height: 1).padding(.vertical, 6)
                            }
                            RailAgent(agent: group.agent, repo: repo)
                            ForEach(workers(group, in: snapshot)) { worker in
                                RailWorker(worker: worker, repo: repo)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                SettingsButton()
                LedgerToggle()
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// In the tree's order: waiting on you, running, ended badly.
    private func workers(_ group: AgentGroup, in snapshot: Snapshot) -> [WorkerRow] {
        var selected: String?
        if case .worker(let r, let id)? = model.selection, r == snapshot.repo { selected = id }
        return visibleWorkers(group, in: snapshot, selected: selected)
    }
}

struct RailAgent: View {
    @EnvironmentObject private var model: AppModel
    let agent: Agent
    let repo: String

    var body: some View {
        let selected = model.selection == .agent(repo: repo, id: agent.id)
        Button { model.select(.agent(repo: repo, id: agent.id)) } label: {
            AgentGlyph(kind: agent.kind)
                .foregroundStyle(agent.live ? Ledger.ink : Ledger.ink3)
                .frame(width: 32, height: 28)
                .background(selected ? Ledger.selected : Color.clear, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .prewarmsTerminal(.agent(id: agent.id), epoch: "\(agent.live)")
        .help("\(agent.displayName), \(agent.live ? "live" : agent.isOrchestrator ? "stopped" : "ended")")
    }
}

struct RailWorker: View {
    @EnvironmentObject private var model: AppModel
    let worker: WorkerRow
    let repo: String

    var body: some View {
        let selected = model.selection == .worker(repo: repo, id: worker.id)
        Button { model.select(.worker(repo: repo, id: worker.id)) } label: {
            WorkerMark(worker: worker)
                .frame(width: 32, height: 22)
                .background(selected ? Ledger.selected : Color.clear, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .prewarmsTerminal(model.terminalTarget(repo, worker))
        .help("\(worker.id) \(worker.profile): \(worker.title)\n\(worker.phaseLabel), quiet for \(formatAge(worker.quietFor()))")
    }
}

/// The Workers an agent's branch shows: those waiting on the human, then those at work, then
/// any that ended badly. A Worker that finished is gone, unless it is the one on screen, so
/// opening its report from a notification still works (ui-ux/0084).
func visibleWorkers(_ group: AgentGroup, in snapshot: Snapshot, selected: String?) -> [WorkerRow] {
    let waiting = group.needs.compactMap(\.worker).compactMap { id in snapshot.workers.first { $0.id == id } }
    let settled = group.settled.filter { $0.isTrouble || $0.id == selected }
    var seen = Set<String>()
    return (waiting + group.running + settled).filter { seen.insert($0.id).inserted }
}

/// One agent in the tree: its line, then its Workers and what waits on the human.
struct AgentBranch: View {
    @EnvironmentObject private var model: AppModel
    let group: AgentGroup
    let snapshot: Snapshot
    let repo: String
    /// Its place in the repo, which ⌘ and the number shows.
    let number: Int

    var body: some View {
        let agent = group.agent
        let selectedWorker: String? = {
            if case .worker(let r, let id)? = model.selection, r == repo { return id }
            return nil
        }()
        let workers = visibleWorkers(group, in: snapshot, selected: selectedWorker)
        let folded = model.collapsed.contains(agent.id)
        VStack(alignment: .leading, spacing: 2) {
            AgentLine(group: group, repo: repo, number: number, folded: folded, hasChildren: !workers.isEmpty,
                      running: workers.filter(\.isActive).count)
            if !folded {
                if let confirmation = model.confirmations[agent.id] {
                    ConfirmationLine(text: confirmation.text)
                        .padding(.leading, 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(workers) { worker in
                        LedgerRow(worker: worker, repo: repo)
                    }
                }
            }
        }
        // A Worker starting, finishing, or leaving slides the rows below it instead of jumping.
        .animation(.easeInOut(duration: 0.2), value: workers.map(\.id))
    }
}

/// An agent's line: its mark and name; click to show it. The chevron folds its Workers.
struct AgentLine: View {
    @EnvironmentObject private var model: AppModel
    let group: AgentGroup
    let repo: String
    let number: Int
    let folded: Bool
    let hasChildren: Bool
    let running: Int
    @StateObject private var hovering = Flag()

    var body: some View {
        let agent = group.agent
        let selected = model.selection == .agent(repo: repo, id: agent.id)
        TreeRow(selected: selected, indent: 1) {
            model.select(.agent(repo: repo, id: agent.id))
        } label: {
            AgentGlyph(kind: agent.kind).foregroundStyle(agent.live ? Ledger.ink2 : Ledger.ink3)
            Text(agent.displayName)
                .italic(agent.name == nil && !agent.isTerminal)
                .foregroundStyle(agent.live ? Ledger.ink : Ledger.ink3)
                .fadedEnd()
            if folded && running > 0 {
                Text("\(running)").font(Ledger.font(12)).monospacedDigit().foregroundStyle(Ledger.ink3)
            }
            if !agent.live {
                Circle().strokeBorder(Ledger.ink3, lineWidth: 1).frame(width: 7, height: 7)
                    .accessibilityLabel("Stopped")
            }
            if hasChildren && (folded || hovering.on) {
                Button { model.toggleCollapsed(agent.id) } label: {
                    Image(systemName: "chevron.right")
                        .font(Ledger.font(9, .semibold))
                        .rotationEffect(.degrees(folded ? 0 : 90))
                        .foregroundStyle(Ledger.ink3)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(folded ? "Show \(agent.displayName)'s Workers" : "Fold \(agent.displayName)'s Workers")
            }
            // How many of this agent's Workers (or it itself) wait on the human (ui-ux/0094).
            if !group.needs.isEmpty {
                NeedsBadge(count: group.needs.count).help("\(group.needs.count) waiting on you")
            }
        }
        .onHover { hovering.on = $0 }
        .prewarmsTerminal(.agent(id: agent.id), epoch: "\(agent.live)")
        .contextMenu {
            Button("Rename…") { model.renaming = agent }
            if agent.isTerminal {
            } else if agent.live {
                Button(agent.isOrchestrator ? "Stop Orchestrator" : "End Session") { model.stopAgent(agent.id) }
            } else {
                Button(agent.isOrchestrator ? "Start Orchestrator" : "Resume Session") { model.startAgent(agent.id) }
            }
            Divider()
            Button("Close \(agent.kindName)…") { model.closing = agent }
        }
        .help([agent.name == nil ? "Named after your first request" : agent.displayName,
               number <= 9 ? "⌘\(number)" : nil,
               agent.isOrchestrator ? "Orchestrator" : nil, agent.branch,
               agent.model.map(AgentLine.short)].compactMap { $0 }.joined(separator: ", "))
    }

    /// "claude-opus-5-5" reads "opus".
    static func short(_ model: String) -> String {
        let parts = model.split(separator: "-")
        return parts.count >= 2 && parts[0] == "claude" ? String(parts[1]) : model
    }
}

// MARK: - The terminal side

struct MainPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tabs = model.openPreviews.filter { $0.root == model.selectedCheckout }
        VStack(spacing: 0) {
            // Always there, Terminal tab alone or not, so every terminal is the same size and
            // switching never resizes one: a resize makes Claude Code redraw everything (ui-ux/0051).
            if model.selection != nil { PreviewTabs(files: tabs) }
            Group {
                switch model.selection {
                case .agent(let repo, let id)?:
                    if let agent = model.agents(repo).first(where: { $0.id == id }) {
                        AgentPanel(repo: repo, agent: agent)
                    } else {
                        ContentUnavailableView("That session is closed", systemImage: "questionmark.square.dashed",
                                               description: Text("Pick another agent in the ledger."))
                    }
                case .worker(let repo, let id)?:
                    WorkerPanel(repo: repo, id: id)
                case nil:
                    FirstLaunch()
                }
            }
            // Previewed files cover the panel; the terminal stays attached underneath, and each
            // file keeps its scroll and view while another tab is shown. Every checkout's open
            // files stay laid out, not just this one's, so showing an agent in another checkout
            // never lays a long file out again from scratch (bugs/0055).
            .overlay {
                ZStack {
                    ForEach(model.openPreviews, id: \.self) { file in
                        FilePreviewPanel(file: file, files: model.checkoutFiles(file.root, shown: file.root == model.selectedCheckout),
                                         active: model.preview == file && file.root == model.selectedCheckout)
                    }
                }
            }
        }
        .ledgerSheet()
        .task(id: scheme) { PreviewContent.warm(dark: scheme == .dark) }
    }
}

/// An agent's chat or terminal (ADR 0010). While an Orchestrator or a Claude Code session is not
/// running, its shell fills the terminal and the header offers to start it again.
struct AgentPanel: View {
    @EnvironmentObject private var model: AppModel
    let repo: String
    let agent: Agent

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader {
                AgentGlyph(kind: agent.kind).foregroundStyle(Ledger.ink3)
                Text(agent.displayName).fontWeight(.medium).lineLimit(1)
                Text(meta)
                    .font(Ledger.font(12.5))
                    .foregroundStyle(Ledger.ink3)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if model.hasChat(agent) {
                    ChatTerminalSwitch(chat: model.showsChat(agent)) { model.toggleChat() }
                }
                if agent.isTerminal {
                } else if agent.live {
                    Button { model.stopAgent(agent.id) } label: {
                        Image(systemName: "stop.circle")
                            .font(Ledger.font(14))
                            .foregroundStyle(Ledger.ink2)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(agent.isOrchestrator ? "Stop Orchestrator" : "End session")
                    .help(agent.isOrchestrator ? "Stop the Orchestrator. Its Workers keep running." : "End this Claude Code session. You can resume it.")
                } else if agent.isOrchestrator {
                    Button("Start Orchestrator") { model.startAgent(agent.id) }
                        .buttonStyle(.ledgerPrimary)
                        .disabled(model.daemonDown)
                        .help(stoppedHelp)
                } else {
                    HStack(spacing: 8) {
                        Button("Start fresh") { model.startFresh(agent, repo: repo) }
                            .buttonStyle(.ledger)
                            .help("A new conversation in the same repo")
                        Button("Resume") { model.startAgent(agent.id) }
                            .buttonStyle(.ledgerPrimary)
                            .help("Picks the saved conversation up where it stopped")
                    }
                    .disabled(model.daemonDown)
                }
            }
            if model.showsChat(agent) {
                ChatDeck(repo: repo, shown: .agent(id: agent.id))
            } else {
                // A new terminal whenever the agent starts or stops, so one without the multiplexer
                // attaches to whichever runs now: the agent, or its shell.
                LiveTerminal(target: .agent(id: agent.id), epoch: "\(agent.live)")
                    .id("\(agent.id) \(agent.live)")
            }
        }
    }

    private var meta: String {
        let name = URL(fileURLWithPath: repo).lastPathComponent
        let model = agent.model ?? "default model"
        let place = (agent.head ?? agent.branch).map { "\(name) on \($0)" } ?? name
        if agent.isTerminal { return "Shell in \(place)" }
        if !agent.live { return "\(agent.isOrchestrator ? "Stopped" : "Exited"), a shell in \(place)" }
        return "\(agent.kindName) in \(place), \(model)"
    }

    private var stoppedHelp: String {
        let running = model.snapshot(repo).groups.first { $0.agent.id == agent.id }?.running.count ?? 0
        let workers = running > 0 ? "Its \(running) running Workers carry on meanwhile. " : ""
        return workers + "Starting it resumes the same conversation, with every report it missed."
    }
}

/// Chat | Terminal in an agent's header; ⇧⌘T does the same.
struct ChatTerminalSwitch: View {
    let chat: Bool
    /// What shows instead of the chat: the terminal, or a settled Worker's Final Report.
    var other = "Terminal"
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            segment("Chat", on: chat)
            segment(other, on: !chat)
        }
        .padding(2)
        .background(Ledger.bubble, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
        .help("Switch between the chat and the \(other.lowercased()) (⇧⌘T)")
    }

    private func segment(_ title: String, on: Bool) -> some View {
        Button { if !on { toggle() } } label: {
            Text(title)
                .font(Ledger.font(12, on ? .medium : .regular))
                .foregroundStyle(on ? Ledger.ink : Ledger.ink2)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(on ? Ledger.field : .clear, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
                .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1.5, y: 0.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A live agent's or Worker's terminal: inside the human's multiplexer when that is on (its
/// first pane shows the target, and they can split beside it), else the terminal itself.
struct LiveTerminal: View {
    @EnvironmentObject private var model: AppModel
    let target: TerminalTarget
    /// Changes when a terminal kept for `target` no longer fits it (`TerminalCache`).
    var epoch = ""

    var body: some View {
        let command = model.paneCommand(for: target)
        Group {
            if let command {
                TerminalPane(target: target, command: command, client: model.client, appearance: model.appearance,
                             keyboard: !model.modalShown && model.preview == nil && !model.treeFocused && !model.sideFocus,
                             focusRequest: model.terminalFocusRequest, epoch: epoch)
            } else {
                Pending("Starting the multiplexer…")
                    .font(Ledger.font(12.5))
                    .foregroundStyle(TerminalTheme.color(model.appearance.theme.foreground).opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.leading, 10)
        .padding(.vertical, 6)
        .background { TerminalBackdrop(appearance: model.appearance) }
        .opacity(model.daemonDown ? 0.45 : 1)
        // Runs again whenever the multiplexer line goes, so a multiplexer the human quit is replaced.
        .task(id: "\(target.label) \(command == nil) \(model.multiplexer.enabled)") {
            model.ensureMux(target)
        }
    }
}

extension View {
    /// The pointer resting on this row starts `target`'s terminal out of sight, so a click on it
    /// shows the terminal at once (ui-ux/0058).
    func prewarmsTerminal(_ target: TerminalTarget?, epoch: String = "") -> some View {
        modifier(PrewarmOnHover(target: target, epoch: epoch))
    }
}

private struct PrewarmOnHover: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let target: TerminalTarget?
    let epoch: String
    @StateObject private var dwell = Dwell()

    /// Long enough that sweeping the pointer past rows starts nothing; short enough to finish
    /// before a usual click.
    private static let rest = Duration.milliseconds(120)

    func body(content: Content) -> some View {
        content.onHover { inside in
            dwell.task?.cancel()
            guard inside, let target else { return }
            dwell.task = Task { @MainActor in
                try? await Task.sleep(for: Self.rest)
                guard !Task.isCancelled else { return }
                model.prewarm(target, epoch: epoch)
            }
        }
    }
}

/// A pending pointer rest, for views that would otherwise need `@State`.
private final class Dwell: ObservableObject {
    var task: Task<Void, Never>?
}

/// What sits behind a terminal: the theme background, or the chosen image, blurred and dimmed by it.
struct TerminalBackdrop: View {
    let appearance: TerminalAppearance
    private static var images: [String: NSImage] = [:]

    var body: some View {
        let background = TerminalTheme.color(appearance.theme.background)
        if let path = appearance.backgroundImage, let image = Self.image(at: path) {
            Color.clear
                .overlay {
                    Image(nsImage: image).resizable().scaledToFill()
                        .blur(radius: appearance.backgroundImageBlur, opaque: true)
                }
                .clipped()
                .overlay { background.opacity(appearance.backgroundImageDim) }
                // The filled image spills past the panel; clipping hides that but still hit-tests
                // it, which took clicks meant for the ledger and the Files column.
                .allowsHitTesting(false)
        } else {
            background
        }
    }

    /// Read once per path; a file that is gone falls back to the plain background.
    private static func image(at path: String) -> NSImage? {
        if let image = images[path] { return image }
        let image = NSImage(contentsOfFile: path)
        images[path] = image
        return image
    }
}

// MARK: - Panels shared parts

/// A panel's title row: what the terminal below is showing.
struct PanelHeader<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // As tall as its buttons, so a header without any lines up with the rest.
        HStack(spacing: 10) { content() }
            .frame(minHeight: 26)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FirstLaunch: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start your first session")
                .font(Ledger.font(28, .semibold))
            Text("A session is an Orchestrator, or Claude Code on its own, working in one git repo. You talk to it; it hands Tasks to Workers and reports back. Workers keep running when this window is closed.")
                .font(Ledger.font(15))
                .foregroundStyle(Ledger.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open a repo") { model.showNewSession() }
                .buttonStyle(.ledgerLarge)
                .padding(.top, 6)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// MARK: - Workers

struct WorkerPanel: View {
    @EnvironmentObject private var model: AppModel
    let repo: String
    let id: String
    @StateObject private var confirmStop = Flag()

    var body: some View {
        if let worker = model.snapshot(repo).workers.first(where: { $0.id == id }) {
            VStack(spacing: 0) {
                WorkerHeader(worker: worker, confirmStop: $confirmStop.on, view: viewBinding(worker),
                             comments: model.reviews[AppModel.workerKey(repo, worker)]?.count ?? 0,
                             chat: model.showsChat(worker))
                if model.workerView(repo, worker) == .changes {
                    ChangesView(repo: repo, worker: worker)
                } else if model.workerView(repo, worker) == .compare, let fanout = worker.fanout {
                    CompareView(repo: repo, fanout: fanout)
                } else if let number = worker.number, model.showsChat(worker) {
                    ChatDeck(repo: repo, shown: .worker(id: number))
                } else if let target = model.terminalTarget(repo, worker) {
                    LiveTerminal(target: target)
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                        Text("Typing here is an Intervention. \(worker.id) does what you ask and tells the Orchestrator.")
                            .lineLimit(1)
                    }
                    .font(Ledger.font(12.5))
                    .foregroundStyle(Ledger.ink2)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ledger.wash)
                } else {
                    FinalReportView(worker: worker)
                }
            }
            .confirmationDialog("Stop \(worker.id)?", isPresented: $confirmStop.on) {
                Button("Stop \(worker.id)", role: .destructive) { model.stopWorker(worker) }
            } message: {
                Text("Its terminal closes and the Orchestrator is told it ended without a Final Report.")
            }
        } else {
            ContentUnavailableView("\(id) is gone", systemImage: "questionmark.square.dashed",
                                   description: Text("Its row left the ledger. Pick another Worker or the Orchestrator."))
        }
    }

    private func viewBinding(_ worker: WorkerRow) -> Binding<WorkerView> {
        Binding {
            model.workerView(repo, worker)
        } set: { view in
            model.show(view, repo: repo, worker: worker)
        }
    }
}

struct WorkerHeader: View {
    let worker: WorkerRow
    @Binding var confirmStop: Bool
    /// Its terminal or Final Report, its Changes, or its fan-out compared.
    @Binding var view: WorkerView
    /// Review comments not sent yet.
    let comments: Int
    /// Its main view is its chat (ADR 0010).
    let chat: Bool
    @EnvironmentObject private var model: AppModel

    /// The header's choices: the chat and the terminal (or Final Report) are both its main view.
    private enum Shown: Hashable { case chat, main, changes, compare }

    private var shown: Binding<Shown> {
        Binding {
            switch view {
            case .main: chat ? .chat : .main
            case .changes: .changes
            case .compare: .compare
            }
        } set: { picked in
            switch picked {
            case .chat, .main:
                view = .main
                if let number = worker.number { model.setChat(.worker(id: number), on: picked == .chat) }
            case .changes: view = .changes
            case .compare: view = .compare
            }
        }
    }

    private var shownOptions: [(value: Shown, title: String)] {
        var options: [(value: Shown, title: String)] = []
        if worker.number != nil { options.append((.chat, "Chat")) }
        options.append((.main, worker.isActive && worker.live ? "Terminal" : "Final Report"))
        options.append((.changes, comments > 0 ? "Changes (\(comments))" : "Changes"))
        if worker.fanout != nil { options.append((.compare, "Compare")) }
        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(worker.id) \(worker.profile)").fontWeight(.medium)
                Text(worker.title).foregroundStyle(Ledger.ink2).lineLimit(1)
                HStack(spacing: 6) {
                    WorkerMark(worker: worker)
                    Text(worker.phaseLabel)
                }
                .font(Ledger.font(12.5))
                .foregroundStyle(worker.markColor)
                .padding(.leading, 4)
                Spacer(minLength: 8)
                LedgerSegmented(selection: shown, options: shownOptions)
                .help("⇧⌘T switches between the chat and the \(worker.isActive && worker.live ? "terminal" : "Final Report")")
                if worker.isActive, worker.live {
                    Button("Stop Worker") { confirmStop = true }.buttonStyle(.ledger)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 2) {
                GridRow {
                    Fact.label("Model")
                    Fact.label(worker.branch == nil ? "Where" : "Worktree")
                    Fact.label("Latest status")
                    Fact.label("Quiet for")
                }
                GridRow {
                    Fact.value(worker.modelLine ?? "From its profile")
                    Fact.value(worker.branch ?? worker.place, mono: worker.branch != nil)
                    Fact.value(worker.progress ?? "None sent yet")
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        Fact.value(formatAge(worker.quietFor(at: context.date)))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ledger.band, in: Rectangle())
    }
}

enum Fact {
    static func label(_ text: String) -> some View {
        Text(text).font(Ledger.font(11.5)).foregroundStyle(Ledger.ink3)
    }

    static func value(_ text: String, mono: Bool = false) -> some View {
        Text(text)
            .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 12.5))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// A settled Worker: its Final Report, read as a document rather than a closed terminal.
/// Each section's text renders as Markdown, so lists, `code`, and emphasis read as written.
struct FinalReportView: View {
    let worker: WorkerRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .firstTextBaseline) {
                    Text(worker.finalReport == nil ? "No Final Report" : "Final Report")
                        .font(Ledger.font(30, .bold))
                    Spacer(minLength: 8)
                    if let report = worker.finalReport {
                        Button("Copy report") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(report, forType: .string)
                        }
                        .buttonStyle(.ledger)
                    }
                }
                if let report = worker.finalReport {
                    ForEach(Array(ReportSection.parse(report).enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 12) {
                            if let title = section.title {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(title).font(Ledger.font(19, .semibold))
                                    Rectangle().fill(Ledger.rule).frame(height: 1)
                                }
                            }
                            let blocks = parseMarkdown(section.body)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                                    MarkdownBlockView(block: block, leading: 7, codeSize: 13.5)
                                        .padding(.top, index == 0 ? 0 : Self.gap(blocks[index - 1], block))
                                }
                            }
                            .foregroundStyle(section.title == "State" && worker.isTrouble ? Ledger.fail : Ledger.ink)
                        }
                    }
                } else {
                    Text("\(worker.id) \(worker.phaseLabel.lowercased()) without sending one. The Orchestrator has been told.")
                        .lineSpacing(7)
                        .foregroundStyle(Ledger.ink2)
                }
            }
            .font(Ledger.font(15))
            .foregroundStyle(Ledger.ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The file preview's spacing, opened up to match the report's larger text.
    private static func gap(_ previous: MarkdownBlock, _ block: MarkdownBlock) -> CGFloat {
        if case .bullet = previous, case .bullet = block { return 9 }
        return MarkdownBlockView.gap(previous, block) + 4
    }
}

/// A Final Report split on the Worker Contract's headings: `State:`, `Changed:`, `Verified:`.
struct ReportSection: Equatable {
    var title: String?
    var body: String

    static let headings = ["State", "Changed", "Verified"]

    static func parse(_ report: String) -> [ReportSection] {
        var sections: [ReportSection] = []
        for line in report.components(separatedBy: "\n") {
            let heading = headings.first { line.hasPrefix($0 + ":") }
            if let heading {
                let rest = line.dropFirst(heading.count + 1).trimmingCharacters(in: .whitespaces)
                sections.append(ReportSection(title: heading, body: rest))
            } else if sections.isEmpty {
                sections.append(ReportSection(title: nil, body: line))
            } else {
                sections[sections.count - 1].body += (sections[sections.count - 1].body.isEmpty ? "" : "\n") + line
            }
        }
        return sections
            .map { ReportSection(title: $0.title, body: $0.body.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.title != nil || !$0.body.isEmpty }
    }
}


// MARK: - Ledger parts

/// A Worker in the tree: its mark and its title, nothing more; the rest is in its tooltip and
/// panel. Amber mark when it waits on you, red when it ended badly.
struct LedgerRow: View {
    @EnvironmentObject private var model: AppModel
    let worker: WorkerRow
    let repo: String

    var body: some View {
        let selected = model.selection == .worker(repo: repo, id: worker.id)
        TreeRow(selected: selected, indent: 2) {
            model.select(.worker(repo: repo, id: worker.id))
        } label: {
            Text(worker.title)
                .fontWeight(worker.state == .needsYou && worker.isActive ? .medium : .regular)
                .foregroundStyle(selected || worker.state == .needsYou && worker.isActive ? Ledger.ink : Ledger.ink2)
                .fadedEnd()
            // How long since it last reported, then its state; the minute ticks without a new snapshot.
            TimelineView(.everyMinute) { context in
                let quiet = worker.quietFor(at: context.date)
                Text(quiet < 60 ? "now" : formatAge(quiet))
                    .font(Ledger.font(12))
                    .monospacedDigit()
                    .foregroundStyle(Ledger.ink3)
                    .lineLimit(1)
            }
            WorkerGlyph(worker: worker)
        }
        .prewarmsTerminal(model.terminalTarget(repo, worker))
        .help([worker.id, worker.profile, worker.title, worker.branch, worker.phaseLabel,
               "quiet for \(formatAge(worker.quietFor()))"].compactMap { $0 }.joined(separator: " · "))
        .contextMenu {
            if worker.settledAt != nil {
                Button("Dismiss") { model.dismiss([worker]) }
            }
        }
    }
}

struct ConfirmationLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(Ledger.font(11, .bold))
            Text(text).lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(Ledger.font(12.5))
        .foregroundStyle(Ledger.okInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Ledger.okWash, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .transition(.opacity)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A quiet sentence where a section is empty.
struct Hint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Ledger.font(12.5))
            .foregroundStyle(Ledger.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }
}

// MARK: - Usage

/// The Claude account's plan limits, in the session bar. Click to re-read them.
/// The top bar's Worker statistics: the context a Worker starts with, and a button that opens
/// the week's report.
struct StatsInline: View {
    let stats: WorkerStats
    @StateObject private var shown = Flag()

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("Worker start").foregroundStyle(Ledger.ink2)
                Text(tokenCount(stats.startContext)).fontWeight(.medium).monospacedDigit().foregroundStyle(Ledger.ink)
            }
            .help("The median context a Worker starts with over the last 7 days; every turn re-reads it")
            Button { shown.on.toggle() } label: {
                Image(systemName: "ellipsis")
                    .font(Ledger.font(12, .semibold))
                    .foregroundStyle(Ledger.ink2)
                    .frame(width: 24, height: 22)
                    .background(shown.on ? Ledger.fill : Color.clear, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Worker statistics")
            .accessibilityLabel("Worker statistics")
            .popover(isPresented: $shown.on, arrowEdge: .bottom) { StatsReport(stats: stats) }
        }
    }
}

/// `echoctl stats` for the last 7 days: where Workers' tokens went and how much they read.
struct StatsReport: View {
    let stats: WorkerStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Workers, last 7 days").font(Ledger.font(14, .semibold)).foregroundStyle(Ledger.ink)
                Text("\(stats.withTranscript) Workers, \(stats.turns) turns")
                    .foregroundStyle(Ledger.ink3)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("Start context", "\(tokenCount(stats.startContext)), re-read on every turn")
                row("Context per turn", tokenCount(stats.contextPerTurn))
                row("Token cost", "cache reads \(percent(stats.share.cacheReads)), cache writes \(percent(stats.share.cacheWrites)), output \(percent(stats.share.output))")
                row("Cold starts", "\(percent(stats.share.coldStarts)) of token cost")
                row("Per Worker", "\(number(stats.perWorker.reads)) Reads, \(number(stats.perWorker.shellReads)) cat, head, or sed, \(number(stats.perWorker.searches)) searches")
                row("Repeated reads", "\(percent(stats.repeatReads)) of Reads")
            }
            Rectangle().fill(Ledger.rule).frame(height: 1)
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Profile").gridColumnAlignment(.leading)
                    Text("Workers")
                    Text("Turns each")
                    Text("Start")
                    Text("Per turn")
                    Text("Cost")
                }
                .font(Ledger.font(12, .semibold))
                .foregroundStyle(Ledger.ink3)
                ForEach(stats.profiles) { p in
                    GridRow {
                        Text(p.profile).foregroundStyle(Ledger.ink)
                        Text("\(p.workers)")
                        Text("\(p.turnsPerWorker)")
                        Text(tokenCount(p.startContext))
                        Text(tokenCount(p.contextPerTurn))
                        Text(percent(p.share))
                    }
                    .monospacedDigit()
                    .foregroundStyle(Ledger.ink2)
                }
            }
            Text("From Claude Code transcripts; Codex Workers are not counted. Token cost weighs a cache read 0.1, a write 1.25 to 2, and output 5 against fresh input.")
                .font(Ledger.font(11.5))
                .foregroundStyle(Ledger.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Ledger.font(12.5))
        .padding(16)
        .frame(width: 460)
        .background(Ledger.paper)
        .textSelection(.enabled)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Ledger.ink3)
            Text(value).foregroundStyle(Ledger.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    private func number(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

struct UsageInline: View {
    @EnvironmentObject private var model: AppModel
    let usage: Usage?

    var body: some View {
        Button { model.refreshUsage() } label: {
            HStack(spacing: 14) {
                if usage == nil || usage?.refreshing == true { Spinner(size: 10) }
                if let usage, !usage.limits.isEmpty {
                    ForEach(usage.limits.prefix(2)) { limit in
                        HStack(spacing: 4) {
                            Text(limit.name).foregroundStyle(Ledger.ink2)
                            Text("\(limit.percent)%")
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundStyle(limit.percent >= 90 ? Ledger.fail : Ledger.ink)
                            // Counts down between snapshots, which repeat an unchanged `resets`.
                            TimelineView(.everyMinute) { context in
                                if let left = limit.resetsIn(now: context.date) {
                                    Text(left).monospacedDigit().foregroundStyle(Ledger.ink3)
                                }
                            }
                        }
                    }
                } else if usage?.error != nil {
                    Text("Usage unavailable").foregroundStyle(Ledger.ink3)
                }
            }
            .opacity(usage?.refreshing == true ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var helpText: String {
        guard let usage else { return "Reading Claude usage" }
        if let error = usage.error, usage.limits.isEmpty { return error }
        let lines = usage.limits.map { limit in
            "\(limit.name): \(limit.percent)% used" + (limit.resets.map { ", resets \($0)" } ?? "")
        }
        return (lines + ["Click to refresh."]).joined(separator: "\n")
    }
}

// MARK: - Banners

struct DisconnectedBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 2) {
                Text("Can’t reach the daemon").fontWeight(.medium)
                Text("Workers keep running inside it. The ledger shows the last update and reconnects on its own; approving and replying wait until then.")
                    .font(Ledger.font(12.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Start the daemon") { model.refreshSessions() }
                .buttonStyle(.ledgerPrimary)
        }
        .foregroundStyle(Ledger.failInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Ledger.failWash, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ErrorBanner: View {
    @EnvironmentObject private var model: AppModel
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text(text).lineLimit(2).textSelection(.enabled)
            Spacer(minLength: 8)
            Button { model.error = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
        }
        .font(Ledger.font(12.5))
        .foregroundStyle(Ledger.failInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Ledger.failWash, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
    }
}

/// A passing word about something the human just did, like a key that did nothing; it hides itself.
struct NoticeBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
            Text(text).lineLimit(2)
            Spacer(minLength: 8)
        }
        .font(Ledger.font(12.5))
        .foregroundStyle(Ledger.ink2)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Ledger.wash, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
    }
}

extension TerminalTheme {
    static func color(_ hex: String) -> Color {
        guard let c = rgb(hex) else { return .clear }
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }
}

/// The column's width when a resize drag began; nil between drags.
final class DragStart: ObservableObject {
    @Published var width: CGFloat?
}

/// The 12pt gap between two columns, dragged to resize the column beside it; a double click
/// puts it back to its first width.
struct ColumnResizer: View {
    enum Side { case left, right }
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    /// Which way dragging makes the column wider: right for the ledger, left for Files.
    let grows: Side
    let fallback: CGFloat
    @StateObject private var drag = DragStart()
    @StateObject private var hover = Flag()

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            .overlay {
                Capsule()
                    .fill(Ledger.rule)
                    .frame(width: 3, height: 36)
                    .opacity(hover.on || drag.width != nil ? 1 : 0)
            }
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .onHover { hover.on = $0 }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let from = drag.width ?? width
                        drag.width = from
                        let delta = grows == .right ? value.translation.width : -value.translation.width
                        width = min(max(from + delta, range.lowerBound), range.upperBound).rounded()
                    }
                    .onEnded { _ in drag.width = nil }
            )
            .onTapGesture(count: 2) { width = fallback }
            .accessibilityLabel("Resize column")
    }
}

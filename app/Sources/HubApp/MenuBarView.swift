import AppKit
import Combine
import HubCore
import SwiftUI

/// The menu bar panel: everything waiting on the human across sessions, answerable in place,
/// and a way back to the window.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let waiting = model.sessions.filter { model.snapshot($0.repo).needsYouCount > 0 }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Needs you").font(Ledger.font(15, .semibold))
                if !waiting.isEmpty {
                    Text("\(model.needsYouCount) across \(waiting.count) session\(waiting.count == 1 ? "" : "s")")
                        .font(Ledger.font(12.5))
                        .foregroundStyle(Ledger.ink3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if waiting.isEmpty {
                Text("Nothing is waiting on you.")
                    .font(Ledger.font(12.5))
                    .foregroundStyle(Ledger.ink2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            ForEach(waiting) { session in
                Text(session.name)
                    .font(Ledger.font(12, .semibold))
                    .foregroundStyle(Ledger.ink2)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                ForEach(model.snapshot(session.repo).needs) { need in
                    MenuNeedRow(need: need, repo: session.repo, agent: agentName(need, repo: session.repo))
                }
            }

            Color.clear.frame(height: 10)
            Text(summary)
                .font(Ledger.font(12.5))
                .foregroundStyle(Ledger.ink2)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            MenuRow(title: "Open Echo", shortcut: "⌘O") { model.reveal(repo: nil, worker: nil) }
                .keyboardShortcut("o")
            MenuRow(title: "New session") { model.showNewSession() }
            MenuRow(title: "Quit Echo", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
            Text("Quitting the app leaves every Worker running.")
                .font(Ledger.font(11.5))
                .foregroundStyle(Ledger.ink3)
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 10)
        }
        .font(Ledger.font(13))
        .foregroundStyle(Ledger.ink)
        .frame(width: 380)
        .background(Ledger.paper)
    }

    private var summary: String {
        let live = model.sessions.filter(\.live).count
        return "\(workers(model.runningCount, "running")) in \(live) session\(live == 1 ? "" : "s")"
    }

    /// Which agent asked, when the repo runs more than one.
    private func agentName(_ need: Need, repo: String) -> String? {
        let agents = model.agents(repo)
        guard agents.count > 1, let id = need.agent else { return nil }
        return agents.first { $0.id == id }?.displayName
    }
}

/// One waiting item: approve or deny a command in place, or jump to a question.
struct MenuNeedRow: View {
    @EnvironmentObject private var model: AppModel
    let need: Need
    let repo: String
    var agent: String?

    var body: some View {
        HStack(spacing: 8) {
            Marked(need.headline)
                .lineLimit(1)
                .help((agent.map { "\($0)\n" } ?? "") + (need.command ?? need.body))
            Spacer(minLength: 6)
            if need.kind == .permissionPrompt {
                Button("Approve") { model.decide(need, repo: repo, approve: true, note: "") }
                    .buttonStyle(.ledgerPrimary)
                Button("Deny") { model.decide(need, repo: repo, approve: false, note: "") }
                    .buttonStyle(.ledger)
            } else {
                Button(need.kind == .question ? "Answer" : "Open") {
                    if need.kind == .question { model.replyFocus = need.id }
                    model.reveal(repo: repo, worker: need.worker, agent: need.agent)
                }
                    .buttonStyle(.ledger)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .disabled(!model.connected)
    }
}

struct MenuRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void
    @StateObject private var hovering = Flag()

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(Ledger.ink3) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(hovering.on ? Ledger.selected : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering.on = $0 }
    }
}

/// The menu bar item: Echo's mark and how many things need the human, and nothing else; a click
/// shows `MenuBarView` below it. Built in AppKit, not as a SwiftUI MenuBarExtra: that one set its
/// image again on every change to the app's state, and macOS redrew it on every display and
/// Space each time, which made switching between agents slow (bugs/0061).
@MainActor
final class MenuBarItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = MenuBarPanel()
    private var watches: [AnyCancellable] = []
    private var clicks: Any?

    init(model: AppModel) {
        super.init()
        if let button = item.button {
            button.image = EchoGlyph.image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
        }
        let content = NSHostingController(rootView: MenuBarView().environmentObject(model))
        content.sizingOptions = [.preferredContentSize]
        panel.contentViewController = content
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 10
        panel.contentView?.layer?.masksToBounds = true
        watches.append(model.$snapshots
            .map { $0.values.reduce(0) { $0 + $1.needsYouCount } }
            .removeDuplicates()
            .sink { [weak self] count in self?.item.button?.title = count > 0 ? "\(count)" : "" })
        // Grows and shrinks from its top edge, under the item.
        watches.append(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: panel)
            .sink { [weak self] _ in self?.place() })
        watches.append(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in self?.close() })
        panel.onEscape = { [weak self] in self?.close() }
    }

    @objc private func toggle() {
        panel.isVisible ? close() : open()
    }

    private func open() {
        place()
        panel.makeKeyAndOrderFront(nil)
        // A click anywhere outside Echo closes it, as it does a menu.
        clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func close() {
        if let clicks { NSEvent.removeMonitor(clicks) }
        clicks = nil
        panel.orderOut(nil)
    }

    private func place() {
        guard let button = item.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var x = anchor.minX
        if let screen = window.screen?.visibleFrame { x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8) }
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - 4 - size.height))
    }
}

/// A panel that takes the keyboard, for answering in place, without bringing Echo to the front.
private final class MenuBarPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// The app's mark at menu bar size: one solid square and two fading echoes behind it, drawn as a
/// template image so macOS tints it for light and dark menu bars.
enum EchoGlyph {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            func square(_ x: CGFloat, _ y: CGFloat) -> NSBezierPath {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 7.5, height: 7.5), xRadius: 1.8, yRadius: 1.8)
            }
            for (x, y, alpha) in [(7.0, 1.5, 0.45), (4.5, 4.0, 0.7)] {
                NSColor.black.withAlphaComponent(alpha).setStroke()
                let path = square(x, y)
                path.lineWidth = 1.1
                path.stroke()
            }
            NSColor.black.setFill()
            square(1.5, 7).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Echo"
        return image
    }()
}

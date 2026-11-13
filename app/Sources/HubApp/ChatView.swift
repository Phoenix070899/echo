import HubCore
import SwiftUI

/// The chats shown lately, kept laid out out of sight as terminals are (ui-ux/0068), so showing
/// an agent again flips which one shows instead of laying a long chat out from scratch.
struct ChatDeck: View {
    @EnvironmentObject private var model: AppModel
    let repo: String
    let shown: TerminalTarget

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(model.keptChats(showing: shown), id: \.self) { target in
                    let on = target == shown
                    ChatView(repo: repo, target: target, shown: on, feed: model.chatFeed(target))
                        .opacity(on ? 1 : 0)
                        .allowsHitTesting(on)
                        .accessibilityHidden(!on)
                }
            }
            // One message box for every chat, holding each agent's draft: switching agents keeps
            // the same field focused instead of focusing another, which costs AppKit a key-view walk.
            ChatBottom(repo: repo, target: shown, live: model.chatFeed(shown).live,
                       composer: model.composer(shown))
        }
        .background(Ledger.paper)
        // Files dropped on the chat go with the next message.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            model.composer(shown).files += files
            return !files.isEmpty
        }
    }
}

/// An agent's conversation, read from its transcript through the daemon (ADR 0010), with a
/// message box typed at its input box. The agent keeps running in its terminal; ⇧⌘T shows it.
struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    let repo: String
    let target: TerminalTarget
    /// Only the chat in sight reads new lines.
    let shown: Bool
    /// Kept by the model per agent, so showing the agent again draws what it read before.
    @ObservedObject var feed: ChatFeed

    /// How often a shown chat asks the daemon for new lines; a read with nothing new is a stat.
    private static let poll = Duration.milliseconds(800)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ledger.paper)
            .task(id: shown) {
            if shown { await follow() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !feed.supported, let worker, !worker.isActive {
            // A Codex Worker keeps no transcript Echo reads; its report reads as before.
            FinalReportView(worker: worker)
        } else if !feed.supported {
            ContentUnavailableView("No chat for this agent", systemImage: "terminal",
                                   description: Text("Its CLI keeps no transcript Echo reads yet. Press ⇧⌘T for its terminal."))
        } else if feed.loaded && feed.rows.isEmpty && !feed.more && worker?.finalReport == nil {
            VStack(spacing: 0) {
                ContentUnavailableView("Nothing said yet", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Messages show here once the conversation starts."))
                    .frame(maxHeight: .infinity)
                // The first turn runs before its first line is written.
                WorkingRow(live: feed.live)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)
                    .frame(maxWidth: ChatBottom.width)
            }
        } else {
            ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if feed.more {
                        Button(feed.loadingOlder ? "Loading…" : "Show earlier messages") {
                            loadOlder(scroll)
                        }
                        .buttonStyle(.ledgerLink)
                        .disabled(feed.loadingOlder)
                        .frame(maxWidth: .infinity)
                        // Scrolling up to it loads the page, so older messages need no click.
                        .onAppear { if shown { loadOlder(scroll) } }
                    }
                    ForEach(feed.rows) { row in
                        ChatRowView(row: row, feed: feed)
                    }
                    if let worker, !worker.isActive {
                        FinalReportCard(worker: worker)
                    }
                    // Last in the list, so the bottom anchor keeps it and the newest message in sight.
                    // A settled Worker's turn is over, whatever its screen still shows.
                    if worker?.isActive ?? true {
                        WorkingRow(live: feed.live)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: ChatBottom.width, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            }
        }
    }

    /// Loads the page before the oldest shown, then scrolls back to the message that was first, so
    /// the page arrives above what the human was reading instead of moving it.
    private func loadOlder(_ scroll: ScrollViewProxy) {
        guard feed.more, !feed.loadingOlder, let first = feed.rows.first?.id else { return }
        feed.loadOlder(target, client: model.client) {
            scroll.scrollTo(first, anchor: .top)
        }
    }

    /// The Worker this chat is, while its row is in the ledger.
    private var worker: WorkerRow? {
        guard case .worker(let number) = target else { return nil }
        return model.snapshot(repo).workers.first { $0.number == number }
    }

    private func follow() async {
        let client = model.client
        let target = target
        while !Task.isCancelled {
            let log = feed.log
            let result = await Task.detached { try? client.chat(target, after: log) }.value
            if let result, !Task.isCancelled { feed.take(result) }
            try? await Task.sleep(for: Self.poll)
        }
    }
}

/// One chat's items and which rows the human opened. Only a read that changes what shows
/// publishes, so a quiet chat's polls redraw nothing.
@MainActor
final class ChatFeed: ObservableObject {
    private(set) var log = ChatLog()
    /// The terminal's state, observed on its own: the spinner changes every second, and only the
    /// Working row and message box should redraw for it.
    let live = ChatLive()
    @Published private(set) var rows: [ChatRow] = []
    @Published private(set) var loaded = false
    @Published private(set) var supported = true
    /// Older messages are left to load, and one page is loading.
    @Published private(set) var more = false
    @Published private(set) var loadingOlder = false
    @Published var open: Set<String> = []
    /// Each reply's Markdown, parsed once.
    private var parsed: [String: [MarkdownBlock]] = [:]

    func take(_ result: [String: Any]) {
        if log.apply(result) {
            let rows = log.rows
            if rows != self.rows { self.rows = rows }
            if supported != log.supported { supported = log.supported }
            if more != log.more { more = log.more }
            if live.state != log.state { live.state = log.state }
        }
        if !loaded { loaded = true }
    }

    /// Loads the page before the oldest shown: earlier in this session, or the session before a renewal.
    func loadOlder(_ target: TerminalTarget, client: DaemonClient, loaded: @escaping () -> Void = {}) {
        guard !loadingOlder, more else { return }
        loadingOlder = true
        let log = log
        Task {
            let result = await Task.detached { try? client.chatOlder(target, before: log) }.value
            loadingOlder = false
            // A read that started a new session meanwhile starts the chat over; drop the page.
            guard let result, self.log.session == log.session else { return }
            if self.log.applyOlder(result) {
                rows = self.log.rows
            }
            more = self.log.more
            loaded()
        }
    }

    func blocks(_ item: ChatItem) -> [MarkdownBlock] {
        if let blocks = parsed[item.id] { return blocks }
        let blocks = parseMarkdown(item.text)
        parsed[item.id] = blocks
        return blocks
    }

    func toggle(_ id: String) {
        if open.contains(id) { open.remove(id) } else { open.insert(id) }
    }
}

@MainActor
final class ChatLive: ObservableObject {
    @Published var state = ChatState()
}

/// The text being written in a chat's message box, and what became of the last send.
@MainActor
final class Composer: ObservableObject {
    @Published var text = ""
    @Published var sending = false
    @Published var error: String?
    /// Files to send with the message: pasted or dropped images and files, as paths.
    @Published var files: [URL] = []
    /// What `/` completes, read from the daemon once; the highlighted one.
    @Published var commands: [SlashCommand]?
    @Published var pick = 0
}

/// Under the chat: the agent's own prompt to settle, what it is doing, and the message box.
private struct ChatBottom: View {
    @EnvironmentObject private var model: AppModel
    let repo: String
    let target: TerminalTarget
    @ObservedObject var live: ChatLive
    @ObservedObject var composer: Composer
    @FocusState private var focused: Bool
    @StateObject private var pasteWatch = PasteWatch()

    /// The chat's column, shared by the messages and the box under them.
    static let width: CGFloat = 1200

    var body: some View {
        let state = live.state
        VStack(alignment: .leading, spacing: 10) {
            // Its own prompts, as in Needs you; settling one here settles it there (ADR 0010).
            ForEach(needs) { need in NeedItem(need: need, repo: repo) }
            if state.look == .prompt && needs.isEmpty {
                Text("It shows a prompt Echo cannot draw yet. Press ⇧⌘T to answer it in the terminal.")
                    .font(Ledger.font(12.5))
                    .foregroundStyle(Ledger.ink2)
            }
            if let worker = settledWorker {
                Text("\(worker.id) is \(worker.phaseLabel.lowercased()). The Orchestrator gives it its next Task.")
                    .font(Ledger.font(12.5))
                    .foregroundStyle(Ledger.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else if state.live {
                box(state)
            } else {
                Text(stoppedLine)
                    .font(Ledger.font(12.5))
                    .foregroundStyle(Ledger.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            if let error = composer.error {
                Text(error).font(Ledger.font(12)).foregroundStyle(Ledger.fail)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: Self.width)
        .frame(maxWidth: .infinity)
        .onAppear {
            takeFocus()
            pasteWatch.start(paste: pasteFiles)
        }
        .onDisappear { pasteWatch.stop() }
        .onChange(of: focused) { _, now in pasteWatch.active = now }
        // The closure holds this view's composer, which is another agent's after a switch.
        .onChange(of: target) { pasteWatch.start(paste: pasteFiles) }
        .onChange(of: model.terminalFocusRequest) { takeFocus() }
    }

    /// A Worker that sent its Final Report, or stopped without one: it takes no typing (as its
    /// terminal is not shown either), only its next Task.
    private var settledWorker: WorkerRow? {
        guard case .worker(let number) = target,
              let worker = model.snapshot(repo).workers.first(where: { $0.number == number }), !worker.isActive else { return nil }
        return worker
    }

    private var stoppedLine: String {
        guard case .worker = target else { return "Stopped. Start it to talk to it; its shell is in the terminal (⇧⌘T)." }
        return "Its terminal is closed. The Orchestrator gives it its next Task."
    }

    /// An agent's own Needs; a Worker's show in the ledger's Needs you.
    private var needs: [Need] {
        guard case .agent(let id) = target else { return [] }
        return (model.snapshot(repo).groups.first { $0.agent.id == id }?.needs ?? []).filter { $0.worker == nil }
    }

    /// Typing into a Worker is an Intervention (CONTEXT.md); the box says so.
    private var placeholder: String {
        guard case .worker = target else { return "Reply to Claude…" }
        return "Intervention: \(target.label) does what you ask and tells the Orchestrator"
    }

    private var matches: [SlashCommand] {
        SlashCommand.matches(composer.text, in: composer.commands ?? [])
    }

    private func box(_ state: ChatState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !matches.isEmpty {
                CommandList(commands: Array(matches.prefix(8)), pick: min(composer.pick, min(matches.count, 8) - 1)) { command in
                    complete(command)
                }
            }
            if !composer.files.isEmpty {
                FileChips(files: composer.files) { file in composer.files.removeAll { $0 == file } }
            }
            field(state)
        }
        .onChange(of: composer.text) { _, text in
            composer.pick = 0
            if text.hasPrefix("/"), composer.commands == nil { loadCommands() }
        }
    }

    private func field(_ state: ChatState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $composer.text, axis: .vertical)
                .lineLimit(1...10)
                .textFieldStyle(.plain)
                .font(Ledger.font(15))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    // Shift-Return is a new line; Return completes a command, or sends.
                    if press.modifiers.contains(.shift) {
                        composer.text += "\n"
                    } else if let command = highlighted, "/" + command.name != composer.text {
                        complete(command)
                    } else {
                        send()
                    }
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard let command = highlighted else { return .ignored }
                    complete(command)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !matches.isEmpty else { return .ignored }
                    composer.pick = max(composer.pick - 1, 0)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard !matches.isEmpty else { return .ignored }
                    composer.pick = min(composer.pick + 1, min(matches.count, 8) - 1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    if !matches.isEmpty {
                        composer.text = ""
                        return .handled
                    }
                    guard state.look == .working else { return .ignored }
                    interrupt()
                    return .handled
                }
            HStack(spacing: 6) {
                Button(action: attach) {
                    Image(systemName: "plus")
                        .font(.system(size: 15))
                        .foregroundStyle(Ledger.ink2)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach files or images")
                .accessibilityLabel("Attach")
                Spacer(minLength: 8)
                if let name = modelName {
                    Text(name).font(Ledger.font(13)).foregroundStyle(Ledger.ink3).lineLimit(1)
                }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ledger.onPrimary)
                        .frame(width: 32, height: 32)
                        .background(Ledger.primary.opacity(canSend ? 1 : 0.4),
                                    in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send (Return). Shift-Return adds a line.")
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Ledger.field, in: RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous)
            .strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }

    /// The model the agent runs, as Claude's box names it beside the send button.
    private var modelName: String? {
        let raw: String?
        switch target {
        case .agent(let id): raw = model.agents(repo).first { $0.id == id }?.model
        case .worker(let number): raw = model.snapshot(repo).workers.first { $0.number == number }?.model
        default: raw = nil
        }
        guard let raw else { return nil }
        let name = AgentLine.short(raw)
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private var canSend: Bool {
        !composer.sending && (!composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !composer.files.isEmpty)
    }

    private var highlighted: SlashCommand? {
        let shown = matches.prefix(8)
        return shown.isEmpty ? nil : shown[min(composer.pick, shown.count - 1)]
    }

    private func complete(_ command: SlashCommand) {
        composer.text = "/" + command.name + " "
    }

    private func loadCommands() {
        composer.commands = []
        let client = model.client
        let target = target
        let composer = composer
        Task {
            let commands = await Task.detached { (try? client.chatCommands(target)) ?? [] }.value
            composer.commands = commands
        }
    }

    private func attach() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { composer.files += panel.urls }
    }

    /// Attaches the clipboard's files, or its image saved as a PNG; false when it holds neither,
    /// or holds text too, which pastes as text.
    private func pasteFiles() -> Bool {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            composer.files += urls
            return true
        }
        guard board.string(forType: .string) == nil, let image = NSImage(pasteboard: board),
              let file = ChatAttachments.save(image) else { return false }
        composer.files.append(file)
        return true
    }

    private func takeFocus() {
        guard !focused else { return }
        DispatchQueue.main.async { focused = true }
    }

    /// Clears the box at once; the message shows once the transcript has it. A refused send
    /// puts the text back with the reason.
    private func send() {
        let typed = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        let files = composer.files
        // Files go as their paths, as a drop into the terminal types them; Claude Code reads them.
        let text = ([typed] + files.map { ChatAttachments.quoted($0.path) }).filter { !$0.isEmpty }.joined(separator: " ")
        // A command with a menu draws it in the terminal, so the terminal shows for it.
        let menu = (composer.commands ?? []).contains { $0.menu && (typed == "/" + $0.name || typed.hasPrefix("/" + $0.name + " ")) }
        composer.text = ""
        composer.files = []
        composer.error = nil
        composer.sending = true
        let client = model.client
        let target = target
        let composer = composer
        Task {
            let failure = await Task.detached { () -> String? in
                do { try client.chatSend(target, text: text); return nil } catch { return "\(error)" }
            }.value
            composer.sending = false
            if let failure {
                composer.error = failure
                if composer.text.isEmpty { composer.text = typed }
                if composer.files.isEmpty { composer.files = files }
            } else if menu {
                model.setChat(target, on: false)
            }
        }
    }

    private func interrupt() {
        let client = model.client
        let target = target
        Task.detached { try? client.chatInterrupt(target) }
    }
}

/// While a turn runs: what the agent is doing, from its screen; nothing otherwise.
private struct WorkingRow: View {
    @ObservedObject var live: ChatLive

    var body: some View {
        if let step = live.state.working {
            row(step: step, spinner: live.state.spinner)
        }
    }

    private func row(step: String, spinner: String?) -> some View {
        HStack(spacing: 8) {
            Spinner(color: Ledger.primary, size: 14, period: 1.4)
            Text(step).foregroundStyle(Ledger.ink2).lineLimit(1).truncationMode(.middle)
            if let spinner, let open = spinner.range(of: " (") {
                Text(spinner[open.upperBound...].dropLast().description).foregroundStyle(Ledger.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("Esc to interrupt").foregroundStyle(Ledger.ink3)
        }
        .font(Ledger.font(13))
    }
}

private struct ChatRowView: View {
    let row: ChatRow
    @ObservedObject var feed: ChatFeed

    var body: some View {
        switch row {
        case .item(let item):
            switch item.kind {
            case .user: UserBubble(text: item.text, fromOrchestrator: item.from == "orchestrator")
            case .reply: ReplyView(item: item, blocks: feed.blocks(item))
            case .event: EventLine(text: item.text)
            case .divider: Divider(label: item.text)
            case .tool: ToolRow(item: item, feed: feed)
            }
        case .tools(let run) where run.count == 1:
            ToolRow(item: run[0], feed: feed)
        case .tools(let run):
            ToolGroup(id: row.id, run: run, feed: feed)
        }
    }

    private struct Divider: View {
        let label: String
        var body: some View {
            HStack(spacing: 10) {
                Rectangle().fill(Ledger.rule).frame(height: 1)
                Text(label).font(Ledger.font(12)).foregroundStyle(Ledger.ink3).fixedSize()
                Rectangle().fill(Ledger.rule).frame(height: 1)
            }
            .padding(.vertical, 4)
        }
    }
}

/// What the human typed, on the right.
private struct UserBubble: View {
    let text: String
    /// Typed into a Worker by its Orchestrator: on the left, labelled, since the human did not say it.
    let fromOrchestrator: Bool

    var body: some View {
        HStack {
            if !fromOrchestrator { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 6) {
                if fromOrchestrator {
                    Text("From Orchestrator").font(Ledger.font(12, .medium)).foregroundStyle(Ledger.ink3)
                }
                ChatText(source: .plain(text), size: 15, leading: 5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Ledger.bubble, in: RoundedRectangle(cornerRadius: Ledger.radiusCard, style: .continuous))
            if fromOrchestrator { Spacer(minLength: 80) }
        }
    }
}

/// A settled Worker's Final Report, closing its chat: its sections as the report view draws them.
private struct FinalReportCard: View {
    let worker: WorkerRow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(worker.finalReport == nil ? "No Final Report" : "Final Report").font(Ledger.font(15, .semibold))
                Spacer(minLength: 8)
                Text(worker.phaseLabel).font(Ledger.font(12.5)).foregroundStyle(worker.markColor)
            }
            if let report = worker.finalReport {
                ForEach(Array(ReportSection.parse(report).enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 6) {
                        if let title = section.title {
                            Text(title).font(Ledger.font(13, .semibold)).foregroundStyle(Ledger.ink2)
                        }
                        let tone = section.title == "State" && worker.isTrouble ? Ledger.fail : Ledger.ink
                        ChatMarkdown(blocks: parseMarkdown(section.body), size: 14, color: tone)
                            .foregroundStyle(tone)
                    }
                }
            } else {
                Text("\(worker.id) \(worker.phaseLabel.lowercased()) without sending one. The Orchestrator has been told.")
                    .foregroundStyle(Ledger.ink2)
            }
        }
        .font(Ledger.font(14))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Ledger.radiusCard, style: .continuous).strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
    }
}

/// The agent's text, full width; an amber edge when its Needs you section lists something.
private struct ReplyView: View {
    let item: ChatItem
    let blocks: [MarkdownBlock]

    var body: some View {
        ChatMarkdown(blocks: blocks)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, item.needsHuman ? 14 : 0)
        .overlay(alignment: .leading) {
            if item.needsHuman {
                RoundedRectangle(cornerRadius: 1.5).fill(Ledger.changed).frame(width: 3)
            }
        }
    }
}

/// A background note, such as a task notification: one dim line.
private struct EventLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Ledger.font(12.5))
            .foregroundStyle(Ledger.ink3)
            .lineLimit(2)
            .truncationMode(.tail)
            .help(text)
    }
}

/// Claude's mark for a tool call: a symbol by what the tool does.
private func toolIcon(_ name: String?) -> String {
    switch name {
    case "Bash", "BashOutput", "KillShell": return "terminal"
    case "Edit", "MultiEdit", "Write", "NotebookEdit": return "pencil"
    case "Read": return "doc.text"
    case "Grep", "Glob": return "magnifyingglass"
    case "WebFetch", "WebSearch": return "globe"
    case "Task", "Agent": return "person.2"
    default: return "wrench.and.screwdriver"
    }
}

private extension View {
    /// A tool call's card: Claude's half-point border on the canvas.
    func toolCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: Ledger.radiusCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Ledger.radiusCard, style: .continuous)
                .strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
    }
}

private struct Hairline: View {
    var body: some View { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
}

/// Several tool calls in a row, folded to "6 tool calls" until opened.
private struct ToolGroup: View {
    let id: String
    let run: [ChatItem]
    @ObservedObject var feed: ChatFeed

    var body: some View {
        let open = feed.open.contains(id)
        VStack(alignment: .leading, spacing: 0) {
            Button { feed.toggle(id) } label: {
                FoldLabel(icon: "wrench.and.screwdriver", open: open, failed: run.contains(where: \.failed)) {
                    Text("\(run.count) tool calls").foregroundStyle(Ledger.ink2)
                    Text(run.compactMap(\.tool).uniqued().joined(separator: ", "))
                        .foregroundStyle(Ledger.ink3)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            if open {
                ForEach(run) { item in
                    Hairline()
                    ToolRow(item: item, feed: feed, framed: false)
                }
            }
        }
        .toolCard()
    }
}

/// One tool call: its name and target, and when opened what it did.
private struct ToolRow: View {
    let item: ChatItem
    @ObservedObject var feed: ChatFeed
    /// Alone it is a card of its own; inside a group it is a row of the group's card.
    var framed = true

    var body: some View {
        let open = feed.open.contains(item.id)
        let column = VStack(alignment: .leading, spacing: 0) {
            Button { feed.toggle(item.id) } label: {
                FoldLabel(icon: toolIcon(item.tool), open: open, failed: item.failed) {
                    Text(item.tool ?? "Tool").fontWeight(.medium).foregroundStyle(Ledger.ink2)
                    Text(item.summary ?? "")
                        .font(Ledger.mono)
                        .foregroundStyle(Ledger.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            if open {
                Hairline()
                ToolDetail(item: item).padding(12)
            }
        }
        if framed { column.toolCard() } else { column }
    }
}

private struct FoldLabel<Content: View>: View {
    let icon: String
    let open: Bool
    let failed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Ledger.ink3)
                .frame(width: 16)
            content
            if failed {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Ledger.fail)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(open ? 90 : 0))
                .foregroundStyle(Ledger.ink3)
        }
        .font(Ledger.font(13))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// An opened tool call: the command or prompt, an edit's lines, and the output.
private struct ToolDetail: View {
    let item: ChatItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let detail = item.detail, !detail.isEmpty { Mono(text: detail) }
            if item.old != nil || item.new != nil { EditLines(old: item.old ?? "", new: item.new ?? "") }
            if let output = item.output, !output.isEmpty {
                Mono(text: output).foregroundStyle(item.failed ? Ledger.fail : Ledger.ink2)
            } else if item.output == nil {
                Text("No output yet").font(Ledger.font(12)).foregroundStyle(Ledger.ink3)
            }
        }
    }

    private struct Mono: View {
        let text: String
        var body: some View {
            Text(text)
                .font(Ledger.mono)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ledger.wash, in: RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
        }
    }
}

/// An edit as removed and added lines, coloured as the Changes column colours a diff.
private struct EditLines: View {
    let old: String
    let new: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text((line.added ? "+ " : "- ") + line.text)
                    .font(Ledger.mono)
                    .foregroundStyle(line.added ? Ledger.okInk : Ledger.failInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(line.added ? Ledger.okWash : Ledger.failWash)
            }
        }
        .textSelection(.enabled)
        .clipShape(RoundedRectangle(cornerRadius: Ledger.radiusElement, style: .continuous))
    }

    private var lines: [(added: Bool, text: String)] {
        let removed = old.isEmpty ? [] : old.components(separatedBy: "\n").map { (added: false, text: $0) }
        let added = new.isEmpty ? [] : new.components(separatedBy: "\n").map { (added: true, text: $0) }
        return removed + added
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

/// Under the box while a `/` is typed: the commands it completes, the highlighted one filled.
private struct CommandList: View {
    let commands: [SlashCommand]
    let pick: Int
    let choose: (SlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                Button { choose(command) } label: {
                    HStack(spacing: 10) {
                        Text("/" + command.name).font(Ledger.mono).foregroundStyle(Ledger.ink)
                        Text(command.description).foregroundStyle(Ledger.ink3).lineLimit(1)
                        Spacer(minLength: 8)
                        if command.menu {
                            Text("Opens in the terminal").font(Ledger.font(11.5)).foregroundStyle(Ledger.ink3)
                        }
                    }
                    .font(Ledger.font(12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(index == pick ? Ledger.selected : .clear, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Ledger.field, in: RoundedRectangle(cornerRadius: Ledger.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ledger.radiusCard, style: .continuous).strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

/// The files a message will carry, each with a button to take it off.
private struct FileChips: View {
    let files: [URL]
    let remove: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(files, id: \.self) { file in
                    HStack(spacing: 6) {
                        Image(systemName: ChatAttachments.isImage(file) ? "photo" : "doc")
                        Text(file.lastPathComponent).lineLimit(1)
                        Button { remove(file) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(file.lastPathComponent)")
                    }
                    .font(Ledger.font(12))
                    .foregroundStyle(Ledger.ink2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Ledger.wash, in: Capsule())
                    .help(file.path)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Where a pasted image is saved for the agent to read, and how a path is typed.
enum ChatAttachments {
    static func save(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("echo-pastes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("pasted-\(UUID().uuidString.prefix(8)).png")
        return (try? png.write(to: file)) == nil ? nil : file
    }

    static func isImage(_ file: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(file.pathExtension.lowercased())
    }

    /// A path as a drop into a terminal types it: spaces and quotes escaped.
    static func quoted(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: " ", with: "\\ ")
            .replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// ⌘V while the message box has the keyboard: an image or files on the clipboard are attached
/// instead of pasted. A local event monitor sees the key before the Edit menu's Paste takes it.
@MainActor
final class PasteWatch: ObservableObject {
    var active = false
    private var paste: () -> Bool = { false }
    private var monitor: Any?

    func start(paste: @escaping () -> Bool) {
        self.paste = paste
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.active, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v" else { return event }
            return self.paste() ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

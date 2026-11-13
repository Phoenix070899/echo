import Foundation

/// One item of an agent's conversation, as the daemon's `chat.read` gives it (ADR 0010).
public struct ChatItem: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        /// What the human typed, or a slash command.
        case user
        /// The agent's text.
        case reply
        /// One tool call; `output` arrives with a later read.
        case tool
        /// A background note: a task notification, a command's output.
        case event
        /// The context was compacted.
        case divider
    }

    public let id: String
    public let kind: Kind
    public var text: String
    /// A tool call's name, the short target its folded row shows, and what it shows expanded.
    public var tool: String?
    public var summary: String?
    public var detail: String?
    public var old: String?
    public var new: String?
    public var output: String?
    public var failed = false
    /// Who typed a `user` item into a Worker: `orchestrator`, or nil for the human.
    public var from: String?

    public init(id: String, kind: Kind, text: String = "", tool: String? = nil, summary: String? = nil,
                detail: String? = nil, old: String? = nil, new: String? = nil, output: String? = nil, failed: Bool = false,
                from: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.tool = tool
        self.summary = summary
        self.detail = detail
        self.old = old
        self.new = new
        self.output = output
        self.failed = failed
        self.from = from
    }

    /// A reply whose Needs you section lists something other than "Nothing" or "None", drawn
    /// with an amber edge; the same rule as the mod's `needsHuman` (`mod/hooks/report.ts`).
    public var needsHuman: Bool {
        guard kind == .reply else { return false }
        let section = #/^\s*(?:#+\s*|\*\*)?(?i:(needs you|done|running))\b/#
        let entry = #/^\s*(?:[-*]|\d+\.)\s+(.*)$/#
        let nothing = #/^(?i:nothing|none)\b/#
        var inNeedsYou = false
        for line in text.components(separatedBy: "\n") {
            if let match = line.firstMatch(of: section) {
                inNeedsYou = match.1.lowercased() == "needs you"
                let rest = line[match.range.upperBound...]
                    .drop { $0 == "*" || $0 == ":" || $0 == "-" || $0.isWhitespace }
                    .trimmingCharacters(in: .whitespaces)
                if inNeedsYou, !rest.isEmpty, rest.firstMatch(of: nothing) == nil { return true }
                continue
            }
            if inNeedsYou, let match = line.firstMatch(of: entry),
               String(match.1).trimmingCharacters(in: .whitespaces).firstMatch(of: nothing) == nil {
                return true
            }
        }
        return false
    }
}

/// What the agent's terminal shows now, for the chat's Working row and message box.
public struct ChatState: Equatable, Sendable {
    public enum Look: String, Sendable {
        case stopped, trust, prompt, working, waiting, idle
    }

    public var live = false
    public var look: Look = .stopped
    /// While it works: the spinner line ("Nesting… (3s · ↓ 89 tokens)") and its current step.
    public var spinner: String?
    public var step: String?

    public init(live: Bool = false, look: Look = .stopped, spinner: String? = nil, step: String? = nil) {
        self.live = live
        self.look = look
        self.spinner = spinner
        self.step = step
    }

    init(_ raw: [String: Any]?) {
        live = raw?["live"] as? Bool ?? false
        look = Look(rawValue: raw?["look"] as? String ?? "") ?? .stopped
        spinner = raw?["spinner"] as? String
        step = raw?["step"] as? String
    }

    /// The Working row's text: the step, else the spinner, while a turn runs.
    public var working: String? {
        guard look == .working else { return nil }
        return step ?? spinner.map { $0.components(separatedBy: " (").first ?? $0 } ?? "Working"
    }
}

/// An agent's conversation so far, kept current one `chat.read` at a time.
public struct ChatLog: Equatable, Sendable {
    public private(set) var session: String?
    /// Where the next read continues in the transcript.
    public private(set) var end: Int = 0
    public private(set) var items: [ChatItem] = []
    /// False for an agent whose CLI keeps no transcript Echo reads (Codex and Kiro, for now).
    public private(set) var supported = true
    public private(set) var state = ChatState()
    /// Whether older messages are left to load, and where the oldest page loaded begins: an offset
    /// in `pageSession`, the current session or one before a renewal.
    public private(set) var more = false
    private var start = 0
    private var pageSession: String?
    /// Results whose calls are not loaded yet, kept for when an older page brings them.
    private var orphans: [String: (text: String, failed: Bool)] = [:]

    public init() {}

    public static func == (a: ChatLog, b: ChatLog) -> Bool {
        a.session == b.session && a.end == b.end && a.items == b.items && a.supported == b.supported
            && a.state == b.state && a.more == b.more && a.start == b.start && a.pageSession == b.pageSession
    }

    /// What the next `chat.read` asks for.
    public var request: [String: Any] {
        guard let session else { return [:] }
        return ["session": session, "after": end]
    }

    /// What a `chat.read` for the page before the oldest loaded asks for.
    public var olderRequest: [String: Any]? {
        guard more, let pageSession else { return nil }
        return ["before": start, "page_session": pageSession]
    }

    /// Takes a `chat.read` result in; true when anything the view shows changed.
    @discardableResult
    public mutating func apply(_ result: [String: Any]) -> Bool {
        let session = result["session"] as? String
        let fresh = session != self.session
        let before = (items, supported, state, more)
        if fresh {
            items = []
            orphans = [:]
            start = result["start"] as? Int ?? 0
            more = result["more"] as? Bool ?? false
            pageSession = session
        }
        self.session = session
        supported = result["supported"] as? Bool ?? true
        state = ChatState(result["state"] as? [String: Any])
        end = result["end"] as? Int ?? end
        items = merge(items, result["items"] as? [[String: Any]] ?? [], older: false)
        return fresh || before.0 != items || before.1 != supported || before.2 != state || before.3 != more
    }

    /// Takes an older page in, before the items loaded; true when it brought anything.
    @discardableResult
    public mutating func applyOlder(_ result: [String: Any]) -> Bool {
        let before = (items.count, more)
        start = result["start"] as? Int ?? 0
        pageSession = result["page_session"] as? String ?? pageSession
        more = result["more"] as? Bool ?? false
        items = merge([], result["items"] as? [[String: Any]] ?? [], older: true) + items
        return before != (items.count, more)
    }

    /// `items` with the raw ones after them; a result fills its call, here or once it loads.
    private mutating func merge(_ items: [ChatItem], _ raws: [[String: Any]], older: Bool) -> [ChatItem] {
        var items = items
        var at: [String: Int] = [:]
        for (index, item) in items.enumerated() where item.kind == .tool {
            at[item.id] = index
        }
        for raw in raws {
            let id = raw["id"] as? String ?? UUID().uuidString
            let text = raw["text"] as? String ?? ""
            if raw["kind"] as? String == "result" {
                let failed = raw["error"] as? Bool ?? false
                if let index = at[id] {
                    items[index].output = text
                    items[index].failed = failed
                } else {
                    orphans[id] = (text, failed)
                }
                continue
            }
            guard let kind = ChatItem.Kind(rawValue: raw["kind"] as? String ?? "") else { continue }
            var item = ChatItem(id: id, kind: kind, text: text, tool: raw["tool"] as? String,
                                summary: raw["summary"] as? String, detail: raw["detail"] as? String,
                                old: raw["old"] as? String, new: raw["new"] as? String, from: raw["from"] as? String)
            if kind == .tool {
                at[id] = items.count
                if older, let result = orphans.removeValue(forKey: id) {
                    item.output = result.text
                    item.failed = result.failed
                }
            }
            items.append(item)
        }
        return items
    }

    /// The rows the chat draws: each item, with a run of tool calls as one group.
    public var rows: [ChatRow] {
        var rows: [ChatRow] = []
        for item in items {
            if item.kind == .tool, case .tools(let run)? = rows.last {
                rows[rows.count - 1] = .tools(run + [item])
            } else {
                rows.append(item.kind == .tool ? .tools([item]) : .item(item))
            }
        }
        return rows
    }
}

public enum ChatRow: Equatable, Identifiable, Sendable {
    case item(ChatItem)
    /// Tool calls in a row; one call draws as its own row.
    case tools([ChatItem])

    public var id: String {
        switch self {
        case .item(let item): return item.id
        case .tools(let run): return "tools " + (run.first?.id ?? "")
        }
    }
}

/// A slash command the chat's message box completes; one with a menu shows it in the terminal.
public struct SlashCommand: Equatable, Hashable, Sendable {
    public let name: String
    public let description: String
    public let menu: Bool

    public init(name: String, description: String, menu: Bool) {
        self.name = name
        self.description = description
        self.menu = menu
    }

    /// The commands a `/` draft completes to: names starting with what follows the slash first,
    /// then names containing it; nothing once the draft has a space.
    public static func matches(_ draft: String, in commands: [SlashCommand]) -> [SlashCommand] {
        guard draft.hasPrefix("/"), !draft.contains(where: \.isWhitespace) else { return [] }
        let typed = draft.dropFirst().lowercased()
        let starts = commands.filter { $0.name.lowercased().hasPrefix(typed) }
        let contains = commands.filter { !$0.name.lowercased().hasPrefix(typed) && $0.name.lowercased().contains(typed) }
        return starts + contains
    }
}

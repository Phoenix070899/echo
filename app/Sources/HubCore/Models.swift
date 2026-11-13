import Foundation

/// One of a repo's agents: an Orchestrator, or a Normal session (plain Claude Code).
public struct Agent: Decodable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case orchestrator
        case claude
        /// A plain shell in the repo, with no agent in it.
        case terminal

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .orchestrator
        }
    }

    public let id: Int
    public let kind: Kind
    /// What the human called it, or what their first request was about; nil until then.
    public let name: String?
    public let model: String?
    /// The Team an Orchestrator was started with, by name; nil for any other agent.
    public let team: String?
    public let live: Bool
    /// The branch it works on, when the human picked or made one for it.
    public let branch: String?
    /// Its own worktree; nil when it works in the repo's checkout.
    public let cwd: String?
    /// The branch checked out where it works, now; nil when HEAD is detached.
    public let head: String?

    public init(id: Int, kind: Kind, name: String? = nil, model: String? = nil, team: String? = nil,
                live: Bool = false, branch: String? = nil, cwd: String? = nil, head: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.model = model
        self.team = team
        self.live = live
        self.branch = branch
        self.cwd = cwd
        self.head = head
    }

    public var isOrchestrator: Bool { kind == .orchestrator }
    public var isTerminal: Bool { kind == .terminal }

    /// What it is, as menus and titles say it.
    public var kindName: String {
        switch kind {
        case .orchestrator: return "Orchestrator"
        case .claude: return "Claude Code"
        case .terminal: return "Terminal"
        }
    }

    /// Its name, or until the first request names it, the branch it works on; on a detached
    /// HEAD, what it is and its id ("Orchestrator a3", as `echoctl attach a3` reads).
    public var displayName: String { name ?? branch ?? head ?? "\(kindName) a\(id)" }
}

/// One agent's share of a repo's ledger: what it is waiting on, and its Workers.
public struct AgentGroup: Identifiable, Equatable, Sendable {
    public let agent: Agent
    public let needs: [Need]
    public let running: [WorkerRow]
    public let settled: [WorkerRow]

    public var id: Int { agent.id }
}

/// One repo as the daemon's `events` stream draws it: its agents, their Workers, what needs you.
/// One `echoctl ui` request: open a file, show a Worker or agent or a Worker's diff, or notify.
public struct UiRequest: Decodable, Equatable, Sendable {
    public let id: String
    /// Unix seconds.
    public let at: Int
    public let action: String
    /// Who asked: `w12` or `a3`, or nil from a plain terminal.
    public let from: String?
    /// `open`: the checkout, the path in it, and the 1-based line.
    public let root: String?
    public let path: String?
    public let line: Int?
    /// `show` and `diff`: the Worker (`w12`) or the agent.
    public let worker: String?
    public let agent: Int?
    /// `notify`.
    public let text: String?
}

public struct Snapshot: Decodable, Equatable, Sendable {
    public struct Orchestrator: Decodable, Equatable, Sendable {
        public let live: Bool
        /// The model the human picked for this session; nil means the `claude` default.
        public let model: String?

        public init(live: Bool, model: String? = nil) {
            self.live = live
            self.model = model
        }
    }

    public let repo: String
    /// The repo's first Orchestrator, as older daemons describe it.
    public let orchestrator: Orchestrator
    /// Every open agent, oldest first; nil from a daemon older than agents.
    public let agents: [Agent]?
    public let workers: [WorkerRow]
    public let needs: [Need]
    /// Account-wide; every session's snapshot carries the same.
    public let usage: Usage?
    /// What agents asked Echo to show with `echoctl ui`, for the last half minute.
    public let ui: [UiRequest]?

    public init(
        repo: String, orchestrator: Orchestrator, agents: [Agent]? = nil, workers: [WorkerRow],
        needs: [Need], usage: Usage? = nil, ui: [UiRequest]? = nil
    ) {
        self.repo = repo
        self.orchestrator = orchestrator
        self.agents = agents
        self.workers = workers
        self.needs = needs
        self.usage = usage
        self.ui = ui
    }

    public static func empty(repo: String) -> Snapshot {
        Snapshot(repo: repo, orchestrator: Orchestrator(live: false), workers: [], needs: [])
    }

    public var needsYouCount: Int { needs.count }

    /// The ledger, one group per agent. A Worker or Need whose Orchestrator is gone, or that
    /// predates agents, belongs to the first Orchestrator, else the first agent.
    public var groups: [AgentGroup] {
        let list = agents ?? []
        let ids = Set(list.map(\.id))
        let first = list.first(where: \.isOrchestrator)?.id ?? list.first?.id
        func owner(_ agent: Int?) -> Int? {
            if let agent, ids.contains(agent) { return agent }
            return first
        }
        let running = running
        let settled = settled
        return list.map { agent in
            AgentGroup(
                agent: agent,
                needs: needs.filter { owner($0.agent) == agent.id },
                running: running.filter { owner($0.agent) == agent.id },
                settled: settled.filter { owner($0.agent) == agent.id }
            )
        }
    }

    /// Every Need in the ledger's order: each agent group's in turn, then any that belong to none.
    public var orderedNeeds: [Need] {
        let grouped = groups.flatMap(\.needs)
        let ids = Set(grouped.map(\.id))
        return grouped + needs.filter { !ids.contains($0.id) }
    }

    public func agent(_ id: Int) -> Agent? { agents?.first { $0.id == id } }

    /// The ledger's Running rows: live Workers with nothing waiting on the human, the
    /// longest-quiet first so a stuck one rises to the top.
    public var running: [WorkerRow] {
        let waiting = Set(needs.compactMap(\.worker))
        let now = Date()
        return workers
            .filter { $0.isActive && !waiting.contains($0.id) }
            .sorted { $0.quietFor(at: now) > $1.quietFor(at: now) }
    }

    /// The ledger's Done section: settled Workers, failed and blocked ones first, then newest.
    public var settled: [WorkerRow] {
        let now = Date()
        return workers
            .filter { !$0.isActive }
            .sorted { ($0.isTrouble ? 0 : 1, $0.quietFor(at: now)) < ($1.isTrouble ? 0 : 1, $1.quietFor(at: now)) }
    }
}

/// The account limits the daemon reads: Claude's plan limits, as `claude -p /usage` prints them,
/// and after them Kiro's credits when it knows them (features/0078).
public struct Usage: Decodable, Equatable, Sendable {
    /// One limit, e.g. "Session" 48% resetting "Oct 17 at 4:50pm".
    public struct Limit: Decodable, Equatable, Sendable, Identifiable {
        /// The name the daemon gives Kiro's credits entry.
        public static let kiroName = "Kiro credits"

        public let name: String
        public let percent: Int
        public let resets: String?
        /// Only Kiro's entry has it: the credits used and the plan's, "603.62 of 2000".
        public let detail: String?

        public var id: String { name }

        public init(name: String, percent: Int, resets: String?, detail: String? = nil) {
            self.name = name
            self.percent = percent
            self.resets = resets
            self.detail = detail
        }

        public var isKiro: Bool { name == Self.kiroName }

        /// The limit's line in the usage tooltip: Claude's as "Session: 48% used, resets Oct 17 at
        /// 4:50pm", Kiro's as "Kiro credits: 603.62 of 2000 credits, resets Dec 1".
        public var tooltip: String {
            let resetsText = resets.map { ", resets \($0)" } ?? ""
            if let detail, !detail.isEmpty { return "\(name): \(detail) credits" + resetsText }
            return "\(name): \(percent)% used" + resetsText
        }

        /// Time left until `resets`, e.g. "3h 40m" or "4d 11h"; nil when it does not read as a date.
        /// `/usage` prints it in this Mac's time zone without a year, so a date already past is next year's.
        public func resetsIn(now: Date = Date(), calendar: Calendar = .current) -> String? {
            guard let resets else { return nil }
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.calendar = calendar
            parser.timeZone = calendar.timeZone
            // "Dec 1" is Kiro's billing date, with no time: the day's start.
            let formats = ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d"]
            guard let parsed = formats.lazy.compactMap({ format -> Date? in
                parser.dateFormat = format
                return parser.date(from: resets)
            }).first else { return nil }
            var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
            parts.year = calendar.component(.year, from: now)
            guard var date = calendar.date(from: parts) else { return nil }
            // A day of slack, so a reset that has just passed is not read as next year's.
            if date < now.addingTimeInterval(-86_400) {
                date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
            }
            let minutes = max(0, Int(date.timeIntervalSince(now)) / 60)
            if minutes < 60 { return "\(minutes)m" }
            if minutes < 24 * 60 { return "\(minutes / 60)h \(minutes % 60)m" }
            return "\(minutes / (24 * 60))d \(minutes / 60 % 24)h"
        }
    }

    public let limits: [Limit]
    public let updatedAt: Int?
    public let error: String?
    public let refreshing: Bool

    public init(limits: [Limit], updatedAt: Int? = nil, error: String? = nil, refreshing: Bool = false) {
        self.limits = limits
        self.updatedAt = updatedAt
        self.error = error
        self.refreshing = refreshing
    }

    /// Claude's limits as drawn: the first two, Session and Week.
    public var claudeShown: [Limit] { Array(limits.filter { !$0.isKiro }.prefix(2)) }

    /// Whether Claude sent any limit; its `error` shows only when it did not.
    public var hasClaudeLimits: Bool { limits.contains { !$0.isKiro } }

    /// What the bar draws: Claude's two, then Kiro's credits, which show even when Claude sent none.
    public var shown: [Limit] { claudeShown + limits.filter(\.isKiro) }
}

/// A Worker's Dashboard state.
public enum WorkerState: String, Decodable, Sendable {
    case needsYou = "needs you"
    case running
    /// Live at its input box while background work it started runs: a shell, a monitor.
    case waiting
    case failed
    case done
    /// Stopped at its input box after a finished turn with no Final Report; its last screen stands in.
    case ended
}

public struct WorkerRow: Decodable, Equatable, Identifiable, Sendable {
    /// `w12`.
    public let id: String
    public let profile: String
    public let title: String
    public let state: WorkerState
    /// The Worker's lifecycle state: starting, running, done, ended, blocked, exited, lost.
    public let phase: String
    /// When it last reported (Unix seconds), so its quiet time counts up without a new snapshot,
    /// and an unchanged repo sends an unchanged snapshot.
    public let quietSince: Int?
    /// From a daemon older than `quietSince`.
    private let quietSeconds: Int?
    public let place: String
    public let branch: String?
    public let live: Bool
    public let blocker: String?
    public let finalReport: String?
    /// What it runs with: the CLI and model the daemon picked for it (a forced CLI included) and
    /// its Agent Profile's effort.
    public let model: String?
    public let effort: String?
    /// The CLI it runs on when that is not claude (`kiro`); nil for Claude and from an older daemon.
    public let cli: String?
    /// The first line of the Worker's latest status message.
    public let progress: String?
    /// The Orchestrator that started it.
    public let agent: Int?
    /// When it settled (Unix seconds); nil while it works.
    public let settledAt: Int?
    /// The fan-out it is one try of: Workers given the same Task, each on its own branch.
    public let fanout: String?
    /// The folder it works in; nil from a daemon older than the Files column.
    public let cwd: String?

    /// The daemon's numeric id, as `decide` and `attach` take it.
    public var number: Int? { Int(id.dropFirst()) }

    /// Seconds since it last reported.
    public func quietFor(at now: Date = Date()) -> Int {
        guard let quietSince else { return quietSeconds ?? 0 }
        return max(0, Int(now.timeIntervalSince1970) - quietSince)
    }

    /// Still working on its Task: starting or running, waiting on the human or not.
    public var isActive: Bool { phase == "starting" || phase == "running" }

    /// Settled badly: blocked, exited mid-turn without a Final Report, or lost. Ended is not
    /// trouble: the Worker finished its turn and only skipped the report.
    public var isTrouble: Bool { !isActive && phase != "done" && phase != "ended" }

    /// "claude-sonnet-5-5, high effort", and "kiro: claude-haiku-5-5, high effort" on another CLI.
    public var modelLine: String? {
        guard model != nil || cli != nil else { return nil }
        let name = model ?? "its own model"
        let line = effort.map { "\(name), \($0) effort" } ?? name
        return cli.map { "\($0): \(line)" } ?? line
    }
}

/// Something only the human can settle: a Worker's question or a waiting prompt, or a Normal
/// session's own permission prompt.
public struct Need: Decodable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case question
        case permissionPrompt = "permission_prompt"
        case idlePrompt = "idle_prompt"
        case other

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .other
        }
    }

    public let kind: Kind
    /// The daemon message id behind it: the question to answer, or the blocker report.
    public let message: Int
    /// The agent it belongs to: the Worker's Orchestrator, or the Normal session itself.
    public let agent: Int?
    /// The Worker asking; nil for a Normal session's own prompt.
    public let worker: String?
    public let profile: String
    public let title: String
    public let body: String
    /// For a permission prompt: its own lines, ending in "Do you want to ...".
    public let prompt: String?
    public let at: Int

    public var id: String {
        worker == nil ? "\(kind.rawValue)-agent-\(agent ?? 0)-\(at)" : "\(kind.rawValue)-\(message)"
    }

    /// A permission prompt's own lines without the closing question the buttons answer.
    public var promptLines: [String] {
        (prompt ?? "").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Do you want") }
    }

    /// What a permission prompt asks to run: its lines after the tool's name ("Bash command"),
    /// on one line. Falls back to the whole prompt when it has a single line.
    public var command: String? {
        let lines = promptLines
        guard !lines.isEmpty else { return nil }
        return (lines.count > 1 ? lines.dropFirst() : lines[...]).joined(separator: " ")
    }
}

/// Echo Remote, the phone web app the daemon serves (ADR 0008).
public struct RemoteStatus: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let running: Bool
    /// Why it is not serving as asked: the port taken, or Tailscale failing.
    public let error: String?
    /// Its address on this Mac, `http://127.0.0.1:7480`.
    public let local: String
    /// Its HTTPS address on the tailnet, once Tailscale is connected.
    public let url: String?
    /// "ready", "missing", "test", or what is wrong with Tailscale.
    public let tailscale: String
    /// The address with the pairing token; whoever opens it controls the agents.
    public let pairLink: String?
    /// Phones that turned on notifications.
    public let phones: Int
}

/// A repo the daemon knows, with its agents.
public struct SessionInfo: Decodable, Equatable, Identifiable, Sendable {
    public let repo: String
    /// Whether any of its agents is live.
    public let live: Bool
    public let model: String?
    public let agents: [Agent]?

    public init(repo: String, live: Bool, model: String? = nil, agents: [Agent]? = nil) {
        self.repo = repo
        self.live = live
        self.model = model
        self.agents = agents
    }

    public var id: String { repo }
    public var name: String { URL(fileURLWithPath: repo).lastPathComponent }

    /// Only Normal sessions, no Orchestrator: its tab gets the prompt mark.
    public var isNormalOnly: Bool {
        guard let agents, !agents.isEmpty else { return false }
        return agents.allSatisfy { !$0.isOrchestrator }
    }
}

/// What a terminal view shows.
public enum TerminalTarget: Hashable, Sendable {
    /// An Orchestrator or a Normal session.
    case agent(id: Int)
    case worker(id: Int)
    /// A checkout's own shell, shown under the Files column; it belongs to the folder, not to an agent.
    case side(root: String)

    /// The daemon's way of naming it in `attach` and `terminal.resize`.
    public var params: [String: Any] {
        switch self {
        case .agent(let id): return ["agent": id]
        case .worker(let id): return ["id": id]
        case .side(let root): return ["side": root]
        }
    }

    /// How the daemon's `chat.*` methods name it; a side shell has no chat.
    public var chatParams: [String: Any] {
        switch self {
        case .agent(let id): return ["agent": id]
        case .worker(let id): return ["worker": id]
        case .side: return [:]
        }
    }

    /// `a3`, `w21`, `t2f7573…`: how `echoctl attach` and multiplexer session names call it. A side
    /// shell is `t` and the hex of its path, so the label needs no quoting.
    public var label: String {
        switch self {
        case .agent(let id): return "a\(id)"
        case .worker(let id): return "w\(id)"
        case .side(let root): return "t" + root.utf8.map { String(format: "%02x", $0) }.joined()
        }
    }
}

/// Remembers which Needs were already announced, so each one notifies exactly once.
extension Snapshot {
    /// Workers running in `before` that have settled since (done, blocked, exited, or lost), for
    /// a notification each. A Worker seen first already settled is not one.
    public func justSettled(since before: Snapshot) -> [WorkerRow] {
        let running = Set(before.workers.filter(\.isActive).map(\.id))
        return workers.filter { running.contains($0.id) && !$0.isActive }
    }
}

public struct NeedTracker: Sendable {
    private var seen: Set<String> = []
    private var primed = false

    public init() {}

    /// Needs not seen before. The first snapshot only primes: what was already waiting when the
    /// app opened is shown in the inbox, not re-announced.
    public mutating func fresh(in needs: [Need]) -> [Need] {
        let new = needs.filter { !seen.contains($0.id) }
        seen.formUnion(needs.map(\.id))
        if !primed {
            primed = true
            return []
        }
        return new
    }
}

/// "45s", "3m", "2h".
public func formatAge(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    return "\(seconds / 3600)h"
}

/// "1 Worker running", "3 Workers at work": a count of Workers and what they are doing.
public func workers(_ count: Int, _ doing: String) -> String {
    "\(count) Worker\(count == 1 ? "" : "s") \(doing)"
}

/// The byte a tmux key like "C-b" sends, for typing the prefix into a terminal; nil for keys
/// that are not a plain Ctrl-letter (tmux's own notation, as `tmux show -gv prefix` prints it).
public func tmuxControlByte(_ key: String) -> UInt8? {
    let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if key == "C-Space" || key == "C-@" { return 0 }
    guard key.count == 3, key.hasPrefix("C-"), let letter = key.last?.asciiValue,
          (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(letter) else { return nil }
    return letter & 0x1f
}

/// How well `query` matches `text` for Quick open, higher first; nil when it does not. A word
/// that starts with the query beats the query inside a word, which beats its letters in order
/// ("rfu" finds "Rerank follow-ups"). Case is ignored; an empty query matches everything.
public func quickOpenScore(_ query: String, _ text: String) -> Int? {
    quickOpenScore(lowered: query.lowercased().trimmingCharacters(in: .whitespaces), text.lowercased())
}

/// `quickOpenScore` for a query and text already lowercased, with the query trimmed.
func quickOpenScore<Text: StringProtocol>(lowered query: String, _ text: Text) -> Int? {
    guard !query.isEmpty else { return 0 }
    if text.hasPrefix(query) { return 3 }
    if let range = text.range(of: query) {
        let before = range.lowerBound == text.startIndex ? " " : text[text.index(before: range.lowerBound)]
        return before.isLetter || before.isNumber ? 1 : 2
    }
    var rest = text[...]
    for character in query where character != " " {
        guard let found = rest.firstIndex(of: character) else { return nil }
        rest = rest[rest.index(after: found)...]
    }
    return 0
}

/// Dropped files as Terminal.app types them: each path with shell-special characters
/// backslash-escaped, separated by spaces, and a space after so typing can go on.
public func droppedPaths(_ paths: [String]) -> String {
    let plain = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+,@%=:")
    let escaped = paths.map { path in
        path.map { plain.contains($0) || !$0.isASCII ? String($0) : "\\\($0)" }.joined()
    }
    return escaped.joined(separator: " ") + " "
}

/// A GitHub issue as `gh issue view --json number,title,body,url` prints it, to start an agent on.
public struct GitHubIssue: Decodable, Equatable, Sendable {
    public let number: Int
    public let title: String
    public let body: String
    public let url: String

    /// The agent's name in the ledger: "#12 Flaky bench".
    public var name: String { "#\(number) \(title)" }

    /// The agent's first message: the whole issue, and what to do with it.
    public var request: String {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Work on GitHub issue #\(number): \(title)\n\(url)\n\n\(body.isEmpty ? "(The issue has no description.)" : body)"
    }
}

/// What `gh issue view` takes for an issue typed by hand: its URL, or its number with or without "#".
/// Nil for anything else.
public func issueReference(_ typed: String) -> String? {
    let text = typed.trimmingCharacters(in: .whitespaces)
    let number = text.hasPrefix("#") ? String(text.dropFirst()) : text
    if !number.isEmpty, number.allSatisfy(\.isASCII), Int(number) != nil { return number }
    if let url = URL(string: text), url.host == "github.com", url.pathComponents.count >= 5,
       url.pathComponents[3] == "issues", Int(url.pathComponents[4]) != nil {
        return text
    }
    return nil
}

/// An Agent Profile a Worker can run as, from `profiles.list`.
public struct WorkerProfile: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let description: String
    /// The model it runs with here, after the settings: "claude-haiku-5-5", or "claude default".
    public let model: String
    /// It edits files, so tries of one Task by it differ and are worth comparing.
    public let writes: Bool
    /// The CLI it runs with here.
    public var cli: String? = nil
    /// What its own file says; nil leaves it to the settings.
    public var ownCli: String? = nil
    public var ownModel: String? = nil
    public var effort: String? = nil
    /// Where it comes from: "built-in", "yours", or "repo".
    public var level: String? = nil
    public var path: String? = nil
    /// The levels below that it replaces.
    public var replaces: [String]? = nil
    /// Why it cannot run here, when its CLI and model do not fit.
    public var problem: String? = nil

    public var id: String { name }

    /// "yours, replaces built-in"
    public var origin: String {
        guard let level else { return "" }
        guard let below = replaces?.last else { return level }
        return "\(level), replaces \(below)"
    }
}

/// The human's Preferences and one repo's Lessons, from `memory.get`.
public struct MemoryFiles: Decodable, Equatable, Sendable {
    public struct Bullet: Decodable, Equatable, Hashable, Sendable {
        public let section: String
        public let text: String
    }

    public struct Preferences: Decodable, Equatable, Sendable {
        public let path: String
        public let sections: [String]
        public let bullets: [Bullet]
    }

    public struct Lessons: Decodable, Equatable, Sendable {
        public let path: String
        public let bullets: [Bullet]
        public let limit: Int
    }

    public let preferences: Preferences
    public let lessons: Lessons?
}

/// How a repo prepares its new worktrees, from `repo.settings.get`: ignored files to copy from
/// the main checkout, and a setup command run before the agent starts.
public struct RepoSettings: Decodable, Equatable, Sendable {
    public let repo: String
    public let path: String
    public let copy: [String]
    public let setup: String?
}

/// The CLIs Echo can run agents in.
public let agentCLIs = ["claude", "codex", "kiro"]

/// A model id as a line or a button names it: "claude-opus-5-5" and "claude-opus-5.5" read "opus";
/// any other id stays as it is.
public func shortModelName(_ model: String) -> String {
    let parts = model.split(separator: "-")
    return parts.count >= 2 && parts[0] == "claude" ? String(parts[1]) : model
}

/// The human's settings for agents, from `settings.get`: the default CLI and model, whether they
/// are forced on every agent, and how Orchestrators work.
public struct AgentSettings: Decodable, Equatable, Sendable {
    public var cli: String?
    public var model: String?
    /// The CLI and model above apply to every agent over a Profile's own; absent or null is off.
    public var forceCli: Bool?
    public var orchestrator: OrchestratorRules

    public struct OrchestratorRules: Codable, Equatable, Sendable {
        public var maxWorkers: Int
        public var planApproval: Bool
        public var review: Bool
        public var mergeWithoutAsking: Bool
    }
}

/// A fan-out's branch named after its Task: "Fix the flaky bench!" is `feat/fix-the-flaky-bench`.
/// Each try then works on it with `-1`, `-2` and so on after it.
public func fanoutBranch(_ title: String) -> String {
    let words = title.lowercased()
        .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        .map(String.init)
    var task = ""
    for word in words where task.count + word.count < 40 {
        task += (task.isEmpty ? "" : "-") + word
    }
    return "feat/" + (task.isEmpty ? "task" : task)
}

/// A local branch of a repo, from `branches.list`.
public struct RepoBranch: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    /// The checkout that has it: the repo's own, or a worktree.
    public let checkout: String?
    /// The agent working on it, if one is.
    public let agent: Int?

    public var id: String { name }
}

/// Where a new agent works, from the Create from field.
public enum CreateFrom: Equatable, Sendable {
    /// A GitHub issue (number or link): read it, then work on a new branch named after it.
    case issue(String)
    /// An existing branch, in the checkout that has it or a new worktree.
    case branch(String)
    /// A new branch named after this, in a new worktree.
    case name(String)
    /// A new branch with exactly this name, in a new worktree.
    case newBranch(String)
}

/// Reads the Smart field: an issue number or link, else a branch the repo has, else a name for
/// a new branch. Empty means the repo's own checkout.
public func smartCreateFrom(_ typed: String, branches: [String]) -> CreateFrom? {
    let text = typed.trimmingCharacters(in: .whitespaces)
    if text.isEmpty { return nil }
    if issueReference(text) != nil { return .issue(text) }
    if branches.contains(text) { return .branch(text) }
    return .name(text)
}

/// Reads the Branch tab: the branch picked from the list, else a branch the repo has by the name
/// typed, else a new branch by that name, with spaces as "-". Empty means the repo's own checkout.
public func branchCreateFrom(_ typed: String, picked: String?, branches: [String]) -> CreateFrom? {
    if let picked { return .branch(picked) }
    let text = typed.trimmingCharacters(in: .whitespaces)
    if text.isEmpty { return nil }
    if branches.contains(text) { return .branch(text) }
    return .newBranch(text.split(whereSeparator: \.isWhitespace).joined(separator: "-"))
}

/// `echoctl stats`: what Workers spent tokens on and how much they read, from their transcripts.
public struct WorkerStats: Decodable, Equatable, Sendable {
    public struct Share: Decodable, Equatable, Sendable {
        public let cacheReads: Double
        public let cacheWrites: Double
        public let output: Double
        public let coldStarts: Double
    }

    public struct PerWorker: Decodable, Equatable, Sendable {
        public let reads: Double
        public let shellReads: Double
        public let searches: Double
    }

    public struct Profile: Decodable, Equatable, Identifiable, Sendable {
        public let profile: String
        public let workers: Int
        public let turnsPerWorker: Int
        public let startContext: Int
        public let contextPerTurn: Int
        public let share: Double
        public var id: String { profile }
    }

    public let workers: Int
    public let withTranscript: Int
    public let turns: Int
    /// The median context of a Worker's first request: what every later turn re-reads.
    public let startContext: Int
    public let contextPerTurn: Int
    public let share: Share
    public let perWorker: PerWorker
    /// Percent of Read calls that repeat a file already read.
    public let repeatReads: Double
    public let profiles: [Profile]
}

/// Tokens as Echo shows them: "109k", "850".
public func tokenCount(_ tokens: Int) -> String {
    tokens >= 1000 ? "\(tokens / 1000)k" : "\(tokens)"
}

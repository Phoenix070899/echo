import Foundation

/// Where a new Team starts from, as the New Team sheet lists it: one of the templates, or a copy of
/// a Team that exists.
public enum NewTeamStart: String, CaseIterable, Sendable {
    case blank
    case solo
    case standard
    case researchHeavy
    case copy

    /// The template this starts from; nil for a copy.
    public var template: TeamTemplate? {
        switch self {
        case .blank: .blank
        case .solo: .solo
        case .standard: .standard
        case .researchHeavy: .researchHeavy
        case .copy: nil
        }
    }

    public var title: String { template?.title ?? "Copy of a Team" }

    /// The one plain line under the title.
    public var summary: String { template?.summary ?? "Start from a Team that exists, with its Members and settings." }
}

/// What the New Team sheet holds while it is open, and the decisions it makes from it: what is
/// offered, what is wrong with the name, whether Create is on, and the unsaved form Create builds.
public struct NewTeamSheet: Equatable, Sendable {
    public var name = ""
    public var level = TeamForm.userLevel
    public var start = NewTeamStart.standard
    public var preset = ProviderPreset.claude
    /// The Team a copy starts from, by name; nil until one is picked.
    public var copyOf: String?

    public init() {}

    /// The most a Team's name holds, as the daemon checks it.
    public static let maxNameLength = 40

    /// "Keep in" is offered only with a repo: the human's own level, then the repo's.
    public static func levels(hasRepo: Bool) -> [String] {
        hasRepo ? [TeamForm.userLevel, TeamForm.repoLevel] : [TeamForm.userLevel]
    }

    /// The starting points offered: a copy only when there is a Team to copy.
    public static func starts(teams: [Team]) -> [NewTeamStart] {
        NewTeamStart.allCases.filter { $0 != .copy || !teams.isEmpty }
    }

    /// The Provider is a choice for a template; a copy keeps the Team's own CLIs and models.
    public var offersProvider: Bool { start != .copy }

    /// The level the Team is kept at: the repo's only when there is a repo.
    public func level(hasRepo: Bool) -> String {
        Self.levels(hasRepo: hasRepo).contains(level) ? level : TeamForm.userLevel
    }

    /// The Team a copy starts from: the one picked, else the first.
    public func source(in teams: [Team]) -> Team? {
        teams.first { $0.name == copyOf } ?? teams.first
    }

    /// What is wrong with the name as typed, in plain words; nil when it is fine or still empty (an
    /// empty name only keeps Create off, it is not scolded).
    public func nameProblem(taking teams: [Team], hasRepo: Bool) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return nil }
        if name.count > Self.maxNameLength { return "A name is at most \(Self.maxNameLength) characters." }
        if name.hasPrefix("-") || !name.unicodeScalars.allSatisfy(Self.nameScalar) {
            return "Use lowercase letters, digits and -, and do not start with -."
        }
        // Echo's own Teams are replaced by a Team of the same name; yours or the repo's are not.
        let kept = level(hasRepo: hasRepo)
        if teams.contains(where: { $0.name == name && $0.origin == kept }) {
            return kept == TeamForm.repoLevel
                ? "This repo already has a Team named \(name)."
                : "You already have a Team named \(name)."
        }
        return nil
    }

    private static func nameScalar(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) || scalar == "-"
    }

    /// What is wrong that Create cannot go past, in plain words: the name's problem, else what
    /// `TeamForm.blocker` says of the form (a copy of a Team that is itself broken). Nil while the
    /// name is still empty.
    public func problem(teams: [Team], hasRepo: Bool) -> String? {
        if let problem = nameProblem(taking: teams, hasRepo: hasRepo) { return problem }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return candidate(teams: teams, hasRepo: hasRepo)?.blocker
    }

    /// The form Create opens, or nil while Create is off: the name is a name, no Team of that name is
    /// kept at that level, and a copy has a Team to copy that is sound.
    public func form(teams: [Team], hasRepo: Bool) -> TeamForm? {
        guard nameProblem(taking: teams, hasRepo: hasRepo) == nil,
              let form = candidate(teams: teams, hasRepo: hasRepo), form.blocker == nil else { return nil }
        return form
    }

    public func canCreate(teams: [Team], hasRepo: Bool) -> Bool {
        form(teams: teams, hasRepo: hasRepo) != nil
    }

    /// The form as typed, before it is checked. A copy takes this sheet's name and level.
    private func candidate(teams: [Team], hasRepo: Bool) -> TeamForm? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let level = level(hasRepo: hasRepo)
        if let template = start.template {
            return TeamForm.starting(template: template, preset: preset, name: name, level: level)
        }
        guard let source = source(in: teams) else { return nil }
        var copy = TeamForm(copying: source, taking: teams.map(\.name))
        copy.name = name
        copy.level = level
        return copy
    }

    /// The item `steps` places after `item` in `items`, stopping at the ends; the first when
    /// `item` is not in the list.
    public static func step<T: Equatable>(_ item: T, in items: [T], by steps: Int) -> T? {
        guard let at = items.firstIndex(of: item) else { return items.first }
        return items[min(max(at + steps, 0), items.count - 1)]
    }
}

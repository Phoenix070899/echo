import Foundation

/// The names a Settings section goes by. A section that was renamed or merged keeps its old name
/// working, so `echoctl ui settings agents` shows the Teams section (ui-ux/0101).
public enum SettingsSectionName {
    /// Old name to the section that took its place.
    public static let renamed = ["agents": "teams"]

    /// The name of the section `raw` asks for: the new name for an old one, else `raw` as it is.
    public static func canonical(_ raw: String) -> String {
        renamed[raw] ?? raw
    }
}

/// What the human answers when Settings holds Team edits that are not saved (ui-ux/0103).
public enum UnsavedAnswer: Sendable {
    case save, discard, cancel
}

/// What happens next, as the answer decides it.
public enum UnsavedStep: Equatable, Sendable {
    /// Write the Team, then take the step `UnsavedChanges.afterSave` names.
    case save
    /// Drop the edits and go where the human was going.
    case discardAndGo
    /// The Team is written: go where the human was going.
    case goOn
    /// Stay on the Team with its edits kept.
    case stay
}

/// When Settings asks before the human leaves a Team, and what each answer does (ui-ux/0103).
public enum UnsavedChanges {
    /// A Team without edits is left without asking, and a second ask never stacks on a first.
    public static func needsAsk(changed: Bool, asking: Bool) -> Bool {
        changed && !asking
    }

    public static func step(for answer: UnsavedAnswer) -> UnsavedStep {
        switch answer {
        case .save: .save
        case .discard: .discardAndGo
        case .cancel: .stay
        }
    }

    /// Once the Team is written the human goes on; when the daemon or the form refused it, they
    /// stay, and the refusal shows where it does on the Team.
    public static func afterSave(succeeded: Bool) -> UnsavedStep {
        succeeded ? .goOn : .stay
    }
}

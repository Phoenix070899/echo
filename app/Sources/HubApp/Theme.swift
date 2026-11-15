import AppKit
import Foundry
import HubCore
import SwiftUI

extension WorkerRow {
    /// Running blue, needing the human amber, done green, ended grey, anything that settled badly red.
    var markColor: Color {
        if isActive { return state == .needsYou ? Ledger.changed : Ledger.run }
        if phase == "ended" { return Ledger.ink3 }
        return isTrouble ? Ledger.fail : Ledger.done
    }

    /// "Running", "Waiting", "Needs you", "Done", "Ended", "Blocked", "Exited", "Lost".
    var phaseLabel: String {
        if isActive {
            switch state {
            case .waiting: return "Waiting"
            case .needsYou: return "Needs you"
            default: return "Running"
            }
        }
        return phase.prefix(1).uppercased() + phase.dropFirst()
    }
}

extension SessionInfo {
    /// The repo path with the home folder as `~`.
    var shortPath: String {
        let home = NSHomeDirectory()
        return repo.hasPrefix(home) ? "~" + repo.dropFirst(home.count) : repo
    }
}

/// A Worker's state mark: a spinner while it works (slower while it only waits on background
/// work), the still square once it settles or needs the human.
struct WorkerMark: View {
    let worker: WorkerRow

    var body: some View {
        if worker.isActive && worker.state != .needsYou {
            Spinner(color: worker.markColor, size: 10, period: worker.state == .waiting ? 2.4 : 1)
        } else {
            StateMark(color: worker.markColor)
        }
    }
}

/// A Worker's mark at the right of its sidebar row (ui-ux/0092, squared by ui-ux/0108): a turning
/// ring while it works (slower while it only waits on background work), the square target when it
/// needs the human, a solid green square with a tick when it is done, a plain grey tick when it ended
/// at its input box, a solid red square with a cross when it went wrong.
struct WorkerGlyph: View {
    let worker: WorkerRow
    private let size: CGFloat = 14

    var body: some View {
        Group {
            if worker.isActive && worker.state == .needsYou {
                NeedsRing(size: size)
            } else if worker.isActive {
                Spinner(color: worker.markColor, size: size - 1, period: worker.state == .waiting ? 2.4 : 1)
            } else if worker.phase == "ended" {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Ledger.ink3)
            } else if worker.isTrouble {
                SquareGlyph(symbol: "xmark", fill: Ledger.fail, size: size)
            } else {
                SquareGlyph(symbol: "checkmark", fill: Ledger.done, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(worker.phaseLabel)
    }
}

/// Makes the window's views resolve the Ledger's colours again after Custom's colours changed.
/// SwiftUI does so only when the colour scheme changes, so the scheme it sees flips for a
/// moment; Ledger colours ignore it while Custom, and the window itself keeps its appearance,
/// so nothing visibly flashes (ui-ux/0037).
struct LookRefresh: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, model.lookFlipped ? (scheme == .dark ? .light : .dark) : scheme)
    }
}

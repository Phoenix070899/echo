import Foundation

/// How wide the ledger and the Files column are drawn, so the panel between them keeps room.
/// The widths the human dragged to are kept as they are; only the widths drawn give way, so a
/// window made wide again gets them back.
public enum ColumnLayout {
    public struct Widths: Equatable, Sendable {
        public var ledger: CGFloat
        public var files: CGFloat?
    }

    /// `total` is the window's width; `fixed` what is not a column (padding and resizers).
    /// Files gives way first, down to `filesMin`, then the ledger, down to `ledgerMin`; if that is
    /// still not enough the panel takes less than `main`, and clips (it never pushes).
    public static func fit(
        total: CGFloat, fixed: CGFloat, ledger: CGFloat, files: CGFloat?,
        ledgerMin: CGFloat = 300, filesMin: CGFloat = 220, main: CGFloat = 360
    ) -> Widths {
        let room = total - fixed - main
        var l = ledger
        var f = files
        var over = l + (f ?? 0) - room
        if over > 0, let current = f {
            let cut = min(over, max(0, current - filesMin))
            f = current - cut
            over -= cut
        }
        if over > 0 { l -= min(over, max(0, l - ledgerMin)) }
        return Widths(ledger: l, files: f)
    }
}

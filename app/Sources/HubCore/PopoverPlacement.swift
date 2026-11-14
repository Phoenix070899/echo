import CoreGraphics

/// Where a Foundry popover opens in the window (ui-ux/0125): under its control when it fits or
/// when there is more room there, else over it; its leading or trailing edge on the control's, and
/// kept inside the window with its hard offset block.
public struct PopoverPlacement: Equatable, Sendable {
    /// The panel's leading edge.
    public let x: Double
    /// The top of the space the panel may take.
    public let y: Double
    /// How tall that space is; a taller panel scrolls.
    public let height: Double
    /// Whether the panel hangs under the control (its top at `y`) or stands over it (its bottom at
    /// `y + height`).
    public let below: Bool

    /// The gap kept between the panel and the window's edges.
    public static let margin = 8.0
    /// The hard offset block, down and right of the panel.
    public static let cast = 6.0
    /// The room under the control that is always enough to open there.
    public static let roomy = 320.0

    public init(x: Double, y: Double, height: Double, below: Bool) {
        self.x = x
        self.y = y
        self.height = height
        self.below = below
    }

    /// The placement of a panel `width` wide for a control at `anchor` in a window of `size`.
    public static func place(anchor: CGRect, width: Double, in size: CGSize, trailing: Bool = false,
                             gap: Double = 8) -> PopoverPlacement {
        let ideal = trailing ? Double(anchor.maxX) - width : Double(anchor.minX)
        let x = min(max(ideal, margin), max(margin, Double(size.width) - width - cast - margin))
        let under = Double(size.height) - (Double(anchor.maxY) + gap) - cast - margin
        let over = Double(anchor.minY) - gap - margin
        if under >= roomy || under >= over {
            return PopoverPlacement(x: x, y: Double(anchor.maxY) + gap, height: max(under, 0), below: true)
        }
        return PopoverPlacement(x: x, y: margin, height: max(over, 0), below: false)
    }
}

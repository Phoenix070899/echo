import AppKit
import HubCore
import SwiftUI

/// A Worker's state as a small square.
public struct StateMark: View {
    public let color: Color

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// A list row's marker (ui-ux/0124): a 6 pt square at the row's leading edge, grey, and the accent
/// on the picked row or the row under the pointer (ui-ux/0127). A row that sets `listRowHovered`
/// (`.listRowHover()`, or the sidebar's `TreeRow`) turns its square orange while hovered. Lists
/// never draw a vertical line.
public struct ListMarker: View {
    public static let size: CGFloat = 6
    public let picked: Bool
    @Environment(\.listRowHovered) private var hovered

    public init(picked: Bool) {
        self.picked = picked
    }

    public var body: some View {
        Rectangle()
            .fill(picked || hovered ? Ledger.accent : Ledger.square)
            .frame(width: Self.size, height: Self.size)
            .accessibilityHidden(true)
    }
}

private struct ListRowHoveredKey: EnvironmentKey {
    public static let defaultValue = false
}

extension EnvironmentValues {
    /// The pointer is over the list row this view sits in; its `ListMarker` turns the accent.
    public var listRowHovered: Bool {
        get { self[ListRowHoveredKey.self] }
        set { self[ListRowHoveredKey.self] = newValue }
    }
}

/// Tracks the pointer over a list row and tells the row's `ListMarker` (ui-ux/0127).
private struct ListRowHover: ViewModifier {
    @StateObject private var hover = Flag()

    public func body(content: Content) -> some View {
        content
            .environment(\.listRowHovered, hover.on)
            .onHover { hover.on = $0 }
    }
}

extension View {
    /// The row's square turns the accent while the pointer is over it (ui-ux/0127).
    public func listRowHover() -> some View { modifier(ListRowHover()) }
}

/// A control or row with no square shows the pointer by its fill alone (ui-ux/0127, ui-ux/0131).
private struct HoverFill: ViewModifier {
    public let fill: Color
    public let active: Bool
    @StateObject private var hover = Flag()

    public func body(content: Content) -> some View {
        content
            .background(active && hover.on ? fill : .clear)
            .onHover { hover.on = $0 }
    }
}

extension View {
    /// Fills the view while the pointer is over it, unless `active` is false (a picked row keeps
    /// its own fill).
    public func hoverFill(_ fill: Color = Ledger.wash, active: Bool = true) -> some View {
        modifier(HoverFill(fill: fill, active: active))
    }
}

/// Something in progress: an arc turning once a second (slower for work only waiting in the
/// background), in the colour of what it stands for. Under Reduce Motion it stands still.
/// Core Animation turns it, off the main thread: a SwiftUI animation laid the whole window out
/// again on every frame for every spinner on screen (bugs/0062).
public struct Spinner: View {
    public var color: Color = Ledger.ink3
    public var size: CGFloat = 10
    public var period: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(color: Color = Ledger.ink3, size: CGFloat = 10, period: Double = 1) {
        self.color = color
        self.size = size
        self.period = period
    }

    public var body: some View {
        SpinnerArc(color: NSColor(color), lineWidth: max(1.5, size / 6), period: reduceMotion ? nil : period)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct SpinnerArc: NSViewRepresentable {
    public let color: NSColor
    public let lineWidth: CGFloat
    /// Seconds a turn takes; nil stands still.
    public let period: Double?

    public func makeNSView(context: Context) -> SpinnerArcView { SpinnerArcView() }

    public func updateNSView(_ view: SpinnerArcView, context: Context) {
        view.update(color: color, lineWidth: lineWidth, period: period)
    }
}

final class SpinnerArcView: NSView {
    private let arc = CAShapeLayer()
    private var color = NSColor.clear
    private var period: Double?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        arc.fillColor = nil
        arc.lineCap = .round
        layer?.addSublayer(arc)
    }

    required init?(coder: NSCoder) { fatalError("SpinnerArcView is built in code") }

    func update(color: NSColor, lineWidth: CGFloat, period: Double?) {
        self.color = color
        arc.lineWidth = lineWidth
        if period != self.period {
            self.period = period
            spin()
        }
        resolveColor()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.frame = bounds
        let inset = arc.lineWidth / 2
        let radius = max(0, min(bounds.width, bounds.height) / 2 - inset)
        let path = CGMutablePath()
        // From 3 o'clock, clockwise on screen (the layer's y runs up), as SwiftUI's trimmed circle did.
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                    startAngle: 0, endAngle: -0.7 * 2 * .pi, clockwise: true)
        arc.path = path
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColor()
    }

    /// Leaving a window drops a layer's animations; coming back starts the turn again.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        spin()
    }

    /// A spinner sits inside rows and buttons; clicks go to them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func resolveColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance { arc.strokeColor = color.cgColor }
        CATransaction.commit()
    }

    private func spin() {
        arc.removeAnimation(forKey: "turn")
        guard let period, window != nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        // Clockwise on screen: the layer's y runs up.
        turn.toValue = -2 * Double.pi
        turn.duration = period
        turn.repeatCount = .infinity
        turn.isRemovedOnCompletion = false
        arc.add(turn, forKey: "turn")
    }
}

/// The target: something waits on the human. A square on the accent's soft fill, with a solid
/// square at its centre (ui-ux/0108).
public struct NeedsRing: View {
    public var size: CGFloat = 14

    public init(size: CGFloat = 14) {
        self.size = size
    }

    public var body: some View {
        Rectangle().fill(Ledger.marker)
            .overlay(Rectangle().strokeBorder(Ledger.accent, lineWidth: max(1.5, size / 8)))
            .overlay(Rectangle().fill(Ledger.accent).frame(width: size * 0.32, height: size * 0.32))
            .frame(width: size, height: size)
            .accessibilityLabel("Needs you")
    }
}

/// A solid square with a symbol cut out of it in the sheet's colour.
public struct SquareGlyph: View {
    public let symbol: String
    public let fill: Color
    public var size: CGFloat = 14

    public init(symbol: String, fill: Color, size: CGFloat = 14) {
        self.symbol = symbol
        self.fill = fill
        self.size = size
    }

    public var body: some View {
        Rectangle().fill(fill)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.55, weight: .heavy)).foregroundStyle(Ledger.paper))
            .frame(width: size, height: size)
    }
}

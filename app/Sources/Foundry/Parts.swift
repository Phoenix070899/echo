import AppKit
import HubCore
import SwiftUI

/// A small mono label in capitals: section names, tabs, readouts.
public struct MonoLabel: View {
    public let text: String
    public var color: Color = Ledger.ink3

    public init(_ text: String, color: Color = Ledger.ink3) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(Ledger.monoFont(11, .bold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// Where a panel has nothing to show: a mono capital title over one quiet line (ui-ux/0117).
public struct EmptyNote: View {
    public let title: String
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: 8) {
            MonoLabel(title)
            Text(detail)
                .font(Ledger.font(14))
                .foregroundStyle(Ledger.ink3)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A line saying something is being read or started, with a spinner before it.
public struct Pending: View {
    public let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        HStack(spacing: 6) {
            Spinner(size: 10)
            Text(text)
        }
    }
}

/// Text under the highlighter: reserved for things waiting on the human.
public struct Marked: View {
    public let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .fontWeight(.medium)
            .foregroundStyle(Ledger.markerInk)
            .padding(.horizontal, 3)
            .background(Ledger.marker)
    }
}

/// The ledger's buttons (ui-ux/0106, ui-ux/0112): the primary is solid ink casting a hard accent
/// offset that presses flat; the rest are a 2 pt ink outline. Mono capitals, square; 28 pt tall
/// with 10 pt capitals and a 2 pt offset, or taller with 11 pt capitals and a 3 pt offset.
public struct LedgerButtonStyle: ButtonStyle {
    public var primary = false
    public var large = false
    /// A height of its own, as Foundry's 34 and 36 pt buttons in headers and footers.
    public var height: CGFloat?

    public init(primary: Bool = false, large: Bool = false, height: CGFloat? = nil) {
        self.primary = primary
        self.large = large
        self.height = height
    }


    public func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, primary: primary, height: height ?? (large ? 36 : 28))
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @StateObject private var hover = Flag()

        var body: some View {
            let tall = height > 30
            let shift: CGFloat = tall ? 3 : 2
            // As Foundry's button: hovered, the primary moves halfway onto its block and pressed, all the
            // way; the secondary takes the hover fill (ui-ux/0131).
            let hovered = hover.on && isEnabled
            let pressed: CGFloat = !primary ? 0 : configuration.isPressed ? shift : hovered ? shift / 2 : 0
            configuration.label
                .font(Ledger.monoFont(tall ? 11 : 10, .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .lineLimit(1)
                // A label never truncates: capitals in mono run wider than the sans they replaced.
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, tall ? 14 : 12)
                .frame(minHeight: height)
                .foregroundStyle(primary ? Ledger.onPrimary : Ledger.ink)
                .background(primary ? Ledger.primary : hovered ? Ledger.wash : Color.clear)
                .overlay(Rectangle().strokeBorder(primary ? Color.clear : Ledger.ink, lineWidth: Ledger.ruleStrong))
                .offset(x: pressed, y: pressed)
                // The offset is a solid block behind the button, not a blurred shadow (ui-ux/0106);
                // pressing moves the button onto it.
                .background {
                    if primary && isEnabled { Rectangle().fill(Ledger.accent).offset(x: shift, y: shift) }
                }
                .padding(.trailing, primary ? shift : 0)
                .padding(.bottom, primary ? shift : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hover.on = $0 }
        }
    }
}

extension ButtonStyle where Self == LedgerButtonStyle {
    public static var ledger: LedgerButtonStyle { LedgerButtonStyle() }
    public static var ledgerPrimary: LedgerButtonStyle { LedgerButtonStyle(primary: true) }
    public static var ledgerLarge: LedgerButtonStyle { LedgerButtonStyle(primary: true, large: true) }
}

/// A segmented choice (ui-ux/0107, ui-ux/0112): a sunk square track, the picked choice on the sheet's
/// grey inside a 2 pt ink frame, mono capitals; 24 pt tall in a compact header, 28 pt in a large one.
/// Stands in for the system's segmented picker, whose accent-blue thumb belongs to no other control.
public struct LedgerSegmented<Value: Hashable>: View {
    @Binding public var selection: Value
    public let options: [(value: Value, title: String)]
    public var large = false

    public init(selection: Binding<Value>, options: [(value: Value, title: String)], large: Bool = false) {
        self._selection = selection
        self.options = options
        self.large = large
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                Button { selection = option.value } label: {
                    SegmentLabel(title: option.title, on: on, large: large)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .segmentTrack(large: large)
    }
}

extension View {
    /// The sunk track a segmented choice sits in.
    public func segmentTrack(large: Bool = false) -> some View {
        padding(large ? 3 : 2)
            .background(Ledger.bubble)
            .fixedSize()
    }
}

/// One choice of a segmented control, picked or not; a choice not picked takes the hover fill.
public struct SegmentLabel: View {
    public let title: String
    public let on: Bool
    public var large = false
    public var inset: CGFloat?
    @StateObject private var hover = Flag()

    public init(title: String, on: Bool, large: Bool = false, inset: CGFloat? = nil) {
        self.title = title
        self.on = on
        self.large = large
        self.inset = inset
    }

    public var body: some View {
        Text(title)
            .font(Ledger.monoFont(large ? 11 : 10, .bold))
            .tracking(large ? 0.9 : 0.8)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(on || hover.on ? Ledger.ink : Ledger.ink3)
            .padding(.horizontal, inset ?? (large ? 14 : 10))
            .frame(height: large ? 28 : 24)
            .background(on ? Ledger.field : hover.on ? Ledger.wash : .clear)
            .overlay(Rectangle().strokeBorder(on ? Ledger.ink : .clear, lineWidth: 2))
            .contentShape(Rectangle())
            .onHover { hover.on = $0 }
    }
}

/// A text link, for quiet actions like Show all: ink, underlined in the accent.
/// Hovered, it turns the muted ink, as Foundry's link.
public struct LinkButtonStyle: ButtonStyle {
    public init() {}


    public func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @StateObject private var hover = Flag()

        var body: some View {
            configuration.label
                .font(Ledger.font(13, .semibold))
                .foregroundStyle(hover.on ? Ledger.ink3 : Ledger.ink)
                .underline(true, color: Ledger.accent)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
                .onHover { hover.on = $0 }
        }
    }
}

extension ButtonStyle where Self == LinkButtonStyle {
    public static var ledgerLink: LinkButtonStyle { LinkButtonStyle() }
}

extension View {
    /// A sheet of paper on the desk, set apart by its fill alone, on the container radius.
    public func ledgerSheet() -> some View {
        background(Ledger.paper, in: RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Ledger.radiusContainer, style: .continuous)
                .strokeBorder(Ledger.rule, lineWidth: Ledger.hairline))
    }

    /// Lays the view out in exactly the room it is offered and cuts what does not fit. Without it a
    /// view whose content cannot shrink (a header, a grid, a terminal) sets a minimum width the
    /// columns around it cannot take back, and the row runs past the window's edge.
    public func clippedToOffer() -> some View {
        GeometryReader { proxy in
            self.frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading).clipped()
        }
    }

    /// One line that runs out in a fade rather than an ellipsis, as Claude's sidebar titles do.
    /// Fills the width it is given, so nothing flexible should follow it in a row. `minWidth: 0`
    /// is what lets it be narrower than its text: without it a long title keeps the whole row,
    /// and the column around it, as wide as the title.
    public func fadedEnd(_ width: CGFloat = 28) -> some View {
        lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask(HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
            })
    }

    /// A text field: the sheet's grey inside a 1 pt grey rule; pair with `.textFieldStyle(.plain)`.
    public func ledgerField() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Ledger.field)
            .overlay(Rectangle().strokeBorder(Ledger.ink3.opacity(0.6), lineWidth: Ledger.hairline))
    }
}

/// A section title in the ledger: name, count, and an optional action on the right.
public struct SectionHeader<Trailing: View>: View {
    public let title: String
    public let count: Int?
    @ViewBuilder public var trailing: () -> Trailing

    public init(title: String, count: Int? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.count = count
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MonoLabel(title, color: Ledger.ink)
            if let count {
                Text("\(count)").font(Ledger.monoFont(11)).foregroundStyle(Ledger.ink3).monospacedDigit()
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    public init(title: String, count: Int? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

/// Echo's mark for the top bar: a solid ink square casting the accent's hard offset, Foundry's own
/// block (ui-ux/0110). It takes 3 pt more than its square, right and down, for the offset.
public struct EchoMark: View {
    public init() {}


    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) - 3
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Ledger.accent).frame(width: side, height: side).offset(x: 3, y: 3)
                Rectangle().fill(Ledger.ink).frame(width: side, height: side)
            }
        }
        .accessibilityHidden(true)
    }
}

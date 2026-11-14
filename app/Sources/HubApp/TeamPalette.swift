import HubCore
import SwiftUI

/// The strip above the Team's tree (ui-ux/0102): the six Actions, the six shipped Workers and
/// Custom as chips. A chip is dragged onto the tree to add a Member, onto a Member for a child,
/// between rows to put it there, onto empty space for level 1. Clicking one adds it under the picked
/// Member, so the palette is not a drag-only thing (ui-ux/0008).
struct TeamPalette: View {
    @ObservedObject var teams: TeamSettingsModel
    let drag: TreeDragState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drag a chip onto the tree to add a Member, or click one to add it under the picked Member.")
                .font(Ledger.font(11))
                .foregroundStyle(Ledger.ink3)
                .fixedSize(horizontal: false, vertical: true)
            ChipFlow(spacing: 6) {
                ForEach(Palette.chips()) { chip in
                    PaletteChipView(teams: teams, drag: drag, chip: chip)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Palette")
    }
}

/// One chip: its icon and name on a fill, dragged by its payload, added under the picked Member when
/// clicked.
private struct PaletteChipView: View {
    @ObservedObject var teams: TeamSettingsModel
    let drag: TreeDragState
    let chip: PaletteChip

    private var help: String {
        switch chip.kind {
        case .action: "Add a \(chip.title) Member: drag it onto the tree, or click to add it under the picked Member"
        case .worker: "Add a Member that runs \(chip.title): drag it onto the tree, or click to add it under the picked Member"
        case .custom: "Add a Member on a Profile of your own: drag it onto the tree, or click to name one"
        }
    }

    var body: some View {
        Button { teams.perform(.add(chip.action)) } label: {
            HStack(spacing: 5) {
                Image(systemName: ActionLook.symbol(for: chip.action))
                    .font(Ledger.font(11))
                    .foregroundStyle(Ledger.ink2)
                Text(chip.title)
                    .font(Ledger.font(12, chip.kind == .worker ? .regular : .medium))
                    .foregroundStyle(Ledger.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(background, in: RoundedRectangle(cornerRadius: Ledger.radiusInner, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            drag.begin(chip.payload)
            return NSItemProvider(object: chip.payload.text as NSString)
        }
        .help(help)
        .accessibilityLabel("\(chip.title) chip. Adds a Member under the picked one.")
    }

    /// The Actions on the fill, the Workers on the quieter wash, so the two rows of names read apart.
    private var background: Color {
        chip.kind == .worker ? Ledger.wash : Ledger.fill
    }
}

/// Lays its children in rows left to right, starting a new row where the next would not fit.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, placed.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}

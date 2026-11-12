import HubCore
import SwiftUI

/// The checkout's own shell under the Files column (ui-ux/0089): a bar that is always there, and
/// the terminal below it while open. Hiding it only stops drawing it; the shell, and a command
/// running in it, goes on in the daemon, and the bar shows a mark while it prints.
struct SideTerminalSection: View {
    @EnvironmentObject private var model: AppModel
    let root: String
    /// The column's height, so the terminal never takes all of it.
    let available: CGFloat

    var body: some View {
        let status = model.sideShells[root]
        let open = model.sideShown
        let height = min(max(model.sideHeight, 120), max(120, available - 200))
        VStack(spacing: 0) {
            if open { HeightResizer(height: $model.sideHeight, range: 120...900) }
            bar(status, open: open)
            if open {
                SideTerminalPane(root: root).frame(height: height)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Ledger.rule).frame(height: Ledger.hairline) }
    }

    private func bar(_ status: SideStatus?, open: Bool) -> some View {
        HStack(spacing: 4) {
            Button { open ? model.hideSide() : model.toggleSide() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(Ledger.ink3)
                        .frame(width: 12)
                    Image(systemName: "terminal").font(.system(size: 12)).foregroundStyle(Ledger.ink3)
                    Text("Terminal").font(Ledger.font(13, .medium)).foregroundStyle(Ledger.ink2)
                    mark(status)
                    Spacer(minLength: 4)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "Hide the terminal (⌃`). Its commands keep running." : "Open a terminal in this folder (⌃`)")
            .accessibilityLabel(open ? "Hide terminal" : "Open terminal")
            if status?.live == true {
                Button { model.stopSide(root) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ledger.ink3)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("End this terminal")
                .accessibilityLabel("End terminal")
            }
        }
        .padding(.trailing, 8)
    }

    /// A turning mark while it prints, a still dot while it waits, nothing before it started.
    @ViewBuilder
    private func mark(_ status: SideStatus?) -> some View {
        if status?.busy == true {
            HStack(spacing: 6) {
                Spinner(color: Ledger.primary, size: 10)
                if !model.sideShown { Text("running").font(Ledger.font(12)).foregroundStyle(Ledger.ink3) }
            }
        } else if status?.live == true {
            Circle().fill(Ledger.done).frame(width: 6, height: 6).accessibilityLabel("Running")
        }
    }
}

/// The shell itself, on the terminal's own background.
private struct SideTerminalPane: View {
    @EnvironmentObject private var model: AppModel
    let root: String

    var body: some View {
        TerminalPane(target: .side(root: root), command: .attach, client: model.client, appearance: model.appearance,
                     keyboard: !model.modalShown && model.preview == nil && model.sideFocus,
                     focusRequest: model.sideFocusRequest, epoch: "\(model.sideEpoch)", side: true)
            .padding(.leading, 10)
            .padding(.vertical, 6)
            .background { TerminalBackdrop(appearance: model.appearance) }
            .opacity(model.daemonDown ? 0.45 : 1)
    }
}

/// The edge above the terminal: dragging up makes it taller.
private struct HeightResizer: View {
    @Binding var height: CGFloat
    let range: ClosedRange<CGFloat>
    @StateObject private var drag = DragStart()
    @StateObject private var hover = Flag()

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .frame(maxWidth: .infinity)
            .overlay {
                Capsule().fill(Ledger.rule).frame(width: 36, height: 3)
                    .opacity(hover.on || drag.width != nil ? 1 : 0)
            }
            .contentShape(Rectangle())
            .pointerStyle(.rowResize)
            .onHover { hover.on = $0 }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let from = drag.width ?? height
                        drag.width = from
                        height = min(max(from - value.translation.height, range.lowerBound), range.upperBound).rounded()
                    }
                    .onEnded { _ in drag.width = nil }
            )
            .onTapGesture(count: 2) { height = 240 }
            .accessibilityLabel("Resize terminal")
    }
}

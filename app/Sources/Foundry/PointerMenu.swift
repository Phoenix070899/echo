import AppKit
import SwiftUI

// Foundry's right-click menu (ui-ux/0141): a `FoundryMenu` that opens at the pointer, in place of the
// system's context menu. A right click, or a Control-click, on the view opens it; ↑ ↓, Return and Esc
// work as in every Foundry menu.

/// Where a right-click menu is open: the point in the view's own space, or nil while it is shut.
@MainActor
public final class PointerMenuState: ObservableObject {
    @Published public var at: CGPoint?

    public init() {}

    /// Whether the menu is open, for `foundryPopover`.
    public var open: Binding<Bool> {
        Binding(get: { self.at != nil }, set: { if !$0 { self.at = nil } })
    }
}

extension View {
    /// Opens `entries` in a Foundry menu at the pointer on a right click or a Control-click. An
    /// empty list opens nothing.
    public func foundryContextMenu(width: CGFloat = 240, label: String = "Actions",
                                   _ entries: @escaping () -> [FoundryMenuEntry]) -> some View {
        modifier(FoundryContextMenu(width: width, label: label, entries: entries))
    }

    /// Draws a Foundry menu at `state`'s point in this view while it is open; for a view that
    /// catches the right click itself, like an AppKit list.
    public func foundryPointerMenu(_ state: PointerMenuState, width: CGFloat = 240, label: String = "Actions",
                                   _ entries: @escaping () -> [FoundryMenuEntry]) -> some View {
        anchorPreference(key: FoundryPopoverKey.self, value: .rect(CGRect(origin: state.at ?? .zero, size: .zero))) { anchor in
            guard state.at != nil else { return [] }
            return [FoundryPopoverEntry(anchor: anchor, width: width, trailing: false, gap: 2,
                                        content: AnyView(FoundryMenu(label: label, entries: entries())),
                                        close: { state.at = nil })]
        }
    }
}

private struct FoundryContextMenu: ViewModifier {
    let width: CGFloat
    let label: String
    let entries: () -> [FoundryMenuEntry]
    @StateObject private var state = PointerMenuState()

    func body(content: Content) -> some View {
        content
            .overlay(RightClickCatcher { point in
                if !entries().isEmpty { state.at = point }
            })
            // VoiceOver's Show Menu opens it too, near the view's top left.
            .accessibilityAction(.showMenu) {
                if !entries().isEmpty { state.at = CGPoint(x: 16, y: 16) }
            }
            .foundryPointerMenu(state, width: width, label: label, entries)
    }
}

/// A clear view over its owner that takes only right clicks and Control-clicks; every other event
/// passes to the views under it.
private struct RightClickCatcher: NSViewRepresentable {
    let clicked: (CGPoint) -> Void

    func makeNSView(context: Context) -> RightClickView { RightClickView() }

    func updateNSView(_ view: RightClickView, context: Context) { view.clicked = clicked }
}

final class RightClickView: NSView {
    var clicked: (CGPoint) -> Void = { _ in }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, Self.isMenuClick(event) else { return nil }
        return super.hitTest(point)
    }

    /// As the system's context menu, it opens on a window that is not in front too.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) { open(event) }

    override func mouseDown(with event: NSEvent) {
        if Self.isMenuClick(event) { open(event) } else { super.mouseDown(with: event) }
    }

    private func open(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        clicked(CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y))
    }

    private static func isMenuClick(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }
}

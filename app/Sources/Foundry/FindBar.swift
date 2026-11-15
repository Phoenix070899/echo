import AppKit

/// Foundry's find bar (ui-ux/0142), drawn by AppKit for the views AppKit draws (a terminal, a
/// file's code): a square field in a 2 pt frame at the view's top right, "3 of 14" beside the
/// text. Return goes to the next match, Shift-Return to the one before, Esc closes it. It stands in
/// for the system's find bar, whose rounded field and buttons belong to no other control.
open class FoundryFindBar: NSView, NSTextFieldDelegate {
    /// The text to find, on every change.
    public var changed: (String) -> Void = { _ in }
    /// Return, or Shift-Return (true) for the match before.
    public var step: (_ back: Bool) -> Void = { _ in }
    /// Esc, after the bar has closed itself.
    public var closed: () -> Void = {}

    public let field = NSTextField()
    private let count = NSTextField(labelWithString: "")

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 32))
        isHidden = true
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.borderWidth = Ledger.ruleStrong
        field.placeholderString = "Find"
        field.font = Ledger.nsMono(12)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        count.font = Ledger.nsMono(11)
        count.alignment = .right
        field.frame = NSRect(x: 10, y: 8, width: 186, height: 16)
        count.frame = NSRect(x: 198, y: 8, width: 72, height: 16)
        addSubview(field)
        addSubview(count)
        colour(background: NSColor(Ledger.paper), frame: NSColor(Ledger.ink), text: NSColor(Ledger.ink))
    }

    public required init?(coder: NSCoder) { fatalError("FoundryFindBar is built in code") }

    private var colours: (background: NSColor, frame: NSColor)?

    /// The bar's own colours; a terminal gives its theme's.
    public func colour(background: NSColor, frame: NSColor, text: NSColor) {
        colours = (background, frame)
        field.textColor = text
        count.textColor = text.withAlphaComponent(0.65)
        resolveColours()
    }

    override open func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColours()
    }

    /// A layer takes fixed colours, so the dynamic ones are resolved for the bar's appearance.
    private func resolveColours() {
        guard let colours else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = colours.background.cgColor
            layer?.borderColor = colours.frame.cgColor
        }
    }

    /// Sits at the top right of `bounds`, in a flipped view or not.
    public func place(in bounds: NSRect, flipped: Bool) {
        let y = flipped ? bounds.minY + 8 : bounds.maxY - frame.height - 8
        setFrameOrigin(NSPoint(x: bounds.maxX - frame.width - 14, y: y))
    }

    public var isOpen: Bool { !isHidden }

    /// Opens with `needle`, or the last text, picked, and finds it.
    open func open(_ needle: String = "") {
        if !needle.isEmpty { field.stringValue = needle }
        isHidden = false
        watchEscape()
        window?.makeFirstResponder(field)
        field.selectText(nil)
        changed(field.stringValue)
    }

    public func close() {
        guard !isHidden else { return }
        isHidden = true
        if let escape { NSEvent.removeMonitor(escape) }
        escape = nil
        show(selected: -1, of: -1)
        closed()
    }

    /// "3 of 14", "No matches", or nothing while `total` is below 0.
    public func show(selected: Int, of total: Int) {
        count.stringValue = total < 0 ? "" : total == 0 ? "No matches" : "\(max(selected, 0) + 1) of \(total)"
    }

    private var escape: Any?

    /// Esc while the field has the keyboard closes the bar. It is caught before the window sends
    /// it, since SwiftUI around the bar would take it as its own key first.
    private func watchEscape() {
        guard escape == nil else { return }
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, event.window === window,
                  let editor = field.currentEditor(), window?.firstResponder === editor else { return event }
            close()
            return nil
        }
    }

    public func controlTextDidChange(_ note: Notification) {
        changed(field.stringValue)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            step(NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }
}

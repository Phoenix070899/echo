import AppKit
import HubCore
import SwiftUI

/// One row of the Files column's tree, as `FileList` draws it.
struct FileListRow: Equatable {
    let entry: FileEntry
    let mark: RowMark?
    /// Covered by .gitignore: drawn dim.
    let ignored: Bool
    let open: Bool
}

/// The Files column's tree, drawn by AppKit: one view draws the rows on screen, so showing another
/// checkout makes no SwiftUI view per row (ui-ux/0063). It draws, scrolls, and reports clicks;
/// the keys, the keyboard focus, and the cursor stay with `FilesTree`.
struct FileList: NSViewRepresentable {
    let rows: [FileListRow]
    let root: String
    let cursor: String?
    /// A terminal shows that a mention can be typed into.
    let typeable: Bool
    let click: (FileEntry) -> Void

    func makeNSView(context: Context) -> FileListScrollView { FileListScrollView() }

    func updateNSView(_ scroll: FileListScrollView, context: Context) {
        scroll.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        let list = scroll.list
        list.click = click
        list.update(rows: rows, root: root, cursor: cursor, typeable: typeable, look: Ledger.custom)
    }
}

final class FileListScrollView: NSScrollView {
    let list = FileListView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        documentView = list
    }

    required init?(coder: NSCoder) { fatalError("FileListScrollView is built in code") }

    /// The rows are as wide as the column, and as tall as there are rows.
    override func layout() {
        super.layout()
        list.fit(width: contentSize.width)
    }
}

final class FileListView: NSView, NSViewToolTipOwner {
    static let rowHeight: CGFloat = 26
    /// Space above the first row and below the last.
    private static let margin: CGFloat = 2
    /// Rows start this far in from the column's edge; their fills run edge to edge (ui-ux/0118).
    private static let inset: CGFloat = 12

    var click: ((FileEntry) -> Void)?
    private(set) var rows: [FileListRow] = []
    private var root = ""
    private var cursor: String?
    private var typeable = false
    private var look: CustomLook?
    private var hovered: Int?
    private var pressed: (row: Int, at: NSPoint)?

    private let picked = RowFill(color: Ledger.selected)
    private let hover = RowFill(color: Ledger.wash)
    /// Draws the rows' icons and text, over the fills.
    private lazy var text = RowsText(list: self)

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(hover)
        addSubview(picked)
        addSubview(text)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Files")
    }

    required init?(coder: NSCoder) { fatalError("FileListView is built in code") }

    override var isFlipped: Bool { true }

    func update(rows: [FileListRow], root: String, cursor: String?, typeable: Bool, look: CustomLook?) {
        let changed = rows != self.rows || root != self.root || look != self.look
        let moved = cursor != self.cursor
        self.typeable = typeable
        guard changed || moved else { return }
        if root != self.root { hovered = nil }
        let before = cursorIndex
        self.rows = rows
        self.root = root
        self.cursor = cursor
        self.look = look
        fit(width: frame.width)
        placeFills()
        if changed {
            text.needsDisplay = true
        } else {
            // Only the marker moved: redraw the rows it left and reached.
            for index in [before, cursorIndex].compactMap({ $0 }) { text.setNeedsDisplay(rect(of: index)) }
        }
        if moved, let index = cursorIndex { scrollToVisible(rect(of: index)) }
        accessibilityRows = nil
    }

    func fit(width: CGFloat) {
        let height = Self.margin * 2 + CGFloat(rows.count) * Self.rowHeight
        let size = NSSize(width: width, height: max(height, superview?.bounds.height ?? 0))
        if frame.size != size {
            setFrameSize(size)
            text.frame = bounds
            placeFills()
        }
    }

    private var cursorIndex: Int? { cursor.flatMap { c in rows.firstIndex { $0.entry.path == c } } }

    fileprivate func rect(of index: Int) -> NSRect {
        NSRect(x: 0, y: Self.margin + CGFloat(index) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
    }

    private func row(at point: NSPoint) -> Int? {
        let index = Int(floor((point.y - Self.margin) / Self.rowHeight))
        return point.y >= Self.margin && rows.indices.contains(index) ? index : nil
    }

    // MARK: Drawing

    /// The cursor's row and the hovered one get Claude's rounded fill, inset from the column's edges;
    /// the cursor's wins where they meet.
    private func placeFills() {
        for (fill, index) in [(picked, cursorIndex), (hover, hovered)] {
            let shown = index.map { rows.indices.contains($0) } ?? false
            fill.isHidden = !shown || (fill === hover && hovered == cursorIndex)
            if shown, let index { fill.frame = rect(of: index) }
        }
    }

    fileprivate func drawRows(in dirtyRect: NSRect) {
        guard !rows.isEmpty else { return }
        let first = max(0, Int(floor((dirtyRect.minY - Self.margin) / Self.rowHeight)))
        let last = min(rows.count - 1, Int(floor((dirtyRect.maxY - Self.margin) / Self.rowHeight)))
        guard first <= last else { return }
        for index in first...last { draw(rows[index], in: rect(of: index), hovered: index == hovered) }
    }

    private static let name = Ledger.nsFont(13)
    private static let markFont = Ledger.nsMono(11, .bold)
    private static let chevronFont = Ledger.nsMono(11)

    private func draw(_ row: FileListRow, in rect: NSRect, hovered: Bool) {
        let entry = row.entry
        let ink3 = NSColor(Ledger.ink3)
        // A small square at the row's leading edge: the accent on the cursor's row and the hovered
        // one, grey on the others; no vertical line (ui-ux/0124, ui-ux/0127).
        NSColor(entry.path == cursor || hovered ? Ledger.accent : Ledger.square).setFill()
        NSRect(x: rect.minX + 3, y: rect.midY - 3, width: 6, height: 6).fill()
        // Foundry's tree: a mono ▸ or ▾ before a folder, no icons, 14 pt more for each level.
        var x = rect.minX + Self.inset + CGFloat(entry.depth) * 14
        if entry.isFolder {
            let chevron = NSAttributedString(string: row.open ? "▾" : "▸", attributes: [
                .font: Self.chevronFont, .foregroundColor: ink3,
            ])
            let size = chevron.size()
            chevron.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))
        }
        x += 10 + 8
        var right = rect.maxX - 12
        switch row.mark {
        case .file(let git)?:
            let text = NSAttributedString(string: git.rawValue, attributes: [
                .font: Self.markFont, .foregroundColor: NSColor(gitMarkColor(git)),
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: right - size.width, y: rect.midY - size.height / 2))
            right -= size.width + 6
        case .folder?:
            NSColor(Ledger.changed).setFill()
            NSRect(x: right - 6, y: rect.midY - 3, width: 6, height: 6).fill()
            right -= 6 + 6
        case nil:
            break
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        let name = NSAttributedString(string: entry.name, attributes: [
            .font: Self.name, .foregroundColor: NSColor(nameColor(row)), .paragraphStyle: style,
        ])
        let height = ceil(Self.name.ascender - Self.name.descender)
        name.draw(with: NSRect(x: x, y: rect.midY - height / 2, width: max(0, right - x), height: height),
                  options: [.usesLineFragmentOrigin])
    }

    private func nameColor(_ row: FileListRow) -> Color {
        switch row.mark {
        case .file(.modified)?, .file(.renamed)?: Ledger.changed
        case .file(.added)?, .file(.untracked)?: Ledger.done
        case .file(.deleted)?: Ledger.fail
        default: row.ignored ? Ledger.ink3 : Ledger.ink
        }
    }

    // MARK: Mouse

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { hover(row(at: convert(event.locationInWindow, from: nil))) }
    override func mouseEntered(with event: NSEvent) { hover(row(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { hover(nil) }

    private func hover(_ index: Int?) {
        guard index != hovered else { return }
        // The square of the row left and of the row reached changes colour.
        for old in [hovered, index].compactMap({ $0 }) where rows.indices.contains(old) {
            text.setNeedsDisplay(rect(of: old))
        }
        hovered = index
        placeFills()
        removeAllToolTips()
        if let index { addToolTip(rect(of: index), owner: self, userData: nil) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        row(at: point).map { rows[$0].entry.path } ?? ""
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressed = row(at: point).map { ($0, point) }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let pressed, row(at: convert(event.locationInWindow, from: nil)) == pressed.row else { return }
        click?(rows[pressed.row].entry)
    }

    /// Dragging a row hands its file to wherever it is dropped, as Finder does.
    override func mouseDragged(with event: NSEvent) {
        guard let start = pressed else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.at.x, point.y - start.at.y) > 3 else { return }
        pressed = nil
        let file = FileRef(root: root, path: rows[start.row].entry.path)
        let item = NSDraggingItem(pasteboardWriter: file.url as NSURL)
        let frame = rect(of: start.row)
        let image = NSImage(size: frame.size)
        if let rep = bitmapImageRepForCachingDisplay(in: frame) {
            cacheDisplay(in: frame, to: rep)
            image.addRepresentation(rep)
        }
        item.setDraggingFrame(frame, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let index = row(at: convert(event.locationInWindow, from: nil)) else { return nil }
        let entry = rows[index].entry
        let file = FileRef(root: root, path: entry.path)
        let model = AppModel.shared
        let menu = NSMenu()
        menu.autoenablesItems = false
        if !entry.isFolder {
            menu.addItem(ActionItem("Preview") { model.preview = file })
            menu.addItem(ActionItem("Insert into Terminal", enabled: typeable) { model.insertMention(file) })
            menu.addItem(ActionItem("Open") { model.openInEditor(file) })
            menu.addItem(.separator())
        }
        menu.addItem(ActionItem("Reveal in Finder") { model.revealInFinder(file) })
        menu.addItem(ActionItem("Copy Path") { model.copyPath(file) })
        return menu
    }

    // MARK: Accessibility

    private var accessibilityRows: [NSAccessibilityElement]?

    override func accessibilityChildren() -> [Any]? {
        if let accessibilityRows { return accessibilityRows }
        let elements = rows.indices.map { index -> NSAccessibilityElement in
            let row = rows[index]
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(rect(of: index))
            var label = row.entry.name
            if case .file(let git)? = row.mark { label += ", \(gitMarkLabel(git))" }
            if row.mark == .folder { label += ", has changes" }
            element.setAccessibilityLabel(label)
            element.setAccessibilitySelected(row.entry.path == cursor)
            return element
        }
        accessibilityRows = elements
        return elements
    }
}

/// The fill behind a row, in a colour that follows the light or dark look.
private final class RowFill: NSView {
    private let color: Color

    init(color: Color) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("RowFill is built in code") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor(color).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The rows' icons and text, drawn for the part on screen only.
private final class RowsText: NSView {
    private unowned let list: FileListView

    init(list: FileListView) {
        self.list = list
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("RowsText is built in code") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) { list.drawRows(in: dirtyRect) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension FileListView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, enabled: Bool = true, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("ActionItem is built in code") }

    @objc private func runAction() { run() }
}

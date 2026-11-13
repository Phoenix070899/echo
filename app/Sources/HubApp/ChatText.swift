import AppKit
import HubCore
import SwiftUI

extension NSAttributedString.Key {
    /// A code block's lines, with the block's number: the rounded fill is drawn behind them.
    static let echoCode = NSAttributedString.Key("echo.code")
    /// A quoted paragraph, with its block number: the bar at its left.
    static let echoQuote = NSAttributedString.Key("echo.quote")
    /// A heading with a rule under it.
    static let echoRuleBelow = NSAttributedString.Key("echo.ruleBelow")
    /// Inline `code`, which is never turned into a link.
    static let echoInlineCode = NSAttributedString.Key("echo.inlineCode")
}

/// Text in the chat (ui-ux/0091): a run of Markdown blocks, or a plain message, drawn by one
/// AppKit text view, so a drag selects across paragraphs and list items, links show the pointing
/// hand, and a finished selection is copied at once. SwiftUI's `Text` selects one block at a
/// time and has no link cursor.
struct ChatText: NSViewRepresentable {
    enum Source: Equatable {
        case markdown([MarkdownBlock])
        case plain(String)
    }

    let source: Source
    var size: CGFloat = 15
    /// Extra space between wrapped lines.
    var leading: CGFloat = 6
    /// Inline `code`, a little smaller than the text around it.
    var code: CGFloat = 13
    var color: Color = Ledger.ink
    @Environment(\.colorScheme) private var scheme

    private struct Key: Equatable {
        let source: Source
        let size: CGFloat
        let leading: CGFloat
        let code: CGFloat
        let color: Color
        let scheme: ColorScheme
    }

    private func key(_ scheme: ColorScheme) -> Key {
        Key(source: source, size: size, leading: leading, code: code, color: color, scheme: scheme)
    }

    func makeNSView(context: Context) -> EchoTextView {
        let view = EchoTextView()
        apply(to: view, scheme: context.environment.colorScheme)
        return view
    }

    func updateNSView(_ view: EchoTextView, context: Context) {
        apply(to: view, scheme: context.environment.colorScheme)
    }

    /// Redraws only when something it shows changed, so a selection survives the chat's polling.
    private func apply(to view: EchoTextView, scheme: ColorScheme) {
        let key = key(scheme)
        guard view.appliedKey as? Key != key else { return }
        view.appliedKey = key
        let builder = ChatTextBuilder(size: size, leading: leading, code: code, color: color, appearance: view.effectiveAppearance)
        let hugs: Bool
        if case .plain = source { hugs = true } else { hugs = false }
        view.show(builder.build(source), hugs: hugs)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EchoTextView, context: Context) -> CGSize? {
        let offered = proposal.width.map { max(1, $0) } ?? 10_000
        return nsView.fit(width: offered)
    }
}

/// What `ChatTextBuilder` makes of a source: the text, and the room the first and last code
/// blocks need above and below it.
struct ChatTextBuilt {
    let text: NSAttributedString
    let topPad: CGFloat
    let bottomPad: CGFloat
    let wash: NSColor
    let rule: NSColor
    let link: NSColor
}

/// Turns Markdown blocks into one attributed string, in the look the blocks have as SwiftUI views
/// (`MarkdownBlockView`): same sizes, gaps, markers, and tints.
@MainActor
struct ChatTextBuilder {
    let size: CGFloat
    let leading: CGFloat
    let code: CGFloat
    let ink: NSColor
    let ink2: NSColor
    let ink3: NSColor
    let done: NSColor
    let wash: NSColor
    let rule: NSColor
    let link: NSColor
    /// The colour the whole text takes, `ink` unless the caller asked for another.
    let base: NSColor

    /// A code card's padding, above and below its text.
    static let codePad: CGFloat = 10

    init(size: CGFloat, leading: CGFloat, code: CGFloat, color: Color, appearance: NSAppearance) {
        self.size = size
        self.leading = leading
        self.code = code
        ink = Self.resolve(Ledger.ink, appearance)
        ink2 = Self.resolve(Ledger.ink2, appearance)
        ink3 = Self.resolve(Ledger.ink3, appearance)
        done = Self.resolve(Ledger.done, appearance)
        wash = Self.resolve(Ledger.wash, appearance)
        rule = Self.resolve(Ledger.rule, appearance)
        link = Self.resolve(Ledger.run, appearance)
        base = Self.resolve(color, appearance)
    }

    private static func resolve(_ color: Color, _ appearance: NSAppearance) -> NSColor {
        var out = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance { out = NSColor(color).usingColorSpace(.sRGB) ?? out }
        return out
    }

    func build(_ source: ChatText.Source) -> ChatTextBuilt {
        switch source {
        case .plain(let text):
            let style = NSMutableParagraphStyle()
            style.lineSpacing = leading
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Ledger.nsFont(size), .foregroundColor: base, .paragraphStyle: style,
            ]
            return ChatTextBuilt(text: linkified(NSAttributedString(string: text, attributes: attributes)),
                                 topPad: 0, bottomPad: 0, wash: wash, rule: rule, link: link)
        case .markdown(let blocks):
            return markdown(blocks)
        }
    }

    // MARK: Blocks

    private func markdown(_ blocks: [MarkdownBlock]) -> ChatTextBuilt {
        let out = NSMutableAttributedString()
        var previous: MarkdownBlock?
        var topPad: CGFloat = 0
        var carry: CGFloat = 0
        // AppKit adds a paragraph's line spacing after its last line too; SwiftUI does not. The
        // gap before the next block gives that much back.
        var trailing: CGFloat = 0
        for (number, block) in blocks.enumerated() {
            if out.length > 0 {
                // The break belongs to the paragraph before it.
                out.append(NSAttributedString(string: "\n", attributes: out.attributes(at: out.length - 1, effectiveRange: nil)))
            }
            let gap = previous.map { max(0, MarkdownBlockView.gap($0, block) - trailing) } ?? 0
            let before = gap + carry
            carry = 0
            switch block {
            case .heading(let level, let text):
                let sizes: [CGFloat] = [26, 20, 16.5, 15, 14, 13.5]
                let font = Ledger.nsFont(sizes[min(max(level, 1), 6) - 1], .semibold)
                var attributes = attrs(font, level == 6 ? ink2 : base, before: before, line: 2)
                if level <= 2 {
                    attributes[.paragraphStyle] = paragraph(before: before, line: 2, after: 9)
                    attributes[.echoRuleBelow] = number
                }
                out.append(inline(text, attributes))
            case .paragraph(let text):
                out.append(inline(text, attrs(Ledger.nsFont(size), base, before: before, line: leading)))
            case .bullet(let text, let ordered, let depth, let checked):
                let indent = 4 + CGFloat(depth) * 22
                let column: CGFloat = 24
                let style = paragraph(before: before, line: leading, first: indent, head: indent + column)
                style.tabStops = [NSTextTab(textAlignment: .left, location: indent + column)]
                var marker: String
                var markerColor = ink2
                var markerFont = Ledger.nsFont(size)
                if let checked {
                    marker = checked ? "☑" : "☐"
                    markerColor = checked ? done : ink3
                } else if let ordered {
                    marker = "\(ordered)."
                    markerFont = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
                } else {
                    marker = ["•", "◦", "▪"][depth % 3]
                }
                out.append(NSAttributedString(string: marker + "\t", attributes: [
                    .font: markerFont, .foregroundColor: markerColor, .paragraphStyle: style,
                ]))
                out.append(inline(text, [
                    .font: Ledger.nsFont(size), .foregroundColor: checked == true ? ink2 : base, .paragraphStyle: style,
                ]))
            case .quote(let text):
                var attributes = attrs(Ledger.nsFont(size), ink2, before: before, line: leading)
                attributes[.paragraphStyle] = paragraph(before: before, line: leading, first: 15, head: 15)
                attributes[.echoQuote] = number
                out.append(inline(text, attributes))
            case .code(let text, let language):
                let pad = Self.codePad
                // The first block has nothing above it for the card's padding to sit in.
                let lead = out.length == 0 ? 0 : before + pad
                if out.length == 0 { topPad = pad }
                var lines = text.components(separatedBy: "\n")
                if lines.last == "" { lines.removeLast() }
                var first = true
                if !language.isEmpty {
                    out.append(NSAttributedString(string: language + "\n", attributes: [
                        .font: Ledger.nsFont(11), .foregroundColor: ink3, .echoCode: number,
                        .paragraphStyle: paragraph(before: lead, line: 0, first: 12, head: 12, tail: -12, after: 6),
                    ]))
                    first = false
                }
                for (index, line) in lines.enumerated() {
                    out.append(NSAttributedString(string: line + (index < lines.count - 1 ? "\n" : ""), attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular), .foregroundColor: base,
                        .echoCode: number,
                        .paragraphStyle: paragraph(before: first ? lead : 0, line: 2, first: 12, head: 12, tail: -12),
                    ]))
                    first = false
                }
                carry = pad
            case .frontMatter, .table, .rule:
                break
            }
            previous = block
            trailing = switch block {
            case .paragraph, .bullet, .quote: leading
            case .heading, .code: 2
            case .frontMatter, .table, .rule: 0
            }
        }
        return ChatTextBuilt(text: out, topPad: topPad, bottomPad: carry, wash: wash, rule: rule, link: link)
    }

    private func attrs(_ font: NSFont, _ color: NSColor, before: CGFloat, line: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color, .paragraphStyle: paragraph(before: before, line: line)]
    }

    private func paragraph(before: CGFloat, line: CGFloat, first: CGFloat = 0, head: CGFloat = 0,
                           tail: CGFloat = 0, after: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineSpacing = line
        style.firstLineHeadIndent = first
        style.headIndent = head
        style.tailIndent = tail
        return style
    }

    // MARK: Inline

    /// Bold, italics, `code`, strikethrough, and links, as the block views draw them; bare
    /// http(s) addresses become links too.
    private func inline(_ text: String, _ base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var source = text
        for tag in ["<br>", "<br/>", "<br />"] { source = source.replacingOccurrences(of: tag, with: "\n") }
        guard let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return linkified(NSAttributedString(string: source, attributes: base)) }
        let out = NSMutableAttributedString()
        let manager = NSFontManager.shared
        for run in parsed.runs {
            var attributes = base
            let intent = run.inlinePresentationIntent ?? []
            var font = (base[.font] as? NSFont) ?? Ledger.nsFont(size)
            if intent.contains(.code) {
                font = .monospacedSystemFont(ofSize: code, weight: .regular)
                attributes[.backgroundColor] = wash
                attributes[.echoInlineCode] = true
            }
            if intent.contains(.stronglyEmphasized) { font = manager.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = manager.convert(font, toHaveTrait: .italicFontMask) }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            attributes[.font] = font
            if let link = run.link { attributes[.link] = link }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return linkified(out)
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Makes the http(s) addresses in the text links. Only a written scheme counts: "README.md"
    /// and "e.g." look like web addresses to the detector, and are not.
    private func linkified(_ text: NSAttributedString) -> NSAttributedString {
        guard text.string.contains("http"), let detector = Self.detector else { return text }
        let out = NSMutableAttributedString(attributedString: text)
        let string = text.string as NSString
        for match in detector.matches(in: text.string, range: NSRange(location: 0, length: string.length)) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  string.substring(with: match.range).lowercased().hasPrefix("http"),
                  out.attribute(.link, at: match.range.location, effectiveRange: nil) == nil,
                  out.attribute(.echoInlineCode, at: match.range.location, effectiveRange: nil) == nil
            else { continue }
            out.addAttribute(.link, value: url, range: match.range)
        }
        return out
    }
}

/// The text view behind `ChatText`: read-only, transparent, as tall as its text.
final class EchoTextView: NSTextView, NSTextViewDelegate {
    var appliedKey: Any?
    private var topPad: CGFloat = 0
    private var bottomPad: CGFloat = 0
    private var wash = NSColor.clear
    private var rule = NSColor.clear
    private var hugs = false

    init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        isAutomaticLinkDetectionEnabled = false
        allowsUndo = false
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ built: ChatTextBuilt, hugs: Bool) {
        topPad = built.topPad
        bottomPad = built.bottomPad
        wash = built.wash
        rule = built.rule
        self.hugs = hugs
        // The pointing hand is what shows the pointer over a link.
        linkTextAttributes = [
            .foregroundColor: built.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textStorage?.setAttributedString(built.text)
        setSelectedRange(NSRange(location: 0, length: 0))
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var textContainerOrigin: NSPoint { NSPoint(x: 0, y: topPad) }

    /// Lays the text out in `width` and sizes the view to it. A plain message is as wide as its
    /// longest line, so a short one makes a short bubble; Markdown fills the width.
    func fit(width: CGFloat) -> CGSize {
        guard let layoutManager, let textContainer else { return .zero }
        if textContainer.containerSize.width != width {
            textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let size = NSSize(width: hugs ? min(width, ceil(used.width)) : width, height: ceil(used.height) + topPad + bottomPad)
        if frame.size != size { setFrameSize(size) }
        return size
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawDecorations()
        super.draw(dirtyRect)
    }

    /// What the text carries behind and beside it: code cards, quote bars, the rule under a heading.
    private func drawDecorations() {
        guard let layoutManager, let storage = textStorage, storage.length > 0 else { return }
        let origin = textContainerOrigin
        let whole = NSRange(location: 0, length: storage.length)
        func box(_ range: NSRange) -> NSRect? {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var box = NSRect.null
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in box = box.union(used) }
            return box.isNull ? nil : box.offsetBy(dx: origin.x, dy: origin.y)
        }
        storage.enumerateAttribute(.echoCode, in: whole) { value, range, _ in
            guard value != nil, let box = box(range) else { return }
            wash.setFill()
            let card = NSRect(x: 0, y: box.minY - ChatTextBuilder.codePad, width: bounds.width,
                              height: box.height + 2 * ChatTextBuilder.codePad)
            NSBezierPath(roundedRect: card, xRadius: Ledger.radiusElement, yRadius: Ledger.radiusElement).fill()
        }
        storage.enumerateAttribute(.echoQuote, in: whole) { value, range, _ in
            guard value != nil, let box = box(range) else { return }
            rule.setFill()
            NSRect(x: 0, y: box.minY, width: 3, height: box.height).fill()
        }
        storage.enumerateAttribute(.echoRuleBelow, in: whole) { value, range, _ in
            guard value != nil, let box = box(range) else { return }
            rule.setFill()
            NSRect(x: 0, y: box.maxY + 8, width: bounds.width, height: 1).fill()
        }
    }

    // MARK: Selecting and copying

    /// Dragging is a loop inside `super`; when it returns the mouse is up and the selection is
    /// done, so that is when it is copied.
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        copySelection()
    }

    override func copy(_ sender: Any?) { copySelection() }

    /// The selected text as plain text, put on the clipboard. Nothing happens for a bare click.
    private func copySelection() {
        let range = selectedRange()
        guard range.length > 0, let text = textStorage?.attributedSubstring(from: range).string else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    /// One selection on the screen at a time: picking text elsewhere lets go of this one.
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { setSelectedRange(NSRange(location: 0, length: 0)) }
        return resigned
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url, url.scheme != nil else { return true }
        NSWorkspace.shared.open(url)
        return true
    }
}

/// A reply's or a report's Markdown, with the runs of text drawn as one selectable view and the
/// blocks that are not text (tables, rules, front matter) between them.
struct ChatMarkdown: View {
    let blocks: [MarkdownBlock]
    var size: CGFloat = 15
    var leading: CGFloat = 6
    var code: CGFloat = 13
    var color: Color = Ledger.ink

    private struct Run {
        var blocks: [MarkdownBlock]
        var isText: Bool
    }

    private static func runs(_ blocks: [MarkdownBlock]) -> [Run] {
        var runs: [Run] = []
        for block in blocks {
            let text: Bool = switch block {
            case .heading, .paragraph, .bullet, .quote, .code: true
            case .frontMatter, .table, .rule: false
            }
            if text, let last = runs.last, last.isText {
                runs[runs.count - 1].blocks.append(block)
            } else {
                runs.append(Run(blocks: [block], isText: text))
            }
        }
        return runs
    }

    var body: some View {
        let runs = Self.runs(blocks)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(runs.indices, id: \.self) { index in
                let run = runs[index]
                Group {
                    if run.isText {
                        ChatText(source: .markdown(run.blocks), size: size, leading: leading, code: code, color: color)
                    } else {
                        MarkdownBlockView(block: run.blocks[0], leading: leading, codeSize: code)
                    }
                }
                .padding(.top, index == 0 ? 0 : MarkdownBlockView.gap(runs[index - 1].blocks[runs[index - 1].blocks.count - 1], run.blocks[0]))
            }
        }
    }
}

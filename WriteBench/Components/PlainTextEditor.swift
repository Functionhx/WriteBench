import SwiftUI
import AppKit

enum EditorFont: String, CaseIterable, Identifiable {
    case sans, serif
    var id: String { rawValue }
    var title: String { self == .sans ? "无衬线 · SF / 苹方" : "衬线 · New York / 宋体" }
    func font(size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        guard self == .serif, let serif = system.fontDescriptor.withDesign(.serif) else { return system }
        // Chinese falls back to Songti so both scripts read as one serif page.
        let descriptor = serif.addingAttributes([.cascadeList: [NSFontDescriptor(name: "Songti SC", size: size)]])
        return NSFont(descriptor: descriptor, size: size) ?? system
    }
}

struct EditorAlignmentRequest {
    let id = UUID()
    let alignment: NSTextAlignment
}

/// A plain-text Mac editor with native selection, find, spelling, and undo/redo.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var fontStyle: EditorFont = .sans
    var editable = true
    var identifier = "essayEditor"
    var ruled = false
    /// Answer-sheet look: dark printed rules and the question number in the left margin.
    var sheetNumber: String? = nil
    var requestFocus = false
    var alignmentRequest: EditorAlignmentRequest? = nil

    struct Style: Equatable {
        var font: EditorFont
        var size: CGFloat
        var ruled: Bool
        var sheetNumber: String? = nil
        /// Ruled paper uses one fixed line pitch so every line sits on its own rule.
        var lineHeight: CGFloat { ruled ? (size * 2).rounded() : (size * 1.55).rounded() }
    }
    private var style: Style { Style(font: fontStyle, size: fontSize, ruled: ruled, sheetNumber: sheetNumber) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = RuledTextView()
        view.focusOnAttachment = requestFocus
        view.isRichText = false
        view.isEditable = editable
        view.isSelectable = true
        view.allowsUndo = true
        view.usesFindBar = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.layoutManager?.usesFontLeading = false
        view.delegate = context.coordinator
        view.setAccessibilityIdentifier(identifier)
        let labels = ["essayEditor": "我的作文", "questionEditor": "题目文字", "textQuestionImportEditor": "导入题目文字", "rewriteEditor": "重写作文", "ocrEssayEditor": "识别文字校对", "ocrQuestionEditor": "识别题目校对"]
        view.setAccessibilityLabel(labels[identifier] ?? "Writing editor")
        view.string = text
        view.apply(style)
        context.coordinator.style = style
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? RuledTextView else { return }
        if view.string != text, !view.hasMarkedText() { view.string = text; view.undoManager?.removeAllActions(); view.apply(style) }
        if context.coordinator.style != style { context.coordinator.style = style; view.apply(style) }
        view.isEditable = editable
        if let request = alignmentRequest, context.coordinator.lastAlignmentID != request.id {
            context.coordinator.lastAlignmentID = request.id
            DispatchQueue.main.async { [weak view] in
                view?.alignLines(request.alignment)
                if let view { view.window?.makeFirstResponder(view) }
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        var style: Style?
        var lastAlignmentID: UUID?
        init(_ parent: PlainTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

@MainActor final class RuledTextView: NSTextView {
    var focusOnAttachment = false
    private var didFocus = false
    private var style = PlainTextEditor.Style(font: .sans, size: 16, ruled: false)
    /// Baseline position inside a line fragment, measured with the real layout machinery.
    private var baseline: CGFloat = 0

    func apply(_ style: PlainTextEditor.Style) {
        self.style = style
        let font = style.font.font(size: style.size)
        // Lines keep the font's natural height and the rest of the pitch is spacing after the line,
        // so the insertion point stays as tall as the text instead of filling the whole ruled line.
        let natural = ceil(font.ascender - font.descender + font.leading)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = natural
        paragraph.maximumLineHeight = natural
        paragraph.lineSpacing = max(0, style.lineHeight - natural)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(WB.ink), .paragraphStyle: paragraph]
        self.font = font
        defaultParagraphStyle = paragraph
        typingAttributes = attributes
        if let storage = textStorage, storage.length > 0, !hasMarkedText() {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
        textContainerInset = style.sheetNumber != nil ? NSSize(width: 46, height: 18) : style.ruled ? NSSize(width: 28, height: 18) : NSSize(width: 14, height: 14)
        baseline = Self.measureBaseline(attributes, width: 400)
        // The system indicator is thick, accent-coloured and as tall as the line; a quiet ink caret replaces it.
        insertionPointColor = .clear
        needsDisplay = true
        updateCaret()
    }

    // Alignment is encoded as spaces, so saving, reopening and grading preserve the same text.
    override func alignLeft(_ sender: Any?) { alignLines(.left) }
    override func alignCenter(_ sender: Any?) { alignLines(.center) }
    override func alignRight(_ sender: Any?) { alignLines(.right) }
    func alignLines(_ alignment: NSTextAlignment) {
        guard isEditable, !hasMarkedText(), let container = textContainer else { return }
        let source = string as NSString
        let selection = selectedRange()
        var selected = selection
        // A selection ending at the next line's start should not align that next line.
        if selected.length > 0, selected.location + selected.length <= source.length,
           source.character(at: selected.location + selected.length - 1) == 10 { selected.length -= 1 }
        let range = source.lineRange(for: selected)
        let old = source.substring(with: range)
        let font = style.font.font(size: style.size)
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let available = max(0, container.containerSize.width - 2 * container.lineFragmentPadding)
        var lines = old.components(separatedBy: "\n")
        for index in lines.indices {
            if index == lines.count - 1, lines[index].isEmpty, old.hasSuffix("\n") { continue }
            let content = lines[index].trimmingCharacters(in: .whitespaces)
            let width = (content as NSString).size(withAttributes: [.font: font]).width
            let fraction: CGFloat = alignment == .right ? 1 : alignment == .center ? 0.5 : 0
            let count = spaceWidth > 0 ? max(0, Int(floor((available - width) * fraction / spaceWidth))) : 0
            lines[index] = String(repeating: " ", count: count) + content
        }
        let replacement = lines.joined(separator: "\n")
        guard replacement != old else { return }
        insertText(replacement, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + (replacement as NSString).length - (replacement.hasSuffix("\n") ? 1 : 0), length: 0))
    }
    override func insertTab(_ sender: Any?) {
        guard isEditable else { return }
        insertText("    ", replacementRange: selectedRange())
    }

    // MARK: Caret

    private let caret: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(WB.ink).withAlphaComponent(0.85).cgColor
        view.layer?.cornerRadius = 0.75
        view.isHidden = true
        return view
    }()
    private var blink: Timer?

    /// Where the caret goes: at the insertion point, spanning the text's ascender to just under its baseline.
    func caretFrame() -> NSRect? {
        guard let manager = layoutManager, let container = textContainer, selectedRange().length == 0 else { return nil }
        manager.ensureLayout(for: container)
        let text = string as NSString, index = selectedRange().location
        let lineRect: NSRect, x: CGFloat
        if text.length == 0 || (index >= text.length && text.character(at: text.length - 1) == 10) {
            lineRect = manager.extraLineFragmentRect
            x = lineRect.minX + container.lineFragmentPadding
        } else if index >= text.length {
            let glyph = manager.glyphIndexForCharacter(at: text.length - 1)
            lineRect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            var positions = [CGFloat](repeating: 0, count: text.length + 1)
            var indexes = [Int](repeating: 0, count: text.length + 1)
            let count = manager.getLineFragmentInsertionPoints(forCharacterAt: text.length - 1, alternatePositions: false,
                                                               inDisplayOrder: false, positions: &positions, characterIndexes: &indexes)
            if let point = (0..<count).first(where: { indexes[$0] == index }) {
                x = lineRect.minX + positions[point]
            } else {
                x = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).maxX
            }
        } else {
            let glyph = manager.glyphIndexForCharacter(at: index)
            lineRect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            x = lineRect.minX + manager.location(forGlyphAt: glyph).x
        }
        let font = style.font.font(size: style.size)
        let top = lineRect.minY + baseline - ceil(font.ascender * 0.92)
        let height = ceil(font.ascender * 0.92) + ceil(abs(font.descender) * 0.75)
        return NSRect(x: textContainerOrigin.x + x - 0.75, y: textContainerOrigin.y + top, width: 1.5, height: height)
    }
    func updateCaret(restartBlink: Bool = true) {
        if caret.superview == nil { addSubview(caret) }
        guard window?.firstResponder === self, window?.isKeyWindow == true, isEditable, let frame = caretFrame() else {
            caret.isHidden = true; blink?.invalidate(); blink = nil; return
        }
        caret.frame = frame
        caret.isHidden = false
        guard restartBlink else { return }
        blink?.invalidate()
        blink = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.caret.isHidden.toggle() }
        }
    }
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateCaret()
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        updateCaret()
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.updateCaret() }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { caret.isHidden = true; blink?.invalidate(); blink = nil }
        return resigned
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateCaret(restartBlink: false)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        NotificationCenter.default.removeObserver(self)
        guard let newWindow else { blink?.invalidate(); blink = nil; return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged), name: name, object: newWindow)
        }
    }
    @objc private func windowKeyChanged() { updateCaret() }

    /// Lays out a Latin + CJK sample with the same attributes so empty pages rule exactly like typed ones.
    private static func measureBaseline(_ attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(string: "Hg中，", attributes: attributes)
        let manager = NSLayoutManager()
        manager.usesFontLeading = false
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return manager.location(forGlyphAt: 0).y
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusOnAttachment, !didFocus, let window {
            didFocus = true
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
    override func didChangeText() {
        super.didChangeText()
        updateCaret()
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if style.ruled {
            let pitch = style.lineHeight
            let descent = ceil(abs(style.font.font(size: style.size).descender))
            // One rule per line, just below the descenders of that line.
            let first = textContainerOrigin.y + baseline + descent + max(3, (pitch - baseline - descent) * 0.3)
            let left = textContainerInset.width, right = bounds.width - textContainerInset.width
            let path = NSBezierPath()
            var y = first + max(0, floor((dirtyRect.minY - first) / pitch)) * pitch
            while y < dirtyRect.maxY + pitch {
                let aligned = floor(y) + 0.5
                path.move(to: NSPoint(x: left, y: aligned))
                path.line(to: NSPoint(x: right, y: aligned))
                y += pitch
            }
            if style.sheetNumber != nil {
                // Printed answer sheets use dark, fine rules.
                NSColor(white: 0.2, alpha: 0.72).setStroke()
                path.lineWidth = 0.75
            } else {
                NSColor(red: 0.84, green: 0.87, blue: 0.93, alpha: 1).setStroke()
                path.lineWidth = 1
            }
            path.stroke()
            if let number = style.sheetNumber {
                let labelFont = NSFont.systemFont(ofSize: 11)
                let label = NSAttributedString(string: number, attributes: [.font: labelFont, .foregroundColor: NSColor(white: 0.15, alpha: 1)])
                // Same baseline as the first line of writing, in the left margin like the printed sheet.
                label.draw(at: NSPoint(x: left - label.size().width - 8, y: textContainerOrigin.y + baseline - labelFont.ascender))
            }
        }
        super.draw(dirtyRect)
    }
}

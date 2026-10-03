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

/// A plain-text Mac editor with native selection, find, spelling, and undo/redo.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var fontStyle: EditorFont = .sans
    var editable = true
    var identifier = "essayEditor"
    var ruled = false
    var requestFocus = false

    struct Style: Equatable {
        var font: EditorFont
        var size: CGFloat
        var ruled: Bool
        /// Ruled paper uses one fixed line pitch so every line sits on its own rule.
        var lineHeight: CGFloat { ruled ? (size * 2).rounded() : (size * 1.55).rounded() }
    }
    private var style: Style { Style(font: fontStyle, size: fontSize, ruled: ruled) }

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
        view.insertionPointColor = NSColor(WB.blue)
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
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        var style: Style?
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
        textContainerInset = style.ruled ? NSSize(width: 28, height: 18) : NSSize(width: 14, height: 14)
        baseline = Self.measureBaseline(attributes, width: 400)
        needsDisplay = true
    }

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
            NSColor(red: 0.84, green: 0.87, blue: 0.93, alpha: 1).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        super.draw(dirtyRect)
    }
}

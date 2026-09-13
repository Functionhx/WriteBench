import SwiftUI
import AppKit

/// A plain-text Mac editor with native selection, find, spelling, and undo/redo.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var editable = true
    var identifier = "essayEditor"
    var ruled = false
    var requestFocus = false
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = RuledTextView()
        view.showsRuling = ruled
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
        view.font = ruled ? (NSFont(name: "TimesNewRomanPSMT", size: fontSize) ?? .systemFont(ofSize: fontSize)) : .systemFont(ofSize: fontSize)
        view.textColor = NSColor(WB.ink)
        view.insertionPointColor = NSColor(WB.blue)
        view.textContainerInset = ruled ? NSSize(width: 24, height: 20) : NSSize(width: 12, height: 14)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = ruled ? 0 : 6
        if ruled { style.minimumLineHeight = 34; style.maximumLineHeight = 34; view.layoutManager?.usesFontLeading = false }
        view.defaultParagraphStyle = style
        view.typingAttributes = [.font: view.font ?? NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor(WB.ink), .paragraphStyle: style]
        view.delegate = context.coordinator
        view.setAccessibilityIdentifier(identifier)
        let labels = ["essayEditor": "我的作文", "questionEditor": "题目文字", "textQuestionImportEditor": "导入题目文字", "rewriteEditor": "重写作文", "ocrEssayEditor": "识别文字校对", "ocrQuestionEditor": "识别题目校对"]
        view.setAccessibilityLabel(labels[identifier] ?? "Writing editor")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text; view.undoManager?.removeAllActions() }
        view.isEditable = editable
        view.needsDisplay = true
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        init(_ parent: PlainTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            view.needsDisplay = true
        }
    }
}

@MainActor final class RuledTextView: NSTextView {
    var showsRuling = false
    var focusOnAttachment = false
    private var didFocus = false
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
    override func draw(_ dirtyRect: NSRect) {
        if showsRuling {
            let lineHeight: CGFloat = 34
            var baseline: CGFloat = 25
            if let layoutManager, let textContainer {
                layoutManager.ensureLayout(for: textContainer)
                if layoutManager.numberOfGlyphs > 0 { baseline = layoutManager.location(forGlyphAt: 0).y }
            }
            let first = textContainerOrigin.y + baseline + 4
            let path = NSBezierPath()
            var y = first + max(0, floor((dirtyRect.minY - first) / lineHeight)) * lineHeight
            while y < dirtyRect.maxY {
                path.move(to: NSPoint(x: textContainerInset.width, y: y))
                path.line(to: NSPoint(x: bounds.width - textContainerInset.width, y: y))
                y += lineHeight
            }
            NSColor(white: 0.84, alpha: 1).setStroke(); path.lineWidth = 0.5; path.stroke()
        }
        super.draw(dirtyRect)
    }
}

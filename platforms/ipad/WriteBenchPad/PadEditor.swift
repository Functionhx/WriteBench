import SwiftUI
import UIKit

struct PadEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var richText: Data?
    var identifier: String
    var editable = true
    var command: EditorCommand?
    enum EditorCommand: Equatable { case spaces(UUID), alignment(NSTextAlignment, UUID) }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.accessibilityIdentifier = identifier
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        view.autocorrectionType = .no; view.spellCheckingType = .no
        view.smartQuotesType = .no; view.smartDashesType = .no
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { let range = view.selectedRange; view.text = text; if range.location <= (text as NSString).length { view.selectedRange = range } }
        if richText != context.coordinator.lastRichText {
            if let richText, let attributed = try? NSAttributedString(data: richText, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil), attributed.string == text {
                let selection = view.selectedRange; view.attributedText = attributed; view.selectedRange = selection
            }
            context.coordinator.lastRichText = richText
        }
        view.isEditable = editable
        if let command, command != context.coordinator.lastCommand {
            context.coordinator.lastCommand = command
            switch command {
            case .spaces: view.becomeFirstResponder(); view.insertText("    ")
            case .alignment(let alignment, _):
                // Apply only to selected/current paragraphs, preserving whitespace and undo.
                let ns = view.text as NSString
                let selection = view.selectedRange
                let range = ns.paragraphRange(for: selection)
                let style = NSMutableParagraphStyle(); style.alignment = alignment
                view.textStorage.addAttribute(.paragraphStyle, value: style, range: range)
                view.typingAttributes[.paragraphStyle] = style
                context.coordinator.textViewDidChange(view)
            }
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PadEditor
        var lastCommand: EditorCommand?
        var lastRichText: Data?
        init(_ parent: PadEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            let data = try? textView.attributedText.data(from: NSRange(location: 0, length: textView.attributedText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            lastRichText = data; parent.richText = data
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\t" { textView.insertText("    "); return false }; return true
        }
    }
}

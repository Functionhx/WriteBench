import SwiftUI

/// Question text may mark exam underlines as `<u>…</u>`, the way a paper underlines the segments to translate.
/// Graders receive the markup verbatim; people see a real underline.
enum QuestionText {
    private static let open = "<u>", close = "</u>"

    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: open, with: "").replacingOccurrences(of: close, with: "")
    }

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(text)
        while let start = rest.range(of: open) {
            result += styled(rest[..<start.lowerBound])
            let after = rest[start.upperBound...]
            guard let end = after.range(of: close) else { result += styled(after); return result }
            var underlined = styled(after[..<end.lowerBound])
            underlined.underlineStyle = Text.LineStyle(pattern: .solid, color: WB.ink.opacity(0.75))
            result += underlined
            rest = after[end.upperBound...]
        }
        return result + styled(rest)
    }

    /// Section headings such as 【配图说明】 read as headings rather than body text.
    private static func styled(_ text: Substring) -> AttributedString {
        var output = AttributedString()
        var rest = text
        while let start = rest.range(of: "【"), let end = rest[start.upperBound...].range(of: "】") {
            output += AttributedString(String(rest[..<start.lowerBound]))
            var heading = AttributedString(String(rest[start.lowerBound..<end.upperBound]))
            heading.inlinePresentationIntent = .stronglyEmphasized
            output += heading
            rest = rest[end.upperBound...]
        }
        return output + AttributedString(String(rest))
    }
}

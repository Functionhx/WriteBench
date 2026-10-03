import Foundation

/// Locates reviewer-quoted spans in the student's answer despite quote, dash, width and whitespace drift.
/// A correction that cannot be located is dropped instead of invalidating an otherwise complete review.
enum CorrectionMatcher {
    static func anchored(_ corrections: [Correction], in essay: String) -> [Correction] {
        corrections.compactMap { correction in
            guard !correction.corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !correction.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let range = range(of: correction.original, in: essay) else { return nil }
            var located = correction
            located.original = String(essay[range])
            return located
        }
    }

    static func range(of fragment: String, in essay: String) -> Range<String.Index>? {
        let needle = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let exact = essay.range(of: needle) { return exact }
        let haystack = normalized(essay), target = normalized(needle).map(\.character)
        guard !target.isEmpty, target.count <= haystack.count else { return nil }
        for caseInsensitive in [false, true] {
            let pattern = caseInsensitive ? target.map { Character($0.lowercased()) } : target
            outer: for start in 0...(haystack.count - pattern.count) {
                for offset in pattern.indices {
                    let candidate = haystack[start + offset].character
                    guard (caseInsensitive ? Character(candidate.lowercased()) : candidate) == pattern[offset] else { continue outer }
                }
                return haystack[start].range.lowerBound..<haystack[start + pattern.count - 1].range.upperBound
            }
        }
        return nil
    }

    /// One normalized character per source character, except that a whitespace run becomes one space.
    private static func normalized(_ text: String) -> [(character: Character, range: Range<String.Index>)] {
        var output: [(character: Character, range: Range<String.Index>)] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let character = text[index]
            if character.isWhitespace {
                if let last = output.last, last.character == " " {
                    output[output.count - 1].range = last.range.lowerBound..<next
                } else { output.append((" ", index..<next)) }
            } else { output.append((fold(character), index..<next)) }
            index = next
        }
        return output
    }
    private static func fold(_ character: Character) -> Character {
        switch character {
        case "‘", "’", "‚", "‛", "′", "＇", "`": "'"
        case "“", "”", "„", "‟", "″", "＂": "\""
        case "–", "—", "‒", "−", "－": "-"
        case "，": ","
        case "。": "."
        case "；": ";"
        case "：": ":"
        case "！": "!"
        case "？": "?"
        case "（": "("
        case "）": ")"
        default: character
        }
    }

    /// True when two answers differ only by case, quotes, dashes, width or spacing.
    static func equivalent(_ attempt: String, _ reference: String) -> Bool {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = range(of: attempt, in: reference) else { return false }
        return range.lowerBound == reference.startIndex && range.upperBound == reference.endIndex
    }

    /// The sentence that contains a span, for drills that need context.
    static func sentence(containing range: Range<String.Index>, in text: String) -> String {
        let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]
        var start = range.lowerBound
        while start > text.startIndex {
            let previous = text.index(before: start)
            if terminators.contains(text[previous]) { break }
            start = previous
        }
        var end = range.upperBound
        while end < text.endIndex, text[end] != "\n" {
            let character = text[end]
            end = text.index(after: end)
            if terminators.contains(character) { break }
        }
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

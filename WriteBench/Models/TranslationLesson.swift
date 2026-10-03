import Foundation

struct TranslationVocabulary: Codable, Hashable, Sendable {
    var word: String
    var partOfSpeech: String
    var commonMeaning: String
    var contextualMeaning: String
}
struct TranslationMeaningGroup: Codable, Hashable, Sendable {
    var source: String
    var translation: String
    var vocabulary: [TranslationVocabulary]
    var techniques: [String]
}
struct TranslationLesson: Codable, Hashable, Sendable {
    var number: String
    var source: String
    var groups: [TranslationMeaningGroup]
    var referenceTranslation: String
    var assemblyNotes: [String]
    var studentAdvice: String
}

enum TranslationTeaching {
    static let jsonExample = #"""
    "translationLessons": [{"number": "46", "source": "exact complete source sentence", "groups": [{"source": "exact contiguous meaning group", "translation": "意群译文", "vocabulary": [{"word": "word or phrase from this group", "partOfSpeech": "词性", "commonMeaning": "常见释义", "contextualMeaning": "本句释义"}], "techniques": ["结合原文解释具体翻译要点"]}], "referenceTranslation": "完整参考译文", "assemblyNotes": ["组合意群时的语序、逻辑、指代或衔接要点"], "studentAdvice": "结合学生实际译文，说明保留什么、如何修复误译或漏译"}]
    """#
    static func instructions(_ task: WritingTask) -> String {
        guard task == .kaoyanTranslation || task == .kaoyan2Translation else { return "translationLessons must be an empty array for this task." }
        return """
        translationLessons is REQUIRED: act as an experienced translation teacher, helping this student master each source sentence.
        For English I cover ONLY the numbered underlined segments being translated, using their exact numbers; the rest is context.
        For English II cover the sentences in the source passage in order, numbering from 1. Do not apply English I's 2-point rule to English II.
        Each lesson: source is the complete sentence copied verbatim from the question without markup. Split it in order into 3–4 relatively independent, complete meaning groups where natural; use fewer for short sentences rather than breaking a constituent arbitrarily. Preserve all source content and logical links.
        Each group: source is an exact contiguous span of the sentence, translation is Chinese, vocabulary lists only useful English words/phrases occurring in this group (1–3 where useful, otherwise []), with partOfSpeech, commonMeaning and contextualMeaning explained in Chinese. Prioritize CET and exam-relevant vocabulary but do not claim exact official word-list membership without evidence. techniques explains the SPECIFIC source construction and translation choice (passive voice, relative clauses, nominalization, word-class conversion, reference or word order as applicable); no generic checklist or invented construction.
        referenceTranslation combines the group translations into one faithful, natural Chinese sentence. assemblyNotes explains concrete changes in order, connections, reference or expression when combining. studentAdvice relates to the actual student's rendering, naming the source meaning and how to repair omissions/mistranslations; accept valid alternatives and praise accurate choices.
        Explain in Simplified Chinese. Teaching does not introduce new marks or alter scoring. Avoid repeating the same explanation in every field.
        """
    }
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func anchored(_ lessons: [TranslationLesson], input: GradingInput) -> [TranslationLesson] {
        guard input.task == .kaoyanTranslation || input.task == .kaoyan2Translation else { return [] }
        let question = normalize(QuestionText.plain(input.question))
        let underlined = QuestionText.underlinedSegments(input.question)
        var seen = Set<String>()
        return lessons.filter { lesson in
            let source = normalize(lesson.source)
            guard !source.isEmpty, question.contains(source), !lesson.referenceTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !lesson.groups.isEmpty else { return false }
            if input.task == .kaoyanTranslation, !underlined.isEmpty {
                guard let expected = underlined[lesson.number], normalize(expected) == source else { return false }
            }
            var remainder = source[...]
            for group in lesson.groups {
                let span = normalize(group.source)
                guard !span.isEmpty, !group.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let range = remainder.range(of: span),
                      remainder[..<range.lowerBound].allSatisfy({ $0.isWhitespace || $0.isPunctuation }) else { return false }
                remainder = remainder[range.upperBound...]
            }
            guard remainder.allSatisfy({ $0.isWhitespace || $0.isPunctuation }) else { return false }
            return seen.insert(lesson.number).inserted
        }.map { lesson in
            var lesson = lesson
            lesson.groups = lesson.groups.map { group in
                var group = group
                let source = normalize(group.source).lowercased()
                group.vocabulary = group.vocabulary.filter { !$0.word.isEmpty && source.contains(normalize($0.word).lowercased()) }
                return group
            }
            return lesson
        }
    }
}

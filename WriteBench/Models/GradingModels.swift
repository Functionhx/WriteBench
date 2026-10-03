import Foundation

enum Judge: String, CaseIterable, Codable, Identifiable, Sendable {
    case a, b, c
    var id: String { rawValue }
    var title: String { "Judge \(rawValue.uppercased())" }
    var role: String { switch self { case .a: "Rubric examiner"; case .b: "Language reviewer"; case .c: "Independent examiner" } }
}

enum MistakeCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case collocation = "Collocation", articles = "Articles", grammar = "Grammar", wordChoice = "Word choice", chinglish = "Chinglish", register = "Register", taskOmission = "Task omission", coherence = "Coherence", spelling = "Spelling", mistranslation = "Mistranslation", omission = "Omission", addition = "Addition"
    var id: String { rawValue }
}
enum Severity: String, Codable, Sendable { case major, minor }
struct Correction: Codable, Hashable, Identifiable, Sendable {
    var original: String
    var corrected: String
    var category: MistakeCategory
    var severity: Severity
    var explanation: String
    var id: String { "\(category.rawValue)|\(original)|\(corrected)" }
    private enum CodingKeys: String, CodingKey { case original, corrected, category, severity, explanation }
    init(original: String, corrected: String, category: MistakeCategory, severity: Severity, explanation: String) {
        self.original = original; self.corrected = corrected; self.category = category; self.severity = severity; self.explanation = explanation
    }
    /// Model output sometimes uses a category outside the list or a different case; keep the correction rather than reject the review.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        original = try c.decode(String.self, forKey: .original)
        corrected = try c.decode(String.self, forKey: .corrected)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        let rawCategory = (try? c.decode(String.self, forKey: .category)) ?? ""
        category = MistakeCategory.allCases.first { $0.rawValue.caseInsensitiveCompare(rawCategory) == .orderedSame } ?? MistakeCategory.closest(to: rawCategory)
        severity = Severity(rawValue: ((try? c.decode(String.self, forKey: .severity)) ?? "").lowercased()) ?? .minor
    }
}
extension MistakeCategory {
    static func closest(to raw: String) -> MistakeCategory {
        let value = raw.lowercased()
        if value.contains("omi") || value.contains("漏") { return .omission }
        if value.contains("add") || value.contains("增") { return .addition }
        if value.contains("transl") || value.contains("误译") || value.contains("meaning") { return .mistranslation }
        if value.contains("spell") || value.contains("typo") || value.contains("错别") { return .spelling }
        if value.contains("colloc") { return .collocation }
        if value.contains("article") { return .articles }
        if value.contains("cohe") || value.contains("logic") || value.contains("连贯") { return .coherence }
        if value.contains("regist") || value.contains("tone") || value.contains("style") { return .register }
        if value.contains("word") || value.contains("lexi") || value.contains("vocab") || value.contains("用词") { return .wordChoice }
        return .grammar
    }
}
/// Decodes an array element by element and skips elements that do not fit, so one malformed item cannot void a review.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) { elements.append(element) }
            else { _ = try? container.decode(SkippedValue.self) }
        }
        self.elements = elements
    }
    private struct SkippedValue: Decodable { init(from decoder: Decoder) throws {} }
}
/// Numbers sometimes arrive as strings ("1.5") and labels as numbers (46).
enum FlexibleValue {
    static func double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Double {
        if let value = try? c.decode(Double.self, forKey: key) { return value }
        if let text = try? c.decode(String.self, forKey: key), let value = Double(text.trimmingCharacters(in: .whitespaces)) { return value }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Expected a number")
    }
    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> String {
        if let value = try? c.decode(String.self, forKey: key) { return value }
        if let value = try? c.decode(Int.self, forKey: key) { return String(value) }
        if let value = try? c.decode(Double.self, forKey: key) { return value.rounded() == value ? String(Int(value)) : String(value) }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Expected text")
    }
}
struct ExpressionSuggestion: Codable, Hashable, Sendable {
    var phrase: String
    var meaning: String
    var example: String
}
/// One 采分点 (meaning group) inside a numbered translation segment.
struct ScoringPoint: Codable, Hashable, Sendable {
    var source: String
    var earned: Double
    var max: Double
    var note: String
    private enum CodingKeys: String, CodingKey { case source, earned, max, note }
    init(source: String, earned: Double, max: Double, note: String) { self.source = source; self.earned = earned; self.max = max; self.note = note }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? FlexibleValue.string(c, .source)) ?? ""
        earned = try FlexibleValue.double(c, .earned)
        max = try FlexibleValue.double(c, .max)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
}
/// Per-segment marks for English I translation, where each numbered underlined sentence is scored on its own.
struct SegmentScore: Codable, Hashable, Sendable {
    var number: String
    var score: Double
    var maxScore: Double
    var comment: String
    var points: [ScoringPoint] = []
    private enum CodingKeys: String, CodingKey { case number, score, maxScore, comment, points }
    init(number: String, score: Double, maxScore: Double, comment: String, points: [ScoringPoint] = []) {
        self.number = number; self.score = score; self.maxScore = maxScore; self.comment = comment; self.points = points
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try FlexibleValue.string(c, .number).trimmingCharacters(in: CharacterSet(charactersIn: "() （）"))
        score = try FlexibleValue.double(c, .score)
        maxScore = (try? FlexibleValue.double(c, .maxScore)) ?? 2
        comment = (try? c.decode(String.self, forKey: .comment)) ?? ""
        points = (try? c.decodeIfPresent(LossyArray<ScoringPoint>.self, forKey: .points))??.elements ?? []
    }
}
struct JudgeResponse: Codable, Sendable {
    var score: Double
    // Diagnostic dimensions use a common 0–10 scale; overall score uses the exam scale.
    var taskCompletion: Double
    var language: Double
    var coherence: Double
    var register: Double
    var majorErrors: [String]
    var minorErrors: [String]
    var summary: String
    var corrections: [Correction]
    var improvedVersion: String
    var strengths: [String] = []
    var weaknesses: [String] = []
    var improvements: [String] = []
    var expressions: [ExpressionSuggestion] = []
    var segments: [SegmentScore] = []
    var translationLessons: [TranslationLesson] = []
    private enum CodingKeys: String, CodingKey {
        case score, taskCompletion, language, coherence, register, majorErrors, minorErrors, summary, corrections, improvedVersion, strengths, weaknesses, improvements, expressions, segments, translationLessons
    }
}
extension JudgeResponse {
    static func decodeProviderOutput(_ data: Data) throws -> JudgeResponse {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GradingError.invalidResponse("评分必须是 JSON 对象")
        }
        for key in ["strengths", "weaknesses", "improvements"] where !(object[key] is [String]) {
            throw GradingError.invalidResponse("字段 \(key) 缺失或不是文字列表")
        }
        do { return try JSONDecoder().decode(JudgeResponse.self, from: data) }
        catch let error as DecodingError {
            let path: [any CodingKey]
            switch error {
            case .keyNotFound(let key, let context): path = context.codingPath + [key]
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context): path = context.codingPath
            @unknown default: path = []
            }
            throw GradingError.invalidResponse("字段 \(path.map(\.stringValue).joined(separator: ".")) 缺失或类型不符")
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = try FlexibleValue.double(c, .score)
        taskCompletion = try FlexibleValue.double(c, .taskCompletion)
        language = try FlexibleValue.double(c, .language)
        coherence = try FlexibleValue.double(c, .coherence)
        register = try FlexibleValue.double(c, .register)
        majorErrors = try c.decodeIfPresent([String].self, forKey: .majorErrors) ?? []
        minorErrors = try c.decodeIfPresent([String].self, forKey: .minorErrors) ?? []
        summary = try c.decode(String.self, forKey: .summary)
        corrections = try c.decodeIfPresent(LossyArray<Correction>.self, forKey: .corrections)?.elements ?? []
        improvedVersion = try c.decode(String.self, forKey: .improvedVersion)
        // Existing saved reports predate these fields and remain readable.
        strengths = try c.decodeIfPresent([String].self, forKey: .strengths) ?? []
        weaknesses = try c.decodeIfPresent([String].self, forKey: .weaknesses) ?? []
        improvements = try c.decodeIfPresent([String].self, forKey: .improvements) ?? []
        expressions = (try? c.decodeIfPresent(LossyArray<ExpressionSuggestion>.self, forKey: .expressions))??.elements ?? []
        segments = (try? c.decodeIfPresent(LossyArray<SegmentScore>.self, forKey: .segments))??.elements ?? []
        translationLessons = (try? c.decodeIfPresent(LossyArray<TranslationLesson>.self, forKey: .translationLessons))??.elements ?? []
    }
}
struct TokenUsage: Codable, Hashable, Sendable {
    var input: Int
    var cachedInput: Int
    var output: Int
    var reasoning: Int?
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(input: lhs.input + rhs.input, cachedInput: lhs.cachedInput + rhs.cachedInput, output: lhs.output + rhs.output,
             reasoning: lhs.reasoning.map { $0 + (rhs.reasoning ?? 0) } ?? rhs.reasoning)
    }
}
struct ReviewerResult: Codable, Identifiable, Sendable {
    var judge: Judge
    var response: JudgeResponse
    var model: String
    var timestamp: Date
    var provider: GradingProvider? = nil
    var reasoningEffort: String? = nil
    var usage: TokenUsage? = nil
    /// Seconds from request to validated result.
    var duration: Double? = nil
    var id: String { judge.id }
}
enum Confidence: String, Codable, Sendable {
    case high = "High", medium = "Medium", low = "Low", single = "Single"
    var title: String { self == .single ? "快速单评" : "\(rawValue) confidence" }
    static func label(_ raw: String) -> String { raw == Confidence.single.rawValue ? "单评" : raw }
}
/// Full review is the three-judge median. Quick review asks one judge, for drafts.
enum GradingMode: String, Codable, Sendable {
    case full, quick
}
struct GradingReport: Codable, Sendable {
    var reviewers: [ReviewerResult]
    var finalScore: Double
    var spread: Double
    var confidence: Confidence
    var rubricVersion: String
    var promptVersion: String
    var isDemo: Bool
    var timestamp: Date
    /// nil for reports saved before quick review existed; those are full reviews.
    var mode: GradingMode? = nil
    var duration: Double? = nil
    var gradingMode: GradingMode { mode ?? .full }
    var usage: TokenUsage? {
        let values = reviewers.compactMap(\.usage) + [synthesisUsage].compactMap { $0 }
        return values.isEmpty ? nil : values.dropFirst().reduce(values[0], +)
    }
    /// One consolidated report written by the chief examiner after the three independent reviews.
    /// Scores inside it are the app's own aggregates; only the wording is synthesized.
    var synthesis: JudgeResponse? = nil
    var synthesisModel: String? = nil
    var synthesisProvider: GradingProvider? = nil
    var synthesisUsage: TokenUsage? = nil
    /// Why the consolidated report is missing, when it was attempted and failed.
    var synthesisNote: String? = nil

    var corrections: [Correction] { (synthesis?.corrections ?? mergedCorrections).sorted { $0.severity == .major && $1.severity != .major } }
    var mergedCorrections: [Correction] {
        var seen = Set<String>()
        return reviewers.flatMap(\.response.corrections).filter {
            seen.insert("\($0.category.rawValue)|\($0.original.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))").inserted
        }
    }
    /// The reviewer whose overall score is the median.
    var medianReviewer: ReviewerResult? { reviewers.min { abs($0.response.score - finalScore) < abs($1.response.score - finalScore) } }
    /// Final per-sentence marks: the median of the reviewers' marks for each numbered segment,
    /// explained by a reviewer who gave exactly that mark.
    var medianSegments: [SegmentScore] {
        guard let first = reviewers.first(where: { !$0.response.segments.isEmpty }) else { return [] }
        return first.response.segments.map { template in
            let marks = reviewers.compactMap { reviewer in reviewer.response.segments.first { $0.number == template.number } }
            let sorted = marks.map(\.score).sorted()
            let median = sorted.isEmpty ? template.score : sorted[(sorted.count - 1) / 2]
            var chosen = marks.first { $0.score == median } ?? template
            chosen.score = median
            return chosen
        }
    }
    /// Per-sentence marks shown to the student, with each reviewer's own mark kept for reference.
    var segmentScores: [(segment: SegmentScore, byJudge: [(judge: Judge, score: Double)])] {
        let segments = synthesis.map(\.segments).flatMap { $0.isEmpty ? nil : $0 } ?? medianSegments
        return segments.map { segment in
            (segment, reviewers.compactMap { reviewer in reviewer.response.segments.first { $0.number == segment.number }.map { (reviewer.judge, $0.score) } })
        }
    }
    var translationLessons: [TranslationLesson] {
        if let lessons = synthesis?.translationLessons, !lessons.isEmpty { return lessons }
        // One coherent teacher's explanation, rather than concatenating three versions.
        if let reviewer = medianReviewer, !reviewer.response.translationLessons.isEmpty { return reviewer.response.translationLessons }
        return reviewers.first { !$0.response.translationLessons.isEmpty }?.response.translationLessons ?? []
    }
    private var revisionSource: ReviewerResult? { reviewers.first(where: { $0.judge == .b }) ?? reviewers.first }
    var improvedVersion: String {
        if let text = synthesis?.improvedVersion, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        return revisionSource?.response.improvedVersion ?? ""
    }
    /// Expressions come from the version whose improved answer is shown, so each one appears in context.
    var expressions: [ExpressionSuggestion] {
        var seen = Set<String>()
        return (synthesis?.expressions ?? revisionSource?.response.expressions ?? []).filter {
            !$0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.phrase.lowercased()).inserted
        }
    }
    var conclusion: String { synthesis?.summary ?? medianReviewer?.response.summary ?? "" }
    var strengths: [String] { synthesis?.strengths ?? uniqueFeedback(reviewers.flatMap(\.response.strengths)) }
    var weaknesses: [String] { synthesis?.weaknesses ?? uniqueFeedback(reviewers.flatMap { $0.response.weaknesses.isEmpty ? $0.response.majorErrors : $0.response.weaknesses }) }
    var improvements: [String] { synthesis?.improvements ?? uniqueFeedback(reviewers.flatMap(\.response.improvements)) }
    private func uniqueFeedback(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    func dimension(_ keyPath: KeyPath<JudgeResponse, Double>) -> Double {
        let values = reviewers.map { $0.response[keyPath: keyPath] }.sorted()
        return values.isEmpty ? 0 : values[values.count / 2]
    }
}
struct GradingInput: Sendable {
    var task: WritingTask
    var question: String
    var essay: String
    var rubric: String
}

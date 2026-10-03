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
        number = try c.decode(String.self, forKey: .number); score = try c.decode(Double.self, forKey: .score)
        maxScore = try c.decode(Double.self, forKey: .maxScore); comment = try c.decode(String.self, forKey: .comment)
        points = try c.decodeIfPresent([ScoringPoint].self, forKey: .points) ?? []
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
    private enum CodingKeys: String, CodingKey {
        case score, taskCompletion, language, coherence, register, majorErrors, minorErrors, summary, corrections, improvedVersion, strengths, weaknesses, improvements, expressions, segments
    }
}
extension JudgeResponse {
    static func decodeProviderOutput(_ data: Data) throws -> JudgeResponse {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              ["strengths", "weaknesses", "improvements"].allSatisfy({ object[$0] is [String] }) else {
            throw GradingError.invalidResponse("缺少优点、不足或改进建议")
        }
        return try JSONDecoder().decode(JudgeResponse.self, from: data)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = try c.decode(Double.self, forKey: .score)
        taskCompletion = try c.decode(Double.self, forKey: .taskCompletion)
        language = try c.decode(Double.self, forKey: .language)
        coherence = try c.decode(Double.self, forKey: .coherence)
        register = try c.decode(Double.self, forKey: .register)
        majorErrors = try c.decode([String].self, forKey: .majorErrors)
        minorErrors = try c.decode([String].self, forKey: .minorErrors)
        summary = try c.decode(String.self, forKey: .summary)
        corrections = try c.decode([Correction].self, forKey: .corrections)
        improvedVersion = try c.decode(String.self, forKey: .improvedVersion)
        // Existing saved reports predate these fields and remain readable.
        strengths = try c.decodeIfPresent([String].self, forKey: .strengths) ?? []
        weaknesses = try c.decodeIfPresent([String].self, forKey: .weaknesses) ?? []
        improvements = try c.decodeIfPresent([String].self, forKey: .improvements) ?? []
        expressions = try c.decodeIfPresent([ExpressionSuggestion].self, forKey: .expressions) ?? []
        segments = try c.decodeIfPresent([SegmentScore].self, forKey: .segments) ?? []
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
        let values = reviewers.compactMap(\.usage)
        return values.isEmpty ? nil : values.dropFirst().reduce(values[0], +)
    }
    var corrections: [Correction] {
        var seen = Set<String>()
        return reviewers.flatMap(\.response.corrections).filter {
            seen.insert("\($0.category.rawValue)|\($0.original.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))").inserted
        }.sorted { $0.severity == .major && $1.severity != .major }
    }
    /// The reviewer whose overall score is the median: its per-segment marks add up to the reported total.
    var medianReviewer: ReviewerResult? { reviewers.min { abs($0.response.score - finalScore) < abs($1.response.score - finalScore) } }
    /// Per-sentence marks from the median reviewer, with every reviewer's mark for the same sentence.
    var segmentScores: [(segment: SegmentScore, byJudge: [(judge: Judge, score: Double)])] {
        guard let source = medianReviewer, !source.response.segments.isEmpty else { return [] }
        return source.response.segments.map { segment in
            (segment, reviewers.compactMap { reviewer in reviewer.response.segments.first { $0.number == segment.number }.map { (reviewer.judge, $0.score) } })
        }
    }
    private var revisionSource: ReviewerResult? { reviewers.first(where: { $0.judge == .b }) ?? reviewers.first }
    var improvedVersion: String { revisionSource?.response.improvedVersion ?? "" }
    /// Expressions come from the reviewer whose improved version is shown, so each one appears in context.
    var expressions: [ExpressionSuggestion] {
        var seen = Set<String>()
        return (revisionSource?.response.expressions ?? []).filter {
            !$0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.phrase.lowercased()).inserted
        }
    }
    var conclusion: String { reviewers.min { abs($0.response.score - finalScore) < abs($1.response.score - finalScore) }?.response.summary ?? "" }
    var strengths: [String] { uniqueFeedback(reviewers.flatMap(\.response.strengths)) }
    var weaknesses: [String] { uniqueFeedback(reviewers.flatMap { $0.response.weaknesses.isEmpty ? $0.response.majorErrors : $0.response.weaknesses }) }
    var improvements: [String] { uniqueFeedback(reviewers.flatMap(\.response.improvements)) }
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

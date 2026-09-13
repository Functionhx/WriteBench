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
    private enum CodingKeys: String, CodingKey {
        case score, taskCompletion, language, coherence, register, majorErrors, minorErrors, summary, corrections, improvedVersion, strengths, weaknesses, improvements
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
    }
}
struct ReviewerResult: Codable, Identifiable, Sendable {
    var judge: Judge
    var response: JudgeResponse
    var model: String
    var timestamp: Date
    var provider: GradingProvider? = nil
    var reasoningEffort: String? = nil
    var id: String { judge.id }
}
enum Confidence: String, Codable, Sendable {
    case high = "High", medium = "Medium", low = "Low"
    var title: String { "\(rawValue) confidence" }
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
    var corrections: [Correction] {
        var seen = Set<String>()
        return reviewers.flatMap(\.response.corrections).filter {
            seen.insert("\($0.category.rawValue)|\($0.original.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))").inserted
        }.sorted { $0.severity == .major && $1.severity != .major }
    }
    var improvedVersion: String { reviewers.first(where: { $0.judge == .b })?.response.improvedVersion ?? "" }
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

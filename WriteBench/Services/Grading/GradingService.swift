import Foundation

protocol EssayGradingService: Sendable {
    func grade(_ input: GradingInput, judge: Judge) async throws -> ReviewerResult
}
protocol ChiefExaminerService: Sendable {
    func arbitrate(_ input: GradingInput, reviewers: [ReviewerResult]) async throws -> JudgeResponse
}

enum GradingError: LocalizedError {
    case invalidResponse(String), missingKey, missingRubric, http(Int), incomplete
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail): "评分结果格式无效：\(detail)。请重试；本次未保存不完整评分。"
        case .missingKey: "尚未配置 DeepSeek API Key。请前往设置填入 API Key 后再评卷。"
        case .missingRubric: "找不到本题型的评分标准，请重新安装完整的应用。"
        case .http(let status): status == 401 ? "API Key 验证失败，请在 Settings 中更新。" : status == 402 ? "DeepSeek 余额不足，请检查账户。" : status == 429 ? "DeepSeek 请求过于频繁，请稍后重试。" : "DeepSeek 请求失败（HTTP \(status)），请稍后重试。"
        case .incomplete: "三位评审未全部完成。请重试；不会使用部分评分计算总分。"
        }
    }
}

enum ScoreAggregator {
    static func aggregate(_ results: [ReviewerResult], task: WritingTask, isDemo: Bool) throws -> GradingReport {
        guard results.count == 3, Set(results.map(\.judge)) == Set(Judge.allCases) else { throw GradingError.incomplete }
        for result in results { try validate(result.response, task: task) }
        let scores = results.map(\.response.score).sorted()
        let spread = scores[2] - scores[0]
        return GradingReport(reviewers: results.sorted { $0.judge.rawValue < $1.judge.rawValue }, finalScore: scores[1], spread: spread, confidence: spread <= 1 ? .high : spread <= 2 ? .medium : .low, rubricVersion: RubricLoader.version, promptVersion: GraderPrompt.version, isDemo: isDemo, timestamp: Date())
    }
    static func validate(_ response: JudgeResponse, task: WritingTask) throws {
        guard response.score.isFinite, (0...task.maxScore).contains(response.score) else { throw GradingError.invalidResponse("分数超出题型范围") }
        let values = [response.taskCompletion, response.language, response.coherence, response.register]
        guard values.allSatisfy({ $0.isFinite && (0...10).contains($0) }), !response.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GradingError.invalidResponse("维度分数或评语缺失") }
        guard response.corrections.allSatisfy({ !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.explanation.isEmpty }) else { throw GradingError.invalidResponse("修改建议缺失必要字段") }
        guard !response.improvedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GradingError.invalidResponse("缺少改进版本") }
    }
}

struct GradingCoordinator: Sendable {
    let service: any EssayGradingService
    // Reserved for explicit opt-in arbitration. v1 never makes a hidden fourth paid call.
    var chiefExaminer: (any ChiefExaminerService)? = nil
    func grade(_ input: GradingInput, isDemo: Bool) async throws -> GradingReport {
        async let a = service.grade(input, judge: .a)
        async let b = service.grade(input, judge: .b)
        async let c = service.grade(input, judge: .c)
        let results = try await [a, b, c]
        try Task.checkCancellation()
        return try ScoreAggregator.aggregate(results, task: input.task, isDemo: isDemo)
    }
}

enum RubricLoader {
    static let version = "2026.09-v1"
    static func load(_ task: WritingTask) throws -> String {
        guard let url = Bundle.main.url(forResource: task.rubricFile, withExtension: "md") else { throw GradingError.missingRubric }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
enum GraderPrompt { static let version = "1.0.0" }

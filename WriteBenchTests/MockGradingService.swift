import Foundation
@testable import WriteBench

// Test fixture only. Never included in the application target.
struct MockGradingService: EssayGradingService {
    func grade(_ input: GradingInput, judge: Judge) async throws -> ReviewerResult {
        try await Task.sleep(for: .milliseconds(judge == .a ? 700 : judge == .b ? 950 : 1150))
        try Task.checkCancellation()
        let demoScore = (input.task.maxScore * (judge == .b ? 0.75 : 0.8) * 2).rounded() / 2
        let pairs: [(String, String, MistakeCategory, String)] = [
            ("look forward to hear", "look forward to hearing", .grammar, "“Look forward to”中的 to 是介词，后面接动名词。"),
            ("I very like", "I really like", .chinglish, "用 really 修饰动词 like；very 不能直接修饰该动词。"),
            ("do a decision", "make a decision", .collocation, "Decision 与 make 搭配。")
        ]
        let corrections = pairs.filter { input.essay.contains($0.0) }.map { Correction(original: $0.0, corrected: $0.1, category: $0.2, severity: .minor, explanation: $0.3) }
        var improved = input.essay
        corrections.forEach { improved = improved.replacingOccurrences(of: $0.original, with: $0.corrected) }
        let response = JudgeResponse(score: demoScore, taskCompletion: 8, language: 7.5, coherence: 8, register: 8, majorErrors: [], minorErrors: corrections.map(\.explanation), summary: "演示评阅 · 此分数是固定界面示例，并非对这篇作文的真实评估。连接 DeepSeek 后，\(judge.role) 将独立阅读原题与全文，按对应标准给出具体反馈。", corrections: corrections, improvedVersion: improved)
        return ReviewerResult(judge: judge, response: response, model: "Local demo · no API request", timestamp: Date())
    }
}


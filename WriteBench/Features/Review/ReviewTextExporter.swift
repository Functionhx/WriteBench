import Foundation

/// Copies the assessment; essay text has its own existing Copy action.
@MainActor enum ReviewTextExporter {
    static func text(for session: EssaySession) -> String? {
        guard let report = session.report else { return nil }
        var sections = [
            "WriteBench · \(session.task.fullTitle)\n\(session.date.formatted(date: .abbreviated, time: .shortened))",
            "\(report.isDemo ? "演示评分 · " : "")最终得分：\(report.finalScore.scoreText) / \(Int(session.task.maxScore))\n置信度：\(report.confidence.rawValue)\n评审分差：\(report.spread.scoreText)",
            "评阅结论（中位分评审）\n\(report.conclusion)",
            feedback("写得好的地方", report.strengths),
            feedback("不足的地方", report.weaknesses),
            feedback("下一稿怎么改", report.improvements),
            "评分维度（诊断分 / 10）\n\(session.task.isTranslation ? "译义与完整性" : "任务完成度")：\(report.dimension(\.taskCompletion).scoreText)\n语言：\(report.dimension(\.language).scoreText)\n连贯性：\(report.dimension(\.coherence).scoreText)\n语域：\(report.dimension(\.register).scoreText)"
        ]
        let reviewers = report.reviewers.map { result in
            var lines = ["\(result.judge.title) · \(result.judge.role) · \(result.response.score.scoreText) / \(Int(session.task.maxScore))",
                         "\(result.provider?.title ?? result.model) · \(result.model)", result.response.summary]
            if !result.response.majorErrors.isEmpty { lines.append(feedback("主要问题", result.response.majorErrors)) }
            if !result.response.minorErrors.isEmpty { lines.append(feedback("次要问题", result.response.minorErrors)) }
            return lines.joined(separator: "\n")
        }
        sections.append("三位评审的独立意见\n\n" + reviewers.joined(separator: "\n\n"))
        let corrections = report.corrections.enumerated().map { index, correction in
            "\(index + 1). \(correction.category.rawValue) · \(correction.severity == .major ? "主要" : "次要")\n原句：\(correction.original)\n修改：\(correction.corrected)\n说明：\(correction.explanation)"
        }
        sections.append("逐句修改\n" + (corrections.isEmpty ? "未标注逐句修改。" : corrections.joined(separator: "\n\n")))
        return sections.joined(separator: "\n\n")
    }
    private static func feedback(_ title: String, _ items: [String]) -> String {
        title + "\n" + (items.isEmpty ? "本次评阅未单列此项。" : items.map { "• " + $0 }.joined(separator: "\n"))
    }
}

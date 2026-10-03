import Foundation

/// Copies the assessment; essay text has its own existing Copy action.
@MainActor enum ReviewTextExporter {
    static func text(for session: EssaySession) -> String? {
        guard let report = session.report else { return nil }
        var sections = [
            "WriteBench · \(session.task.fullTitle)\n\(session.date.formatted(date: .abbreviated, time: .shortened))",
            "\(report.isDemo ? "演示评分 · " : "")最终得分：\(report.finalScore.scoreText) / \(Int(session.task.maxScore))\n" + (report.gradingMode == .quick ? "评阅方式：快速单评（一位评审）" : "置信度：\(report.confidence.rawValue)\n评审分差：\(report.spread.scoreText)"),
            "评阅结论\n\(report.conclusion)",
            feedback("写得好的地方", report.strengths),
            feedback("不足的地方", report.weaknesses),
            feedback("下一稿怎么改", report.improvements),
            "评分维度（诊断分 / 10）\n\(session.task.isTranslation ? "译义与完整性" : "任务完成度")：\(report.dimension(\.taskCompletion).scoreText)\n语言：\(report.dimension(\.language).scoreText)\n连贯性：\(report.dimension(\.coherence).scoreText)\n语域：\(report.dimension(\.register).scoreText)"
        ]
        if !report.segmentScores.isEmpty {
            sections.append("逐句得分\n" + report.segmentScores.map { item in
                (["(\(item.segment.number)) \(item.segment.score.scoreText) / \(item.segment.maxScore.scoreText)　\(item.segment.comment)"]
                 + item.segment.points.map { "  · \($0.source)：\($0.earned.scoreText) / \($0.max.scoreText)\($0.note.isEmpty ? "" : "，" + $0.note)" }).joined(separator: "\n")
            }.joined(separator: "\n"))
        }
        if report.reviewers.count > 1 {
            sections.append("三位评审独立评分：" + report.reviewers.map { "\($0.judge.title) \($0.response.score.scoreText)" }.joined(separator: "，") + "（取中位数）")
        }
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

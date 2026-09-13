import Foundation
import Observation

struct GradingSubmission: Sendable {
    let input: GradingInput
    let duration: TimeInterval
    let inputMode: InputMode
    let questionImage: Data?
    let sourceImages: [Data]
    var parentSessionID: UUID? = nil
    var countText: String {
        input.task.targetLanguage == "Simplified Chinese" ? "\(input.essay.count) 字符" : "\(WordCounter.count(input.essay)) words"
    }
}

enum GradingPhase {
    case connecting, reviewing, saving, cancelling, completed, failed, cancelled
    var isRunning: Bool { [.connecting, .reviewing, .saving, .cancelling].contains(self) }
    var title: String {
        switch self {
        case .connecting: "正在检查评审连接"
        case .reviewing: "正在后台评阅"
        case .saving: "正在保存评阅"
        case .cancelling: "正在取消评阅"
        case .completed: "评阅完成"
        case .failed: "评阅未完成"
        case .cancelled: "已取消评阅"
        }
    }
}
enum JudgeProgress: String { case waiting = "等待连接", reviewing = "正在评阅", completed = "已完成", failed = "失败", cancelled = "已取消" }
enum GradingProgressEvent: Sendable {
    case started(Judge)
    case preview(Judge, String)
    case completed(ReviewerResult)
    case failed(Judge, String)
}

@MainActor @Observable final class BackgroundGradingJob: Identifiable {
    let id = UUID()
    let submission: GradingSubmission
    let configuration: GradingConfiguration?
    let startedAt = Date()
    var finishedAt: Date?
    var phase: GradingPhase
    var judges = Dictionary(uniqueKeysWithValues: Judge.allCases.map { ($0, JudgeProgress.waiting) })
    var previews: [Judge: String] = [:]
    var results: [Judge: ReviewerResult] = [:]
    var detail: String?
    var session: EssaySession?
    var completedCount: Int { judges.values.filter { $0 == .completed }.count }

    init(submission: GradingSubmission, configuration: GradingConfiguration?, connecting: Bool) {
        self.submission = submission; self.configuration = configuration
        phase = connecting ? .connecting : .reviewing
    }
    func receive(_ event: GradingProgressEvent) {
        guard phase == .reviewing else { return }
        switch event {
        case .started(let judge): judges[judge] = .reviewing
        case .preview(let judge, let text): previews[judge] = text
        case .completed(let result):
            results[result.judge] = result; previews[result.judge] = result.response.summary
            judges[result.judge] = .completed
        case .failed(let judge, let message): judges[judge] = .failed; detail = message
        }
    }
    func finish(_ phase: GradingPhase, detail: String? = nil) {
        self.phase = phase; self.detail = detail; finishedAt = Date()
        for judge in Judge.allCases where judges[judge] == .waiting || judges[judge] == .reviewing { judges[judge] = .cancelled }
    }
    func elapsedText(at date: Date) -> String {
        let seconds = max(0, Int((finishedAt ?? date).timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

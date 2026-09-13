import Foundation
import SwiftData
import Testing
@testable import WriteBench

private func backgroundResponse(_ essay: String) -> JudgeResponse {
    JudgeResponse(score: 8, taskCompletion: 8, language: 8, coherence: 8, register: 8, majorErrors: [], minorErrors: [],
        summary: "任务完成，注意时态一致。", corrections: [], improvedVersion: essay,
        strengths: ["交代了活动主题。"], weaknesses: ["时态不一致。"], improvements: ["逐句核对动词时态。"])
}
private enum BackgroundTestError: Error { case timeout, reviewerFailed }
private actor GatedGrader: StreamingEssayGradingService {
    var inputs: [Judge: GradingInput] = [:]
    var waiting: [Judge: CheckedContinuation<Void, any Error>] = [:]
    var cancellations: Set<Judge> = []
    func grade(_ input: GradingInput, judge: Judge, onPreview: @escaping @Sendable (String) async -> Void) async throws -> ReviewerResult {
        inputs[judge] = input
        await onPreview("已收到题目，正在核对任务要求。")
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiting[judge] = continuation }
            }
        } onCancel: { Task { await self.cancel(judge) } }
        return ReviewerResult(judge: judge, response: backgroundResponse(input.essay), model: "test-only-gated", timestamp: Date())
    }
    func finish(_ judge: Judge, fail: Bool = false) {
        let continuation = waiting.removeValue(forKey: judge)
        if fail { continuation?.resume(throwing: BackgroundTestError.reviewerFailed) }
        else { continuation?.resume() }
    }
    private func cancel(_ judge: Judge) { cancellations.insert(judge); waiting.removeValue(forKey: judge)?.resume(throwing: CancellationError()) }
}
@MainActor private func eventually(_ condition: @MainActor () async -> Bool) async throws {
    for _ in 0..<250 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw BackgroundTestError.timeout
}
@MainActor private func backgroundStore() throws -> (WritingStore, ModelContext) {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container), store = WritingStore()
    store.attach(context); store.question = "Invite Alex to a lecture."; store.essay = "Dear Alex, Please join the lecture. Yours, Li Ming."
    store.elapsed = 125; store.inputMode = .handwritten; store.sourceImages = [Data([1, 2, 3])]
    store.questionImage = Data([4, 5, 6]); store.startAnswering()
    return (store, context)
}

@Test @MainActor func backgroundProgressUsesRealCompletionsAndOriginalSnapshot() async throws {
    let (store, context) = try backgroundStore(), grader = GatedGrader()
    let original = store.essay
    var completions = 0
    store.submit(service: grader, isDemo: true) { _ in completions += 1 }
    let running = try #require(store.gradingTask), job = try #require(store.gradingJob)
    defer { running.cancel() }
    #expect(store.stage == .preparation && store.isGrading && !store.timerRunning)
    store.select(.cet6Translation); store.question = "另一道题目"; store.essay = "A new answer."; store.elapsed = 0
    #expect(store.startAnswering())
    try await eventually { await grader.waiting.count == 3 }
    #expect(job.completedCount == 0)
    #expect(job.previews.count == 3)
    #expect(await grader.inputs.values.allSatisfy { $0.essay == original && $0.task == .kaoyanSmall })
    // A second submission must not replace or duplicate the running paid request.
    store.submitConfigured(configuration: .init(), loadKey: { Issue.record("Busy submission must not access credentials"); return "" })
    #expect(store.gradingJob?.id == job.id)
    await grader.finish(.b)
    try await eventually { job.completedCount == 1 }
    #expect(job.judges[.b] == .completed && job.judges[.a] == .reviewing)
    #expect(job.session == nil && completions == 0)
    await grader.finish(.a); await grader.finish(.c); await running.value
    #expect(job.phase == .completed && job.completedCount == 3)
    #expect(completions == 1 && !store.isGrading)
    #expect(store.stage == .answering && store.timerRunning && store.essay == "A new answer.")
    let saved = try #require(context.fetch(FetchDescriptor<EssaySession>()).first)
    #expect(saved.task == .kaoyanSmall && saved.originalEssay == original)
    #expect(saved.question == "Invite Alex to a lecture.")
    #expect(saved.inputMode == "handwritten" && saved.writingDuration >= 125)
    #expect(saved.questionImage == Data([4, 5, 6]))
    #expect(saved.report?.strengths == ["交代了活动主题。"])
    #expect(job.submission.countText == "\(WordCounter.count(original)) words")
    #expect(try context.fetchCount(FetchDescriptor<EssaySession>()) == 1)
}

@Test @MainActor func cancellingBackgroundReviewKeepsCurrentDraftAndDoesNotSavePartialScores() async throws {
    let (store, context) = try backgroundStore(), grader = GatedGrader()
    store.submit(service: grader, isDemo: true) { _ in Issue.record("Cancelled review must not complete") }
    let running = try #require(store.gradingTask), job = try #require(store.gradingJob)
    defer { running.cancel() }
    try await eventually { await grader.waiting.count == 3 }
    await grader.finish(.a); try await eventually { job.completedCount == 1 }
    #expect(store.startAnswering()); store.essay = "My continuing draft."
    store.cancelGrading()
    #expect(job.phase == .cancelling)
    await running.value
    #expect(job.phase == .cancelled && !store.isGrading && job.session == nil)
    #expect(store.stage == .answering && store.timerRunning && store.essay == "My continuing draft.")
    #expect(await grader.waiting.isEmpty)
    #expect(await grader.cancellations.contains(.b))
    #expect(try context.fetchCount(FetchDescriptor<EssaySession>()) == 0)
}

@Test @MainActor func backgroundFailureNamesJudgeAndCancelsRemainingRequests() async throws {
    let (store, context) = try backgroundStore(), grader = GatedGrader()
    store.submit(service: grader, isDemo: true)
    let running = try #require(store.gradingTask), job = try #require(store.gradingJob)
    defer { running.cancel() }
    try await eventually { await grader.waiting.count == 3 }
    await grader.finish(.c, fail: true); await running.value
    #expect(job.phase == .failed && job.judges[.c] == .failed)
    #expect(job.detail?.contains("Judge C") == true)
    #expect(job.completedCount == 0 && job.session == nil)
    #expect(await grader.waiting.isEmpty)
    #expect(store.stage == .preparation && !store.timerRunning)
    #expect(job.submission.input.essay == store.essay)
    #expect(try context.fetchCount(FetchDescriptor<EssaySession>()) == 0)
}

@Test @MainActor func codexConnectionFailureDoesNotRestoreOrOverwriteAnotherWritingSession() async throws {
    let (store, context) = try backgroundStore()
    let configuration = GradingConfiguration(a: .codex, b: .codex, c: .codex, codexPath: "/writebench-test-no-such-codex")
    store.submitConfigured(configuration: configuration)
    let running = try #require(store.gradingTask), job = try #require(store.gradingJob)
    #expect(job.phase == .connecting && !store.isInSession)
    store.select(.ieltsTask2); store.essay = "An unrelated draft."; store.startAnswering()
    await running.value
    #expect(job.phase == .failed && job.detail?.contains("Codex") == true)
    #expect(store.task == .ieltsTask2 && store.essay == "An unrelated draft.")
    #expect(store.stage == .answering && store.timerRunning)
    #expect(try context.fetchCount(FetchDescriptor<EssaySession>()) == 0)
}

@Test @MainActor func backgroundRewriteSavesTheSubmittedParentWhenAnotherRewriteStarts() async throws {
    let (store, context) = try backgroundStore(), grader = GatedGrader()
    #expect(store.leaveAnswering())
    let report = try ScoreAggregator.aggregate(Judge.allCases.map {
        ReviewerResult(judge: $0, response: backgroundResponse(store.essay), model: "test", timestamp: Date())
    }, task: .kaoyanSmall, isDemo: false)
    let source = try EssaySession(task: .kaoyanSmall, question: store.question, essay: store.essay, duration: 10, inputMode: .typed, report: report)
    let other = try EssaySession(task: .kaoyanSmall, question: store.question, essay: "Another original answer.", duration: 20, inputMode: .typed, report: report)
    context.insert(source); context.insert(other); try context.save()
    store.beginRewrite(source); store.essay = "The submitted revision."
    store.submit(service: grader, isDemo: false)
    let running = try #require(store.gradingTask), job = try #require(store.gradingJob)
    defer { running.cancel() }
    store.beginRewrite(other); store.essay = "A different rewrite in progress."
    try await eventually { await grader.waiting.count == 3 }
    for judge in Judge.allCases { await grader.finish(judge) }
    await running.value
    let saved = try #require(job.session)
    #expect(saved.parentSessionID == source.id)
    #expect(saved.originalEssay == "The submitted revision.")
    #expect(store.essay == "A different rewrite in progress." && store.isInSession)
    #expect(source.originalEssay != saved.originalEssay)
    #expect(EssayHistoryGroup.make(from: try context.fetch(FetchDescriptor<EssaySession>())).count == 1)
}

import Foundation
import Testing
import SwiftData
import AppKit
@testable import WriteBench

private func response(_ score: Double = 8, corrections: [Correction] = []) -> JudgeResponse {
    JudgeResponse(score: score, taskCompletion: 8, language: 7.5, coherence: 8, register: 8, majorErrors: [], minorErrors: [], summary: "A complete test review.", corrections: corrections, improvedVersion: "Dear Alex, I look forward to hearing from you. Yours, Li Ming.")
}
private func results(_ scores: [Double]) -> [ReviewerResult] {
    zip(Judge.allCases, scores).map { ReviewerResult(judge: $0.0, response: response($0.1), model: "test", timestamp: Date()) }
}
private func input() -> GradingInput {
    GradingInput(task: .kaoyanSmall, question: "Invite Alex to a university lecture. Include time, place and topic.", essay: "Dear Alex, I look forward to hear from you. Yours, Li Ming.", rubric: "Test rubric: 0–10.")
}

@Test func medianAndConfidence() throws {
    let report = try ScoreAggregator.aggregate(results([8, 7.5, 8]), task: .kaoyanSmall, isDemo: false)
    #expect(report.finalScore == 8)
    #expect(report.spread == 0.5)
    #expect(report.confidence == .high)
    #expect(try ScoreAggregator.aggregate(results([6, 7, 8]), task: .kaoyanSmall, isDemo: false).confidence == .medium)
    #expect(try ScoreAggregator.aggregate(results([5, 7, 8]), task: .kaoyanSmall, isDemo: false).confidence == .low)
    #expect(try ScoreAggregator.aggregate(results([7, 8, 8]), task: .kaoyanSmall, isDemo: false).confidence == .high)
}
@Test func rejectIncompleteDuplicateAndOutOfRangeReviewers() throws {
    #expect(throws: (any Error).self) { try ScoreAggregator.aggregate(Array(results([8, 7, 8]).prefix(2)), task: .kaoyanSmall, isDemo: false) }
    var duplicate = results([8, 7, 8]); duplicate[2].judge = .a
    #expect(throws: (any Error).self) { try ScoreAggregator.aggregate(duplicate, task: .kaoyanSmall, isDemo: false) }
    #expect(throws: (any Error).self) { try ScoreAggregator.aggregate(results([8, 11, 8]), task: .kaoyanSmall, isDemo: false) }
    var bad = response(); bad.language = -1
    #expect(throws: (any Error).self) { try ScoreAggregator.validate(bad, task: .kaoyanSmall) }
    bad = response(); bad.score = .nan
    #expect(throws: (any Error).self) { try ScoreAggregator.validate(bad, task: .kaoyanSmall) }
}
@Test func wordCountingAndScales() {
    #expect(WordCounter.count("I'm writing a well-known writer’s story. 2026!") == 7)
    #expect(WordCounter.count("\n  \t") == 0)
    #expect(WordCounter.count("Hello—world. 你好") == 2)
    #expect(WritingTask.kaoyanLarge.maxScore == 20)
    #expect(WritingTask.cet6Writing.maxScore == 15)
    #expect(WritingTask.ieltsTask2.maxScore == 9)
}
@Test func duplicateCorrectionsCountOncePerEssay() throws {
    let correction = Correction(original: "look forward to hear", corrected: "look forward to hearing", category: .grammar, severity: .minor, explanation: "Use a gerund.")
    var reviewers = results([8, 7.5, 8])
    reviewers[0].response.corrections = [correction]
    reviewers[1].response.corrections = [correction]
    let report = try ScoreAggregator.aggregate(reviewers, task: .kaoyanSmall, isDemo: false)
    #expect(report.corrections.count == 1)
    let decoded = try JSONDecoder().decode(GradingReport.self, from: JSONEncoder().encode(report))
    #expect(decoded.finalScore == report.finalScore)
    #expect(decoded.corrections.first?.original == correction.original)
}

private actor RecordingGrader: EssayGradingService {
    var active = 0
    var maxActive = 0
    var evidence: [String] = []
    func grade(_ input: GradingInput, judge: Judge) async throws -> ReviewerResult {
        active += 1; maxActive = max(maxActive, active); evidence.append(input.essay)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(60))
        return ReviewerResult(judge: judge, response: response(judge == .b ? 7.5 : 8), model: "recording", timestamp: Date())
    }
}
@Test func gradersRunInParallelWithIdenticalOriginalEvidence() async throws {
    let grader = RecordingGrader()
    let report = try await GradingCoordinator(service: grader).grade(input(), isDemo: false)
    #expect(report.reviewers.count == 3)
    #expect(await grader.maxActive == 3)
    #expect(await grader.evidence == Array(repeating: input().essay, count: 3))
}
@Test func cancellationDoesNotProduceAPartialReport() async throws {
    let task = Task { try await GradingCoordinator(service: RecordingGrader()).grade(input(), isDemo: false) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}

private actor FixtureTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let status: Int
    let content: String
    let finish: String
    init(status: Int = 200, content: String? = nil, finish: String = "stop") throws {
        self.status = status
        self.content = try content ?? String(decoding: JSONEncoder().encode(response()), as: UTF8.self)
        self.finish = finish
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let json: [String: Any] = ["model": "fixture-model", "choices": [["finish_reason": finish, "message": ["content": content]]]]
        return (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
@Test func deepSeekRequestUsesJSONAndSeparateEvidence() async throws {
    let transport = try FixtureTransport()
    let client = DeepSeekClient(apiKey: "unit-test-placeholder", model: "test-model", transport: transport)
    let result = try await client.grade(input(), judge: .c)
    #expect(result.judge == .c)
    #expect(result.model == "fixture-model")
    let request = try #require(await transport.requests.first)
    #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
    let requestData = try #require(request.httpBody)
    let body = try #require(try JSONSerialization.jsonObject(with: requestData) as? [String: Any])
    let messages = try #require(body["messages"] as? [[String: String]])
    #expect(messages.count == 2)
    #expect(messages[0]["content"]?.contains("Judge C") == true)
    #expect(messages[0]["content"]?.contains("UNTRUSTED") == true)
    let evidenceText = try #require(messages[1]["content"])
    let evidence = try #require(try JSONSerialization.jsonObject(with: Data(evidenceText.utf8)) as? [String: Any])
    #expect(evidence["essay"] as? String == input().essay)
    #expect(evidence["question"] as? String == input().question)
    #expect(evidence["reviewers"] == nil)
    #expect(body["reasoning_effort"] as? String == "max")
    #expect((body["thinking"] as? [String: String])?["type"] == "enabled")
    #expect((body["response_format"] as? [String: String])?["type"] == "json_object")
}
@Test func rejectsHTTPInvalidJSONAndTruncation() async throws {
    for transport in [try FixtureTransport(status: 401), try FixtureTransport(content: "{}"), try FixtureTransport(content: ""), try FixtureTransport(finish: "length")] {
        let client = DeepSeekClient(apiKey: "test", model: "test", transport: transport)
        await #expect(throws: (any Error).self) { try await client.grade(input(), judge: .a) }
    }
}
@Test func rejectsInventedCorrectionSpans() async throws {
    let correction = Correction(original: "This never occurred in the essay", corrected: "A replacement", category: .grammar, severity: .major, explanation: "Test")
    let content = String(decoding: try JSONEncoder().encode(response(corrections: [correction])), as: UTF8.self)
    let client = DeepSeekClient(apiKey: "test", model: "test", transport: try FixtureTransport(content: content))
    await #expect(throws: (any Error).self) { try await client.grade(input(), judge: .b) }
}
@Test @MainActor func swiftDataRoundTripAndRewrite() throws {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let report = try ScoreAggregator.aggregate(results([8, 7.5, 8]), task: .kaoyanSmall, isDemo: true)
    let session = try EssaySession(task: .kaoyanSmall, question: input().question, essay: input().essay, duration: 877, inputMode: .handwritten, report: report, sourceImages: [Data([1, 2, 3])])
    context.insert(session); session.finalRewrite = "A saved rewrite."; try context.save()
    let reloaded = try #require(ModelContext(container).fetch(FetchDescriptor<EssaySession>()).first)
    #expect(reloaded.id == session.id)
    #expect(reloaded.finalRewrite == "A saved rewrite.")
    #expect(reloaded.report?.reviewers.count == 3)
    #expect(reloaded.writingDuration == 877)
    #expect(reloaded.inputMode == "handwritten")
    #expect(reloaded.isDemo)
    #expect(try JSONDecoder().decode([Data].self, from: #require(reloaded.sourceImages)) == [Data([1, 2, 3])])
}
@Test @MainActor func draftsRemainSeparateAcrossTasks() throws {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = WritingStore(); store.attach(ModelContext(container)); store.essay = "My first draft."; store.elapsed = 123; store.persistDraft()
    store.select(.ieltsTask2); store.essay = "My IELTS draft."; store.persistDraft()
    store.select(.kaoyanSmall)
    #expect(store.essay == "My first draft.")
    #expect(store.elapsed >= 123)
    store.select(.ieltsTask2)
    #expect(store.essay == "My IELTS draft.")
}
@Test func everyRubricIsBundled() throws {
    for task in WritingTask.allCases { let rubric = try RubricLoader.load(task); #expect(rubric.contains(RubricLoader.version)); #expect(rubric.count > 200) }
}
@Test @MainActor func visionRecognizesAnActualImage() async throws {
    let image = NSImage(size: NSSize(width: 1000, height: 300))
    image.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 300).fill()
    ("Dear Alex,\nI invite you to a lecture on Chinese culture.\nYours, Li Ming" as NSString).draw(in: NSRect(x: 35, y: 35, width: 930, height: 230), withAttributes: [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.black])
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("writebench-ocr-\(UUID()).png")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let pages = try await VisionOCRService().recognize(urls: [url])
    #expect(pages.count == 1)
    #expect(pages[0].text.localizedCaseInsensitiveContains("Chinese culture"))
    #expect(pages[0].imageData == data)
}

@Test @MainActor func answeringRequiresStartAndPreservesDraftOnLeaving() throws {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = WritingStore(); store.attach(ModelContext(container))
    store.essay = input().essay; store.textChanged()
    #expect(store.stage == .preparation)
    #expect(!store.timerRunning)
    store.submit(service: MockGradingService(), isDemo: true) { _ in Issue.record("Preparation must not be able to submit") }
    #expect(store.gradingTask == nil)
    #expect(store.error != nil)
    #expect(store.startAnswering())
    #expect(store.isInSession && store.timerRunning)
    #expect(!store.showsLiveWordCount)
    store.select(.cet6Writing)
    #expect(store.task == .kaoyanSmall) // An active session cannot switch exams.
    #expect(store.leaveAnswering())
    #expect(store.stage == .preparation && !store.timerRunning)
    let restored = WritingStore(); restored.attach(ModelContext(container))
    #expect(restored.essay == input().essay)
    #expect(restored.stage == .preparation)
    #expect(restored.startAnswering())
    #expect(restored.leaveAnswering())
    restored.select(.cet6Writing); #expect(!restored.showsLiveWordCount)
    restored.select(.ieltsTask2); #expect(restored.showsLiveWordCount)
}
@Test @MainActor func handInSavesThenReturnsToPreparation() async throws {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let store = WritingStore(); store.attach(context); store.essay = input().essay
    #expect(store.startAnswering())
    var savedID: UUID?
    store.submit(service: RecordingGrader(), isDemo: true) { savedID = $0.id }
    #expect(store.stage == .grading && !store.timerRunning)
    #expect(!store.leaveAnswering())
    let grading = try #require(store.gradingTask); await grading.value
    #expect(savedID != nil)
    #expect(store.stage == .preparation && !store.timerRunning)
    #expect(try context.fetchCount(FetchDescriptor<EssaySession>()) == 1)
}
private struct UnavailableGrader: EssayGradingService {
    func grade(_ input: GradingInput, judge: Judge) async throws -> ReviewerResult { throw GradingError.http(503) }
}
@Test @MainActor func failedGradingReturnsToImmersionWithoutLosingAnswer() async throws {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let store = WritingStore(); store.attach(context); store.essay = input().essay; store.startAnswering()
    store.submit(service: UnavailableGrader(), isDemo: false) { _ in Issue.record("A failed grade must not complete") }
    let grading = try #require(store.gradingTask); await grading.value
    #expect(store.stage == .answering && store.timerRunning)
    #expect(store.essay == input().essay)
    #expect(store.error != nil)
    #expect(try context.fetchCount(FetchDescriptor<EssaySession>()) == 0)
}
@Test @MainActor func rewriteUsesImmersionAndUpdatesOriginalHistory() throws {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let report = try ScoreAggregator.aggregate(results([8, 7.5, 8]), task: .kaoyanSmall, isDemo: true)
    let source = try EssaySession(task: .kaoyanSmall, question: input().question, essay: input().essay, duration: 120, inputMode: .typed, report: report)
    context.insert(source); try context.save()
    let store = WritingStore(); store.attach(context); store.beginRewrite(source)
    #expect(store.stage == .answering)
    store.essay = "My revised answer."; #expect(store.leaveAnswering())
    #expect(source.finalRewrite == "My revised answer.")
    let restored = WritingStore(); restored.attach(ModelContext(container)); restored.startAnswering(); restored.essay = "The resumed rewrite."; restored.leaveAnswering()
    let updated = try #require(ModelContext(container).fetch(FetchDescriptor<EssaySession>()).first)
    #expect(updated.finalRewrite == "The resumed rewrite.")
    #expect(updated.originalEssay == input().essay)
    restored.question = "An entirely different question."
    restored.essay = "An answer to the new question."
    restored.persistDraft()
    let unaffected = try #require(ModelContext(container).fetch(FetchDescriptor<EssaySession>()).first)
    #expect(unaffected.finalRewrite == "The resumed rewrite.")
}

@Test @MainActor func missingAPIKeyBlocksTypedAndHandwrittenGradingWithoutAResult() throws {
    for mode in [InputMode.typed, .handwritten] {
        for emptyKey in [false, true] {
            let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let context = ModelContext(container)
            let store = WritingStore(); store.attach(context)
            store.essay = input().essay; store.inputMode = mode; store.startAnswering()
            store.submitConfigured(configuration: GradingConfiguration(), loadKey: {
                if emptyKey { return " \n " }
                throw GradingError.missingKey
            }) { _ in Issue.record("Missing credentials must never yield a review") }
            #expect(store.needsAPIKey)
            #expect(store.stage == .answering && store.timerRunning)
            #expect(store.gradingTask == nil)
            #expect(try context.fetchCount(FetchDescriptor<EssaySession>()) == 0)
            #expect(try context.fetch(FetchDescriptor<WritingDraft>()).first?.essay == input().essay)
            #expect(store.leaveAnswering()) // The settings action saves and safely leaves immersion.
            #expect(store.essay == input().essay)
        }
    }
}
@Test @MainActor func keychainAccessFailureIsAnErrorAndNeverFallsBackToMock() throws {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let store = WritingStore(); store.attach(context); store.essay = input().essay; store.startAnswering()
    store.submitConfigured(configuration: GradingConfiguration(), loadKey: { throw KeychainError(status: -25308) }) { _ in Issue.record("Keychain errors must never yield a review") }
    #expect(!store.needsAPIKey)
    #expect(store.error != nil)
    #expect(store.gradingTask == nil)
    #expect(store.stage == .answering)
    #expect(try context.fetchCount(FetchDescriptor<EssaySession>()) == 0)
}

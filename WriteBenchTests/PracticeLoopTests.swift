import Foundation
import SwiftData
import Testing
@testable import WriteBench

private let essay = "Dear Alex, I’m writing to invite you to  our lecture. I look forward to hear from you. Yours, Li Ming."
private func judgeResponse(_ score: Double = 8, corrections: [Correction] = [], expressions: [ExpressionSuggestion] = []) -> JudgeResponse {
    JudgeResponse(score: score, taskCompletion: 8, language: 7, coherence: 8, register: 8, majorErrors: [], minorErrors: [], summary: "Clear invitation.",
                  corrections: corrections, improvedVersion: essay, strengths: ["Clear purpose."], weaknesses: ["Verb form."], improvements: ["Check verbs."],
                  expressions: expressions)
}
private func report(_ scores: [Double] = [8, 7.5, 8], corrections: [Correction] = [], expressions: [ExpressionSuggestion] = []) throws -> GradingReport {
    try ScoreAggregator.aggregate(zip(Judge.allCases, scores).map {
        ReviewerResult(judge: $0.0, response: judgeResponse($0.1, corrections: corrections, expressions: expressions), model: "test", timestamp: Date())
    }, task: .kaoyanSmall, isDemo: false)
}
@MainActor private func container() throws -> ModelContainer {
    try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, EssayFolderMetadata.self, ReviewCard.self,
                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}
private let verbCorrection = Correction(original: "look forward to hear", corrected: "look forward to hearing", category: .grammar, severity: .major, explanation: "to 是介词。")

// MARK: Correction anchoring

@Test func correctionSpansTolerateQuoteSpacingAndCaseDrift() throws {
    #expect(CorrectionMatcher.range(of: "I'm writing", in: essay).map { String(essay[$0]) } == "I’m writing")
    #expect(CorrectionMatcher.range(of: "to our lecture", in: essay).map { String(essay[$0]) } == "to  our lecture")
    #expect(CorrectionMatcher.range(of: "LOOK FORWARD", in: essay).map { String(essay[$0]) } == "look forward")
    #expect(CorrectionMatcher.range(of: "，", in: "你好，世界").map { String("你好，世界"[$0]) } == "，")
    #expect(CorrectionMatcher.range(of: "not in the essay", in: essay) == nil)
    let anchored = CorrectionMatcher.anchored([
        Correction(original: "I'm writing", corrected: "I am writing", category: .register, severity: .minor, explanation: "Formal."),
        Correction(original: "a sentence the model invented", corrected: "x", category: .grammar, severity: .major, explanation: "Invented."),
        Correction(original: "Li Ming", corrected: "Li Ming", category: .grammar, severity: .minor, explanation: " ")
    ], in: essay)
    #expect(anchored.map(\.original) == ["I’m writing"])
    #expect(CorrectionMatcher.equivalent("Look forward to HEARING ", "look forward to hearing"))
    #expect(!CorrectionMatcher.equivalent("look forward", "look forward to hearing"))
    let sentence = try #require(CorrectionMatcher.range(of: "hear from", in: essay))
    #expect(CorrectionMatcher.sentence(containing: sentence, in: essay) == "I look forward to hear from you.")
}

private actor OneShotStream: StreamingHTTPTransport {
    let events: [String]
    init(_ events: [String]) { self.events = events }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.unsupportedURL) }
    func stream(for request: URLRequest, onEvent: @escaping @Sendable (String) async throws -> Bool) async throws {
        for event in events { if try await !onEvent(event) { return } }
    }
}
@Test func deepSeekKeepsAReviewWhoseCorrectionQuotesDriftAndRecordsUsage() async throws {
    var response = judgeResponse(corrections: [verbCorrection, Correction(original: "Im writing", corrected: "I am writing", category: .spelling, severity: .minor, explanation: "Not in essay.")])
    response.corrections[0].original = "look forward to  hear"
    let content = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
    let chunk = try JSONSerialization.data(withJSONObject: ["model": "fixture", "choices": [["index": 0, "delta": ["content": content], "finish_reason": "stop"]]])
    let usage = #"{"model":"fixture","choices":[],"usage":{"prompt_tokens":1200,"completion_tokens":800,"prompt_cache_hit_tokens":200,"completion_tokens_details":{"reasoning_tokens":500}}}"#
    let client = DeepSeekClient(apiKey: "fixture", model: "fixture", transport: OneShotStream([String(decoding: chunk, as: UTF8.self), usage, "[DONE]"]))
    let input = GradingInput(task: .kaoyanSmall, question: "Invite Alex.", essay: essay, rubric: "Test")
    let result = try await client.grade(input, judge: .b) { _ in }
    #expect(result.response.corrections.map(\.original) == ["look forward to hear"])
    #expect(result.usage == TokenUsage(input: 1200, cachedInput: 200, output: 800, reasoning: 500))
    let recorded = try #require(result.usage)
    let cost = try #require(UsageCost.cost(recorded, prices: .init(input: 4, cached: 1, output: 16)))
    let expected: Double = (1000.0 * 4 + 200.0 * 1 + 800.0 * 16) / 1_000_000
    #expect(abs(cost - expected) < 1e-9)
    #expect(UsageCost.cost(recorded, prices: .init(input: 0, cached: 0, output: 0)) == nil)
}
@Test func codexUsageIsReadFromTheTurnCompletionEvent() {
    let stdout = """
    {"type":"thread.started","thread_id":"x"}
    {"type":"turn.completed","usage":{"input_tokens":5000,"cached_input_tokens":1000,"output_tokens":700,"reasoning_output_tokens":300}}
    """
    #expect(CodexUsage.parse(Data(stdout.utf8)) == TokenUsage(input: 5000, cachedInput: 1000, output: 700, reasoning: 300))
    #expect(CodexUsage.parse(Data("not json".utf8)) == nil)
}
@Test func codexSchemaRequiresExpressions() throws {
    let schema = try #require(JSONSerialization.jsonObject(with: JudgeResponseSchema.data()) as? [String: Any])
    #expect((schema["required"] as? [String])?.contains("expressions") == true)
}

// MARK: Quick review

private actor RecordingGrader: EssayGradingService {
    var judges: [Judge] = []
    func grade(_ input: GradingInput, judge: Judge) async throws -> ReviewerResult {
        judges.append(judge)
        return ReviewerResult(judge: judge, response: judgeResponse(6.5), model: "test", timestamp: Date())
    }
}
@Test func quickReviewAsksOnlyTheChosenJudge() async throws {
    let grader = RecordingGrader()
    let input = GradingInput(task: .kaoyanSmall, question: "Invite Alex.", essay: essay, rubric: "Test")
    let quick = try await GradingCoordinator(service: grader).grade(input, isDemo: false, judges: [.b])
    #expect(await grader.judges == [.b])
    #expect(quick.gradingMode == .quick && quick.confidence == .single && quick.finalScore == 6.5 && quick.spread == 0)
    #expect(quick.improvedVersion == essay && quick.duration != nil && quick.reviewers[0].duration != nil)
    #expect(throws: (any Error).self) { try ScoreAggregator.aggregate(quick.reviewers, task: .kaoyanSmall, isDemo: false) }
    var configuration = GradingConfiguration(); configuration.quickJudge = .c
    #expect(configuration.with(.quick).judges == [.c] && configuration.with(.quick).requiresCodex && !configuration.with(.quick).requiresDeepSeek)
    #expect(configuration.judges == Judge.allCases)
}
@Test func reportsSavedBeforeQuickReviewDecodeAsFullReviews() throws {
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(try report())) as? [String: Any])
    json.removeValue(forKey: "mode"); json.removeValue(forKey: "duration")
    let legacy = try JSONDecoder().decode(GradingReport.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.gradingMode == .full && legacy.expressions.isEmpty && legacy.usage == nil)
}
@Test @MainActor func quickSubmissionTracksOneJudgeAndClearsTheSubmittedDraft() async throws {
    let context = ModelContext(try container()), store = WritingStore()
    store.attach(context); store.question = "Invite Alex."; store.essay = essay; store.elapsed = 300
    #expect(store.startAnswering())
    store.submit(service: RecordingGrader(), isDemo: false, judges: [.a])
    #expect(store.gradingJob?.total == 1 && store.gradingJob?.isQuick == true)
    await store.gradingTask?.value
    let saved = try #require(store.gradingJob?.session)
    #expect(saved.report?.gradingMode == .quick && saved.confidence == "Single")
    #expect(store.essay.isEmpty && store.elapsed == 0 && store.question == "Invite Alex.")
}

// MARK: Exam time limit

@Test @MainActor func crossingTheExamLimitSignalsOnce() async throws {
    let defaults = UserDefaults.standard, previous = defaults.object(forKey: "examTimeLimit")
    defaults.set(true, forKey: "examTimeLimit")
    defer { if let previous { defaults.set(previous, forKey: "examTimeLimit") } else { defaults.removeObject(forKey: "examTimeLimit") } }
    let store = WritingStore(); store.attach(ModelContext(try container())); store.essay = "Draft"
    #expect(store.timeLimit == TimeInterval(900))
    #expect(store.startAnswering())
    store.elapsed = 15 * 60 - 0.001
    try await Task.sleep(for: .milliseconds(20)); store.tick()
    #expect(store.timeUpCount == 1)
    try await Task.sleep(for: .milliseconds(20)); store.tick()
    #expect(store.timeUpCount == 1)
    store.leaveAnswering(); store.startOver()
    #expect(store.essay.isEmpty && store.elapsed == 0)
}

// MARK: Revisions and bank

@Test func revisionDiffCountsWordsAndHandlesChinese() {
    let english = RevisionDiff.compare("I look forward to hear from you.", "I really look forward to hearing from you.")
    #expect(english.inserted == 2 && english.removed == 1)
    #expect(String(english.text.characters) == "I really look forward to hear hearing from you.")
    #expect(String(RevisionDiff.compare("in the hall on Friday at noon", "in the hall at noon").text.characters) == "in the hall on Friday at noon")
    let chinese = RevisionDiff.compare("学习很重要", "学习非常重要")
    #expect(chinese.inserted == 2 && chinese.removed == 1)
}
@Test @MainActor func baselinePrefersRecordedParentThenEarlierAttempt() throws {
    let context = ModelContext(try container())
    let first = try EssaySession(task: .kaoyanSmall, question: "Q", essay: "One", duration: 1, inputMode: .typed, report: report())
    let second = try EssaySession(task: .kaoyanSmall, question: "Q ", essay: "Two", duration: 1, inputMode: .typed, report: report())
    let third = try EssaySession(task: .kaoyanSmall, question: "Q", essay: "Three", duration: 1, inputMode: .typed, report: report(), parentSessionID: first.id)
    first.date = Date(timeIntervalSince1970: 1); second.date = Date(timeIntervalSince1970: 2); third.date = Date(timeIntervalSince1970: 3)
    for session in [first, second, third] { context.insert(session) }
    let all = [first, second, third]
    #expect(RevisionBaseline.find(for: third, among: all)?.session.id == first.id)
    #expect(RevisionBaseline.find(for: third, among: all)?.label == "第 1 稿")
    #expect(RevisionBaseline.find(for: second, among: all)?.session.id == first.id)
    #expect(RevisionBaseline.find(for: first, among: all) == nil)
}
@Test @MainActor func questionBankIsOriginalUniqueAndTracksPractice() throws {
    for task in WritingTask.allCases { #expect(QuestionBank.questions(for: task).count >= 4) }
    let ids = QuestionBank.all.map(\.id), prompts = QuestionBank.all.map(\.prompt)
    #expect(Set(ids).count == ids.count && Set(prompts).count == prompts.count)
    #expect(QuestionBank.questions(for: .kaoyanSmall)[0].prompt == WritingTask.kaoyanSmall.sampleQuestion)
    let pick = QuestionBank.questions(for: .ieltsTask2)[2]
    let session = try EssaySession(task: .ieltsTask2, question: pick.prompt + "\n", essay: essay, duration: 1, inputMode: .typed, report: report([7, 7, 7]))
    let index = PracticeIndex([session])
    #expect(index.attempts(.ieltsTask2, pick.prompt).count == 1 && index.attempts(.ieltsTask1, pick.prompt).isEmpty)
    let store = WritingStore(); store.attach(ModelContext(try container())); store.essay = "keep"
    #expect(store.useQuestion(pick.prompt, title: pick.title, task: .ieltsTask2))
    #expect(store.task == .ieltsTask2 && store.question == pick.prompt && store.questionLabel == pick.title)
}

// MARK: Spaced review

@Test @MainActor func reviewCardsSyncOnceAndProgressToMastery() throws {
    let context = ModelContext(try container())
    let expression = ExpressionSuggestion(phrase: "look forward to hearing from you", meaning: "期待你的回复", example: "I look forward to hearing from you soon.")
    let session = try EssaySession(task: .kaoyanSmall, question: "Q", essay: essay, duration: 1, inputMode: .typed, report: report(corrections: [verbCorrection], expressions: [expression]))
    context.insert(session); try context.save()
    #expect(try ReviewCardSync.sync(context) == 2)
    #expect(try ReviewCardSync.sync(context) == 0)
    let cards = try context.fetch(FetchDescriptor<ReviewCard>())
    let mistake = try #require(cards.first { $0.cardKind == .mistake })
    #expect(mistake.context == "I look forward to hear from you." && mistake.answer == "look forward to hearing" && mistake.isDue)
    let now = Date()
    SpacedRepetition.apply(.again, to: mistake, now: now)
    #expect(mistake.box == 0 && mistake.lapseCount == 1 && mistake.dueDate > now)
    for (step, days) in SpacedRepetition.intervals.enumerated() {
        SpacedRepetition.apply(.good, to: mistake, now: now)
        #expect(mistake.box == step + 1 && !mistake.mastered)
        #expect(Calendar.current.dateComponents([.day], from: now, to: mistake.dueDate).day == days)
    }
    SpacedRepetition.apply(.good, to: mistake, now: now)
    #expect(mistake.mastered && !mistake.isDue)
    SpacedRepetition.setMastered(mistake, false, now: now)
    #expect(mistake.box == 0 && !mistake.mastered)
    let manual = try ReviewCardSync.addExpression(phrase: " Look forward to hearing from you ", meaning: "x", example: "", task: .kaoyanSmall, in: context)
    #expect(manual.key == ReviewCardSync.expressionKey(phrase: expression.phrase))
    #expect(throws: (any Error).self) { try ReviewCardSync.addExpression(phrase: "", meaning: "x", example: "", task: .kaoyanSmall, in: context) }
}

// MARK: Backup

@Test @MainActor func backupRoundTripsEverythingAndRestoreNeverOverwrites() throws {
    let source = ModelContext(try container())
    let session = try EssaySession(task: .kaoyanSmall, question: "Q", essay: essay, duration: 90, inputMode: .handwritten, report: report(corrections: [verbCorrection]),
                                   questionImage: Data([1, 2]), sourceImages: [Data([3])])
    session.finalRewrite = "Rewrite"
    source.insert(session)
    source.insert(SavedQuestion(title: "Saved", task: .cet6Writing, prompt: "P", year: 2024, label: "真题"))
    source.insert(EssayFolderMetadata(key: "folder", title: "Folder", questionYear: 2023, label: "L"))
    let draft = WritingDraft(task: .ieltsTask2); draft.essay = "Unfinished"; source.insert(draft)
    try source.save(); try ReviewCardSync.sync(source)
    let card = try #require(try source.fetch(FetchDescriptor<ReviewCard>()).first); card.box = 3; try source.save()
    let data = try BackupService.export(from: source)
    #expect(!String(decoding: data, as: UTF8.self).contains("fixture-key"))

    let target = ModelContext(try container())
    let summary = try BackupService.restore(data, into: target)
    #expect(summary.added == 5 && summary.skipped == 0)
    let restored = try #require(try target.fetch(FetchDescriptor<EssaySession>()).first)
    #expect(restored.id == session.id && abs(restored.date.timeIntervalSince(session.date)) < 1)
    #expect(restored.finalRewrite == "Rewrite" && restored.questionImage == Data([1, 2]) && restored.inputMode == "handwritten" && restored.report?.corrections.count == 1)
    #expect(try target.fetch(FetchDescriptor<SavedQuestion>()).first?.label == "真题")
    #expect(try target.fetch(FetchDescriptor<ReviewCard>()).first?.box == 3)
    #expect(try target.fetch(FetchDescriptor<WritingDraft>()).first?.essay == "Unfinished")
    let again = try BackupService.restore(data, into: target)
    #expect(again.added == 0 && again.skipped == 5)
    #expect(throws: (any Error).self) { try BackupService.restore(Data("{}".utf8), into: target) }
}

// MARK: English II writing

@Test func englishTwoWritingTasksHaveTheirOwnScalesRubricsAndFigureRule() throws {
    #expect(Exam.kaoyan.tasks == [.kaoyanSmall, .kaoyanLarge, .kaoyan2Small, .kaoyan2Large, .kaoyanTranslation, .kaoyan2Translation])
    #expect(WritingTask.kaoyan2Small.maxScore == 10 && WritingTask.kaoyan2Large.maxScore == 15 && WritingTask.kaoyanLarge.maxScore == 20)
    #expect(WritingTask.kaoyan2Large.targetWords == 150 && !WritingTask.kaoyan2Large.isTranslation)
    for task in [WritingTask.kaoyan2Small, .kaoyan2Large] { #expect(try RubricLoader.load(task).contains("English II")) }
    let input = GradingInput(task: .kaoyan2Large, question: "Write an essay based on the chart.\n【配图说明】看电视 90.8%", essay: "TV is popular.", rubric: try RubricLoader.load(.kaoyan2Large))
    let prompt = GraderPrompt.system(judge: .a, input: input)
    #expect(prompt.contains("【配图说明】") && prompt.contains("0–15.0"))
}

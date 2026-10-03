import Foundation
import AppKit
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

// MARK: Question underline and editor

@Test func underlineMarkupRendersInPlaceAndStripsForPlainText() {
    let source = "Read and translate. (46) <u>We don't have to learn it.</u> It is innate. 【配图说明】图"
    #expect(QuestionText.plain(source) == "Read and translate. (46) We don't have to learn it. It is innate. 【配图说明】图")
    let attributed = QuestionText.attributed(source)
    #expect(String(attributed.characters) == QuestionText.plain(source))
    let underlined = attributed.runs.filter { $0.underlineStyle != nil }.map { String(attributed[$0.range].characters) }
    #expect(underlined == ["We don't have to learn it."])
    #expect(String(QuestionText.attributed("No markup <u>open").characters) == "No markup open")
}
@Test @MainActor func ruledEditorKeepsTextHeightLinesAndEvenPitch() throws {
    let view = RuledTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.layoutManager?.usesFontLeading = false
    view.string = "First line\n第二行\n\nFourth"
    view.apply(.init(font: .serif, size: 18, ruled: true))
    let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
    manager.ensureLayout(for: container)
    let style = try #require(view.defaultParagraphStyle)
    #expect(style.lineSpacing > 0 && style.maximumLineHeight < 36)
    var tops: [CGFloat] = []
    manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { rect, _, _, _, _ in tops.append(rect.minY) }
    let steps = zip(tops.dropFirst(), tops).map { $0 - $1 }
    #expect(!steps.isEmpty && steps.allSatisfy { abs($0 - 36) < 0.5 })
}
@Test @MainActor func customCaretSitsOnTheTextLineWithoutCrossingTheRule() throws {
    let view = RuledTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.layoutManager?.usesFontLeading = false
    view.string = "Dear Alex,\n\nI am writing"
    view.apply(.init(font: .sans, size: 18, ruled: true, sheetNumber: "47."))
    #expect(view.insertionPointColor == .clear)
    var frames: [NSRect] = []
    for index in [0, 4, 12, (view.string as NSString).length] {
        view.setSelectedRange(NSRange(location: index, length: 0))
        frames.append(try #require(view.caretFrame()))
    }
    #expect(frames.allSatisfy { $0.height < 36 && $0.height > 15 && $0.width <= 2 })
    #expect(frames[1].minX > frames[0].minX && abs(frames[1].minY - frames[0].minY) < 0.5)
    #expect(abs(frames[2].minY - frames[0].minY - 72) < 0.5)
    view.setSelectedRange(NSRange(location: 0, length: 4))
    #expect(view.caretFrame() == nil)
    #expect(WritingTask.kaoyan2Small.answerSheet?.number == "47." && WritingTask.kaoyanTranslation.answerSheet?.number == "46–50" && WritingTask.cet6Writing.answerSheet == nil)
}

// MARK: Per-sentence translation scores

private func segments(_ scores: [Double]) -> [SegmentScore] {
    zip(46..., scores).map { SegmentScore(number: String($0.0), score: $0.1, maxScore: 2, comment: "第 \($0.0) 句",
        points: [ScoringPoint(source: "main clause", earned: min($0.1, 1), max: 1, note: ""), ScoringPoint(source: "modifier", earned: max(0, $0.1 - 1), max: 1, note: "")]) }
}
@Test func englishOneTranslationTotalsFollowTheSentenceMarks() {
    var response = judgeResponse(6, corrections: [])
    response.segments = segments([2, 1.5, 1, 2, 1])
    ScoreAggregator.reconcileSegments(&response, task: .kaoyanTranslation)
    #expect(response.score == 7.5)
    response.score = 7
    ScoreAggregator.reconcileSegments(&response, task: .kaoyanTranslation)
    #expect(response.score == 7) // A 0.5 typo deduction is allowed.
    response.segments.append(SegmentScore(number: "51", score: 3, maxScore: 2, comment: "out of range"))
    ScoreAggregator.reconcileSegments(&response, task: .kaoyanTranslation)
    #expect(response.segments.count == 5)
    ScoreAggregator.reconcileSegments(&response, task: .kaoyan2Translation)
    #expect(response.segments.isEmpty)
}
@Test func sentenceMarksComeFromTheMedianReviewer() throws {
    let marks = [[2, 2, 1.5, 2, 1.5], [1.5, 1, 1, 1.5, 1], [2, 1.5, 1.5, 1.5, 1]]
    let reviewers = zip(Judge.allCases, marks).map { judge, marks -> ReviewerResult in
        var response = judgeResponse(marks.reduce(0, +)); response.segments = segments(marks)
        return ReviewerResult(judge: judge, response: response, model: "test", timestamp: Date())
    }
    let report = try ScoreAggregator.aggregate(reviewers, task: .kaoyanTranslation, isDemo: false)
    #expect(report.finalScore == 7.5 && report.medianReviewer?.judge == .c)
    #expect(report.segmentScores.map(\.segment.score) == [2, 1.5, 1.5, 1.5, 1])
    #expect(report.segmentScores[1].byJudge.map(\.score) == [2, 1, 1.5])
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(judgeResponse())) as? [String: Any])
    json.removeValue(forKey: "segments")
    #expect(try JSONDecoder().decode(JudgeResponse.self, from: JSONSerialization.data(withJSONObject: json)).segments.isEmpty)
}
@Test func promptsAndSchemaAskForSentenceMarksOnlyForEnglishOneTranslation() throws {
    let question = "Translate the underlined segments. (46) <u>We don't have to learn it.</u> It is innate. (47) <u>It never leaves us.</u>"
    #expect(QuestionText.underlinedSegments(question) == ["46": "We don't have to learn it.", "47": "It never leaves us."])
    let translation = GraderPrompt.system(judge: .a, input: GradingInput(task: .kaoyanTranslation, question: question, essay: "x", rubric: try RubricLoader.load(.kaoyanTranslation)))
    #expect(translation.contains("segments is REQUIRED") && translation.contains("踩点给分"))
    let essay = GraderPrompt.system(judge: .a, input: GradingInput(task: .kaoyanSmall, question: "Q", essay: "x", rubric: "r"))
    #expect(essay.contains("segments must be an empty array"))
    let schema = try #require(JSONSerialization.jsonObject(with: JudgeResponseSchema.data()) as? [String: Any])
    #expect((schema["required"] as? [String])?.contains("segments") == true)
}

// MARK: One consolidated report

private actor ScriptedSynthesizer: ReportSynthesizer {
    let fail: Bool
    var calls = 0
    init(fail: Bool = false) { self.fail = fail }
    func synthesize(_ input: GradingInput, report: GradingReport) async throws -> SynthesisResult {
        calls += 1
        if fail { throw GradingError.http(503) }
        var draft = judgeResponse(1, corrections: [Correction(original: "look forward to  hear", corrected: "look forward to hearing", category: .grammar, severity: .major, explanation: "动名词。"),
                                                   Correction(original: "invented span", corrected: "x", category: .grammar, severity: .minor, explanation: "x")])
        draft.summary = "汇总结论"; draft.strengths = ["合并后的优点"]; draft.improvedVersion = "Consolidated version."
        return SynthesisResult(response: try SynthesisPrompt.finalize(draft, input: input, report: report), model: "chief", provider: .deepSeek, usage: TokenUsage(input: 10, cachedInput: 0, output: 5, reasoning: nil))
    }
}
private actor ScoreGrader: EssayGradingService {
    let scores: [Judge: Double]
    init(_ scores: [Judge: Double]) { self.scores = scores }
    func grade(_ input: GradingInput, judge: Judge) async throws -> ReviewerResult {
        ReviewerResult(judge: judge, response: judgeResponse(scores[judge] ?? 7), model: "test", timestamp: Date())
    }
}
@Test func threeReviewsBecomeOneReportWithoutChangingTheMarks() async throws {
    let input = GradingInput(task: .kaoyanSmall, question: "Invite Alex.", essay: essay, rubric: "Test")
    let synthesizer = ScriptedSynthesizer()
    let report = try await GradingCoordinator(service: ScoreGrader([.a: 6, .b: 7.5, .c: 8]), synthesizer: synthesizer).grade(input, isDemo: false)
    #expect(await synthesizer.calls == 1)
    #expect(report.finalScore == 7.5 && report.synthesis?.score == 7.5 && report.synthesis?.language == report.dimension(\.language))
    #expect(report.conclusion == "汇总结论" && report.strengths == ["合并后的优点"] && report.improvedVersion == "Consolidated version.")
    #expect(report.corrections.map(\.original) == ["look forward to hear"])
    #expect(report.usage?.input == 10 && report.synthesisProvider == .deepSeek)
    let quick = try await GradingCoordinator(service: ScoreGrader([:]), synthesizer: synthesizer).grade(input, isDemo: false, judges: [.b])
    let callsAfterQuick = await synthesizer.calls
    #expect(quick.synthesis == nil && callsAfterQuick == 1)
}
@Test func failedSynthesisKeepsTheLocalMergeAndExplains() async throws {
    let input = GradingInput(task: .kaoyanSmall, question: "Invite Alex.", essay: essay, rubric: "Test")
    let report = try await GradingCoordinator(service: ScoreGrader([.a: 6, .b: 7.5, .c: 8]), synthesizer: ScriptedSynthesizer(fail: true)).grade(input, isDemo: false)
    #expect(report.synthesis == nil && report.finalScore == 7.5 && report.synthesisNote?.contains("汇总未完成") == true)
    #expect(report.conclusion == "Clear invitation.")
    let decoded = try JSONDecoder().decode(GradingReport.self, from: JSONEncoder().encode(report))
    #expect(decoded.synthesisNote == report.synthesisNote)
}
@Test func englishOneTranslationTotalIsTheSumOfSentenceMedians() throws {
    let marks: [[Double]] = [[2, 2, 2, 1, 1], [1, 1, 1, 2, 2], [1.5, 1.5, 1.5, 1.5, 1.5]]
    let reviewers = zip(Judge.allCases, marks).map { judge, marks -> ReviewerResult in
        var response = judgeResponse(marks.reduce(0, +)); response.segments = segments(marks)
        return ReviewerResult(judge: judge, response: response, model: "test", timestamp: Date())
    }
    let report = try ScoreAggregator.aggregate(reviewers, task: .kaoyanTranslation, isDemo: false)
    #expect(report.medianSegments.map(\.score) == [1.5, 1.5, 1.5, 1.5, 1.5])
    #expect(report.finalScore == 7.5)
    #expect(report.segmentScores.allSatisfy { $0.byJudge.count == 3 })
    let prompt = SynthesisPrompt.system(GradingInput(task: .kaoyanTranslation, question: "Q", essay: "答", rubric: "r"), report: report)
    #expect(prompt.contains("(46) 1.5/2.0") && prompt.contains("Do not mention examiners"))
}

@Test @MainActor func answerSheetAlignmentPersistsAsTextAndUndoRestoresIndentation() throws {
    let view = RuledTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.isRichText = false
    view.isEditable = true
    view.allowsUndo = true
    view.string = "  Notice\nBody with  two spaces\nUniversity Library"
    view.apply(.init(font: .sans, size: 18, ruled: true))
    view.layoutManager?.ensureLayout(for: try #require(view.textContainer))
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    window.makeFirstResponder(view)
    let undo = try #require(view.undoManager)
    undo.beginUndoGrouping()
    let original = view.string
    view.setSelectedRange(NSRange(location: 3, length: 0))
    view.alignLines(.right)
    let right = view.string
    let rightIndent = right.prefix(while: { $0 == " " }).count
    #expect(rightIndent > 20)
    #expect(right.hasSuffix("\nBody with  two spaces\nUniversity Library"))
    undo.endUndoGrouping()
    undo.undo()
    #expect(view.string == original)
    view.setSelectedRange(NSRange(location: 3, length: 0))
    view.alignLines(.center)
    let centerIndent = view.string.prefix(while: { $0 == " " }).count
    #expect(abs(centerIndent * 2 - rightIndent) <= 1)
    view.setSelectedRange(NSRange(location: 3, length: 0))
    view.alignLines(.left)
    #expect(view.string == "Notice\nBody with  two spaces\nUniversity Library")
    view.setSelectedRange(NSRange(location: 6, length: 0))
    view.insertTab(nil)
    #expect(view.string.hasPrefix("Notice    \n"))
}

@Test @MainActor func trailingSpacesAdvanceTheCaret() throws {
    let view = RuledTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.apply(.init(font: .sans, size: 18, ruled: true))
    var xs: [CGFloat] = []
    for spaces in 0...5 {
        view.string = "Notice" + String(repeating: " ", count: spaces)
        view.apply(.init(font: .sans, size: 18, ruled: true))
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        xs.append(try #require(view.caretFrame()).minX)
    }
    #expect(zip(xs, xs.dropFirst()).allSatisfy { $1 > $0 + 1 })
}

private func teachingLesson() -> TranslationLesson {
    TranslationLesson(number: "46", source: "Reading makes us wiser.", groups: [
        TranslationMeaningGroup(source: "Reading", translation: "阅读", vocabulary: [
            TranslationVocabulary(word: "Reading", partOfSpeech: "动名词", commonMeaning: "阅读", contextualMeaning: "阅读这一活动")], techniques: ["动名词作主语，译为阅读。"]),
        TranslationMeaningGroup(source: "makes us wiser.", translation: "让我们更有智慧", vocabulary: [], techniques: ["make + 宾语 + 形容词，表示使某人变得……。"])
    ], referenceTranslation: "阅读使我们更有智慧。", assemblyNotes: ["主语与谓语顺接，保留比较级。"], studentAdvice: "你的译文保留了使役关系，注意译出比较级。")
}
@Test @MainActor func translationLessonsRoundTripOldReportsAndExport() throws {
    var response = judgeResponse()
    response.translationLessons = [teachingLesson()]
    let data = try JSONEncoder().encode(response)
    #expect(try JSONDecoder().decode(JudgeResponse.self, from: data).translationLessons == response.translationLessons)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "translationLessons")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(JudgeResponse.self, from: legacy).translationLessons.isEmpty)
    var grade = try report([8, 8, 8])
    grade.reviewers[0].response.translationLessons = [teachingLesson()]
    let session = try EssaySession(task: .kaoyanTranslation, question: "(46) <u>Reading makes us wiser.</u>", essay: "阅读使我们智慧。", duration: 90, inputMode: .typed, report: grade)
    let exported = try #require(ReviewTextExporter.text(for: session))
    #expect(exported.contains("意群精讲") && exported.contains("动名词") && exported.contains("完整译文") && exported.contains("比较级"))
}
@Test func teachingGroundsGroupsVocabularyAndExamScopeInSource() {
    let input = GradingInput(task: .kaoyanTranslation, question: "Context. (46) <u>Reading makes us wiser.</u>", essay: "阅读使我们智慧。", rubric: "Test")
    let lesson = teachingLesson()
    #expect(TranslationTeaching.anchored([lesson], input: input).count == 1)
    var wrong = lesson
    wrong.number = "47"
    #expect(TranslationTeaching.anchored([wrong], input: input).isEmpty)
    wrong = lesson; wrong.groups.reverse()
    #expect(TranslationTeaching.anchored([wrong], input: input).isEmpty)
    wrong = lesson; wrong.groups[0].vocabulary.append(.init(word: "invented", partOfSpeech: "adj.", commonMeaning: "虚构", contextualMeaning: "虚构"))
    #expect(TranslationTeaching.anchored([wrong], input: input).first?.groups[0].vocabulary.count == 1)
    #expect(TranslationTeaching.instructions(.kaoyan2Translation).contains("Do not apply English I's 2-point rule"))
    #expect(TranslationTeaching.instructions(.kaoyanSmall).contains("empty array"))
}
@Test func synthesisRetainsTeachingWithoutChangingMarks() throws {
    let input = GradingInput(task: .kaoyanTranslation, question: "(46) <u>Reading makes us wiser.</u>", essay: "阅读使我们智慧。", rubric: "Test")
    var grade = try report([8, 8, 8])
    grade.reviewers[0].response.translationLessons = [teachingLesson()]
    var draft = judgeResponse(1)
    draft.translationLessons = []
    let final = try SynthesisPrompt.finalize(draft, input: input, report: grade)
    #expect(final.score == grade.finalScore)
    #expect(final.translationLessons == [teachingLesson()])
    let prompt = SynthesisPrompt.system(input, report: grade)
    #expect(prompt.contains("commonMeaning") && prompt.contains("assemblyNotes") && prompt.contains("studentAdvice"))
}
@Test @MainActor func handInPausesBeforeCredentialsAndOnlyExplicitResumeRestarts() throws {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = WritingStore()
    store.attach(ModelContext(container))
    store.essay = "A draft answer."
    #expect(store.startAnswering())
    store.elapsed = 90
    store.submitConfigured(configuration: .init(), loadKey: { throw GradingError.missingKey })
    #expect(store.needsAPIKey && !store.timerRunning && store.stage == .answering)
    let frozen = store.elapsed
    store.tick()
    #expect(store.elapsed == frozen)
    store.resumeAnswering()
    #expect(store.timerRunning && store.elapsed == frozen)
    store.pauseForSubmission()
    #expect(!store.timerRunning)
}

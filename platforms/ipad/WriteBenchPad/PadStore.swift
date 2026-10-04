import SwiftUI
import SwiftData

// iPad uses the same report format as desktop; CLI providers are not available on iPadOS.
enum GradingProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepSeek, codex
    var id: String { rawValue }
    var title: String { self == .deepSeek ? "DeepSeek" : "ChatGPT · via Codex" }
}
enum GradingProgressEvent: Sendable {
    case started(Judge), preview(Judge, String), completed(ReviewerResult), failed(Judge, String), summarizing
}
@MainActor enum DeepSeekCredentials {
    private static var key: String?
    static var hasSessionKey: Bool { key != nil }
    static func load() throws -> String { guard let key else { throw GradingError.missingKey }; return key }
    static func restore() throws {
        do { key = try KeychainService.load() } catch GradingError.missingKey { key = nil }
    }
    static func save(_ value: String) throws { try KeychainService.save(value); key = value.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func forget() throws { try KeychainService.remove(); key = nil }
}

@MainActor @Observable final class PadStore {
    var task: WritingTask = .cet6Writing
    var question = WritingTask.cet6Writing.sampleQuestion
    var label = "原创练习"
    var essay = ""
    var richText: Data?
    var pencilDrawing: Data?
    var questionImage: Data?
    var sourceImages: [Data] = []
    var inputMode: InputMode = .typed
    var elapsed: Double = 0
    var startedAt: Date?
    var isGrading = false
    var status = ""
    var previews: [Judge: String] = [:]
    var error: String?
    var result: EssaySession?
    var savedAt: Date?
    private var context: ModelContext?
    private var grading: Task<Void, Never>?
    var running: Bool { startedAt != nil }
    func time(at date: Date = Date()) -> Double { elapsed + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0) }
    func attach(_ context: ModelContext) { guard self.context == nil else { return }; self.context = context; restore() }
    func restore() {
        guard let context else { return }
        do {
            let subtype = task.rawValue
            if let draft = try context.fetch(FetchDescriptor<WritingDraft>(predicate: #Predicate { $0.subtype == subtype })).first {
                question = draft.question; label = draft.questionLabel; essay = draft.essay; elapsed = draft.elapsed; richText = draft.richText; pencilDrawing = draft.pencilDrawing; questionImage = draft.questionImage; sourceImages = draft.sourceImages.flatMap { try? JSONDecoder().decode([Data].self, from: $0) } ?? []; inputMode = InputMode(rawValue: draft.inputMode) ?? .typed
            } else { question = task.sampleQuestion; label = "原创练习"; essay = ""; elapsed = 0; richText = nil; pencilDrawing = nil; questionImage = nil; sourceImages = []; inputMode = .typed }
            startedAt = nil
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func save() -> Bool {
        guard let context else { return false }
        do {
            let subtype = task.rawValue
            let draft: WritingDraft
            if let found = try context.fetch(FetchDescriptor<WritingDraft>(predicate: #Predicate { $0.subtype == subtype })).first { draft = found }
            else { draft = WritingDraft(task: task); context.insert(draft) }
            draft.question = question; draft.questionLabel = label; draft.essay = essay; draft.richText = richText; draft.pencilDrawing = pencilDrawing; draft.questionImage = questionImage; draft.sourceImages = sourceImages.isEmpty ? nil : try JSONEncoder().encode(sourceImages); draft.inputMode = inputMode.rawValue; draft.elapsed = time(); draft.updatedAt = Date()
            try context.save(); savedAt = Date(); return true
        } catch { self.error = "草稿保存失败：\(error.localizedDescription)"; return false }
    }
    func pause() { elapsed = time(); startedAt = nil; _ = save() }
    func start() { guard !isGrading else { return }; if startedAt == nil { startedAt = Date() }; _ = save() }
    @discardableResult func select(_ task: WritingTask) -> Bool { guard !isGrading else { return false }; pause(); guard save() else { return false }; self.task = task; restore(); return true }
    func choose(_ item: BankQuestion) { guard select(item.task) else { return }; question = item.prompt; label = item.title; questionImage = nil; _ = save() }
    func randomQuestion() { if let item = QuestionBank.questions(for: task).randomElement() { choose(item) } }
    func cancel() { grading?.cancel() }
    func submit(quick: Bool) {
        guard !isGrading else { return }
        pause()
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !essay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请先填写题目与作答内容。"; return }
        guard save(), let context else { return }
        do {
            let key = try DeepSeekCredentials.load()
            let client = DeepSeekClient(apiKey: key, model: UserDefaults.standard.string(forKey: "deepSeekModel") ?? DeepSeekClient.defaultModel)
            let input = GradingInput(task: task, question: question, essay: essay, rubric: try RubricLoader.load(task))
            let duration = elapsed
            let capturedImage = questionImage, capturedSources = sourceImages, capturedMode = inputMode
            isGrading = true; result = nil; previews = [:]; status = "正在评阅"
            grading = Task {
                defer { isGrading = false; grading = nil }
                do {
                    let report = try await GradingCoordinator(service: client, synthesizer: quick ? nil : client).grade(input, isDemo: false, judges: quick ? [.b] : Judge.allCases) { event in
                        await MainActor.run {
                            switch event {
                            case .preview(let judge, let text): self.previews[judge] = text
                            case .completed(let reviewer): self.previews[reviewer.judge] = reviewer.response.summary
                            case .summarizing: self.status = "正在汇总评阅"
                            default: break
                            }
                        }
                    }
                    try Task.checkCancellation()
                    let session = try EssaySession(task: input.task, question: input.question, essay: input.essay, duration: duration, inputMode: capturedMode, report: report, questionImage: capturedImage, sourceImages: capturedSources)
                    context.insert(session)
                    do { try context.save() } catch { context.delete(session); throw error }
                    result = session; status = "评阅完成"
                    _ = try? ReviewCardSync.sync(context)
                } catch is CancellationError { status = "评阅已停止，草稿已保留" }
                catch { self.error = error.localizedDescription; status = "评阅未完成，草稿已保留" }
            }
        } catch { self.error = error.localizedDescription }
    }
}

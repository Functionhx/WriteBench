import SwiftUI
import SwiftData
import Observation

enum WritingStage { case preparation, answering }

@MainActor @Observable final class WritingStore {
    var task: WritingTask = .kaoyanSmall
    var question = WritingTask.kaoyanSmall.sampleQuestion
    var questionLabel = "原创练习 · 邀请信"
    var essay = ""
    private(set) var stage: WritingStage = .preparation
    var isInSession: Bool { stage != .preparation }
    var isGrading: Bool { gradingJob?.phase.isRunning == true }
    private(set) var gradingJob: BackgroundGradingJob?
    var inputMode: InputMode = .typed
    var elapsed: TimeInterval = 0
    var timerRunning = false
    var needsAPIKey = false
    var error: String?
    var showLibrary = false
    var questionImage: Data?
    var sourceImages: [Data] = []
    var saveStatus = "草稿自动保存"
    @ObservationIgnored var context: ModelContext?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored var gradingTask: Task<Void, Never>?
    private var lastTick = Date()
    private var lastPersist = Date()
    private var rewriteSessionID: UUID?
    var words: Int { WordCounter.count(essay) }
    var timerText: String { let t = Int(elapsed); return String(format: "%02d:%02d", t / 60, t % 60) }
    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }; self.context = context; restore()
    }
    func tick() {
        let now = Date()
        if timerRunning { elapsed += max(0, now.timeIntervalSince(lastTick)) }
        lastTick = now
        if timerRunning && now.timeIntervalSince(lastPersist) >= 15 { persistDraft() }
    }
    @discardableResult func startAnswering() -> Bool {
        guard stage == .preparation else { return false }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请先填写题目。"; return false }
        guard persistDraft() else { return false }
        lastTick = Date(); timerRunning = true; stage = .answering
        return true
    }
    @discardableResult func leaveAnswering() -> Bool {
        guard stage == .answering else { return false }
        tick()
        guard persistDraft() else { return false }
        timerRunning = false; stage = .preparation
        return true
    }
    func select(_ next: WritingTask) {
        guard next != task, stage == .preparation else { return }
        tick(); persistDraft(); task = next; restore(); timerRunning = false
    }
    func textChanged() {
        queueSave()
    }
    @discardableResult func importQuestion(text: String, title: String) -> Bool {
        guard stage == .preparation else { return false }
        do {
            let prompt = try QuestionTextReader.validated(text)
            guard persistDraft() else { return false }
            let previous = (question, questionLabel, questionImage, rewriteSessionID)
            saveTask?.cancel()
            question = prompt
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            questionLabel = name.isEmpty ? "文字导入" : name
            questionImage = nil
            rewriteSessionID = nil
            guard persistDraft() else {
                context?.rollback()
                (question, questionLabel, questionImage, rewriteSessionID) = previous
                return false
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func queueSave() {
        saveTask?.cancel(); saveStatus = "正在保存…"
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)); try Task.checkCancellation(); self?.persistDraft() } catch { }
        }
    }
    @discardableResult func persistDraft() -> Bool {
        guard let context else { return false }
        do {
            let key = task.rawValue
            let found = try context.fetch(FetchDescriptor<WritingDraft>(predicate: #Predicate { $0.subtype == key })).first
            let draft = found ?? WritingDraft(task: task)
            if found == nil { context.insert(draft) }
            draft.question = question; draft.questionLabel = questionLabel; draft.essay = essay; draft.elapsed = elapsed; draft.inputMode = inputMode.rawValue; draft.questionImage = questionImage
            draft.rewriteSessionID = rewriteSessionID
            if let sourceID = rewriteSessionID, let source = try context.fetch(FetchDescriptor<EssaySession>(predicate: #Predicate { $0.id == sourceID })).first {
                if source.question == question && source.subtype == task.rawValue { source.finalRewrite = essay }
                else { rewriteSessionID = nil; draft.rewriteSessionID = nil }
            }
            draft.sourceImages = sourceImages.isEmpty ? nil : try JSONEncoder().encode(sourceImages); draft.updatedAt = Date()
            try context.save(); lastPersist = Date(); saveStatus = "草稿已保存"; return true
        } catch { saveStatus = "草稿保存失败"; self.error = error.localizedDescription; return false }
    }
    private func restore() {
        guard let context else { return }
        do {
            let key = task.rawValue
            if let draft = try context.fetch(FetchDescriptor<WritingDraft>(predicate: #Predicate { $0.subtype == key })).first {
                question = draft.question; questionLabel = draft.questionLabel; essay = draft.essay; elapsed = draft.elapsed; inputMode = InputMode(rawValue: draft.inputMode) ?? .typed; questionImage = draft.questionImage
                rewriteSessionID = draft.rewriteSessionID
                sourceImages = draft.sourceImages.flatMap { try? JSONDecoder().decode([Data].self, from: $0) } ?? []
            } else { question = task.sampleQuestion; questionLabel = task == .kaoyanSmall ? "原创练习 · 邀请信" : "原创练习"; essay = ""; elapsed = 0; inputMode = .typed; questionImage = nil; sourceImages = []; rewriteSessionID = nil }
        } catch { self.error = error.localizedDescription }
    }
    func submitConfigured(configuration: GradingConfiguration, loadKey: @MainActor () throws -> String = DeepSeekCredentials.load, onComplete: @escaping (EssaySession) -> Void = { _ in }) {
        guard stage == .answering, !isGrading else { return }
        needsAPIKey = false
        guard persistDraft() else { return }
        var deepSeek: DeepSeekClient?
        do {
            if configuration.requiresDeepSeek {
                let key = try loadKey().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { throw GradingError.missingKey }
                guard !configuration.deepSeekModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请在设置中填写 DeepSeek 模型 ID。"; return }
                deepSeek = DeepSeekClient(apiKey: key, model: configuration.deepSeekModel)
            }
        } catch GradingError.missingKey { needsAPIKey = true; return }
        catch { self.error = error.localizedDescription; return }
        let selectedDeepSeek = deepSeek
        launchSubmission(configuration: configuration, isDemo: false, onComplete: onComplete) {
            var codex: CodexJudgeService?
            if configuration.requiresCodex {
                do {
                    let connection = try await CodexJudgeService.checkConnection(customPath: configuration.codexPath)
                    try Task.checkCancellation()
                    codex = CodexJudgeService(executable: connection.executable, model: configuration.codexModel, reasoning: configuration.codexReasoning)
                } catch {
                    if Task.isCancelled || error is CancellationError { throw CancellationError() }
                    let judges = Judge.allCases.filter { configuration.provider(for: $0) == .codex }.map(\.title).joined(separator: "、")
                    throw JudgeExecutionError(judge: Judge.allCases.first { configuration.provider(for: $0) == .codex } ?? .c,
                        detail: "\(judges) · ChatGPT via Codex\n\(error.localizedDescription)\n尚未发起评卷，请在设置中检查连接。")
                }
            }
            return ProviderRouter(configuration: configuration, deepSeek: selectedDeepSeek, codex: codex)
        }
    }
    func submit(service: any EssayGradingService, isDemo: Bool, onComplete: @escaping (EssaySession) -> Void = { _ in }) {
        launchSubmission(configuration: nil, isDemo: isDemo, onComplete: onComplete) { service }
    }
    private func launchSubmission(configuration: GradingConfiguration?, isDemo: Bool, onComplete: @escaping (EssaySession) -> Void,
                                  makeService: @escaping @Sendable () async throws -> any EssayGradingService) {
        guard !isGrading else { return }
        guard stage == .answering else { error = "请先点击开始答题。"; return }
        guard let context else { return }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !essay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请先填写题目与作答内容。"; return }
        tick(); guard persistDraft() else { return }
        do {
            let submission = GradingSubmission(input: GradingInput(task: task, question: question, essay: essay, rubric: try RubricLoader.load(task)),
                duration: elapsed, inputMode: inputMode, questionImage: questionImage, sourceImages: sourceImages, parentSessionID: rewriteSessionID)
            let job = BackgroundGradingJob(submission: submission, configuration: configuration, connecting: configuration?.requiresCodex == true)
            gradingJob = job
            timerRunning = false; stage = .preparation
            gradingTask = Task {
                let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "WriteBench 正在评阅已提交的作答")
                defer { ProcessInfo.processInfo.endActivity(activity) }
                defer { if gradingJob?.id == job.id { gradingTask = nil } }
                do {
                    let service = try await makeService()
                    try Task.checkCancellation()
                    job.phase = .reviewing
                    let report = try await GradingCoordinator(service: service).grade(submission.input, isDemo: isDemo) { event in
                        await MainActor.run { job.receive(event) }
                    }
                    try Task.checkCancellation()
                    job.phase = .saving
                    let session = try EssaySession(task: submission.input.task, question: submission.input.question, essay: submission.input.essay,
                        duration: submission.duration, inputMode: submission.inputMode, report: report, questionImage: submission.questionImage,
                        sourceImages: submission.sourceImages, parentSessionID: submission.parentSessionID)
                    context.insert(session)
                    do { try context.save() } catch { context.delete(session); throw error }
                    job.session = session; job.finish(.completed)
                    onComplete(session)
                } catch {
                    if Task.isCancelled || error is CancellationError { job.finish(.cancelled) }
                    else {
                        if let failure = error as? JudgeExecutionError { job.judges[failure.judge] = .failed }
                        job.finish(.failed, detail: error.localizedDescription)
                    }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func cancelGrading() {
        guard let job = gradingJob, job.phase.isRunning else { return }
        job.phase = .cancelling
        gradingTask?.cancel()
    }
    func dismissGradingStatus() {
        guard !isGrading else { return }
        gradingJob = nil
    }
    func beginRewrite(_ session: EssaySession) {
        guard stage == .preparation else { return }
        select(session.task)
        question = session.question; questionLabel = "重写练习"; questionImage = session.questionImage
        essay = session.finalRewrite.isEmpty ? session.originalEssay : session.finalRewrite
        elapsed = 0; timerRunning = false; inputMode = .typed; sourceImages = []; rewriteSessionID = session.id; persistDraft(); startAnswering()
    }
}

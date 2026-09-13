import SwiftUI
import SwiftData
import Observation

enum WritingStage { case preparation, answering, grading }

@MainActor @Observable final class WritingStore {
    var task: WritingTask = .kaoyanSmall
    var question = WritingTask.kaoyanSmall.sampleQuestion
    var questionLabel = "原创练习 · 邀请信"
    var essay = ""
    private(set) var stage: WritingStage = .preparation
    var isInSession: Bool { stage != .preparation }
    var isGrading: Bool { stage == .grading }
    var showsLiveWordCount: Bool { task.exam == .ielts }
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
    func submitConfigured(configuration: GradingConfiguration, loadKey: @MainActor () throws -> String = DeepSeekCredentials.load, onComplete: @escaping (EssaySession) -> Void) {
        guard stage == .answering else { return }
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
        if !configuration.requiresCodex {
            submit(service: ProviderRouter(configuration: configuration, deepSeek: selectedDeepSeek, codex: nil), isDemo: false, onComplete: onComplete)
            return
        }
        tick(); timerRunning = false; stage = .grading
        gradingTask = Task {
            do {
                let connection = try await CodexJudgeService.checkConnection(customPath: configuration.codexPath)
                try Task.checkCancellation()
                let codex = CodexJudgeService(executable: connection.executable, model: configuration.codexModel, reasoning: configuration.codexReasoning)
                stage = .answering
                submit(service: ProviderRouter(configuration: configuration, deepSeek: selectedDeepSeek, codex: codex), isDemo: false, onComplete: onComplete)
                if stage == .answering { lastTick = Date(); timerRunning = true; gradingTask = nil }
            } catch {
                stage = .answering; lastTick = Date(); timerRunning = true; gradingTask = nil
                if !(error is CancellationError) {
                    let judges = Judge.allCases.filter { configuration.provider(for: $0) == .codex }.map(\.title).joined(separator: "、")
                    self.error = "\(judges) · ChatGPT via Codex\n\(error.localizedDescription)\n本次尚未发起评卷。请保存并离开，前往设置检查连接。"
                }
            }
        }
    }
    func submit(service: any EssayGradingService, isDemo: Bool, onComplete: @escaping (EssaySession) -> Void) {
        guard stage == .answering else { error = "请先点击开始答题。"; return }
        guard let context else { return }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, words > 0 else { error = "请先填写题目与作文。"; return }
        tick(); guard persistDraft() else { return }
        do {
            let input = GradingInput(task: task, question: question, essay: essay, rubric: try RubricLoader.load(task))
            let duration = elapsed, mode = inputMode, image = questionImage, images = sourceImages
            timerRunning = false; stage = .grading
            gradingTask = Task {
                defer {
                    if stage == .grading { stage = .answering; lastTick = Date(); timerRunning = true }
                    gradingTask = nil
                }
                do {
                    let report = try await GradingCoordinator(service: service).grade(input, isDemo: isDemo)
                    try Task.checkCancellation()
                    let session = try EssaySession(task: input.task, question: input.question, essay: input.essay, duration: duration, inputMode: mode, report: report, questionImage: image, sourceImages: images)
                    context.insert(session)
                    do { try context.save() } catch { context.delete(session); throw error }
                    stage = .preparation
                    onComplete(session)
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
    func beginRewrite(_ session: EssaySession) {
        guard stage == .preparation else { return }
        select(session.task)
        question = session.question; questionLabel = "重写练习"; questionImage = session.questionImage
        essay = session.finalRewrite.isEmpty ? session.originalEssay : session.finalRewrite
        elapsed = 0; timerRunning = false; inputMode = .typed; sourceImages = []; rewriteSessionID = session.id; persistDraft(); startAnswering()
    }
}

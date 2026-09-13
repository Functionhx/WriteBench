import SwiftUI
import AppKit

struct WritingView: View {
    @Bindable var store: WritingStore
    var onReview: (EssaySession) -> Void
    @State private var ocrImport: OCRImport?
    @State private var isRecognizing = false
    @State private var ocrTask: Task<Void, Never>?
    @State private var editingQuestion = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        Group {
            if store.isInSession {
                ImmersiveWritingView(store: store, isRecognizing: isRecognizing, onSubmit: submit, onImport: { importImages(.essay) }, onCancelOCR: { ocrTask?.cancel() })
            } else {
                preparation
            }
        }
        .onReceive(clock) { _ in store.tick() }
        .sheet(item: $ocrImport) { imported in
            OCRConfirmationView(imported: imported, initialQuestion: store.question, allowEssayImport: store.isInSession) { purpose, question, essay, images in
                store.question = question
                if purpose != .essay { store.questionLabel = "图片导入 · 已校对"; store.questionImage = images.first }
                if purpose != .question {
                    store.essay = essay; store.inputMode = .handwritten; store.sourceImages = images
                    if store.persistDraft() { submit() }
                } else { store.persistDraft() }
            }
        }
        .sheet(isPresented: $store.showLibrary) { QuestionLibraryView(store: store) }
        .onDisappear { ocrTask?.cancel(); store.persistDraft() }
        .onChange(of: store.question) { _, _ in store.queueSave() }
        .onChange(of: store.essay) { _, _ in store.textChanged() }
    }
    private var preparation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(store.task.isTranslation ? "准备翻译" : "准备写作").font(.system(size: 26, weight: .semibold))
                    Text(store.task.isTranslation ? store.task.wordGuidance : "选好题目，开始一段安静的写作。").font(.system(size: 14)).foregroundStyle(WB.secondary)
                }
                taskTabs
                questionCard
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.essay.isEmpty ? "开始后进入沉浸式答题" : "已有草稿，开始后继续作答").font(.system(size: 14, weight: .medium))
                        Text("题目、答题区与计时。手写稿可在答题页导入。").font(.system(size: 12)).foregroundStyle(WB.secondary)
                    }
                    Spacer()
                    Button { editingQuestion = false; store.startAnswering() } label: { HStack(spacing: 12) { Text("开始答题"); Image(systemName: "arrow.right") } }
                        .buttonStyle(PrimaryButtonStyle()).disabled(store.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRecognizing)
                        .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("startAnswering")
                }
                if isRecognizing { HStack(spacing: 10) { ProgressView().controlSize(.small); Text("正在识别题目…").font(.system(size: 12)); Spacer(); Button("取消") { ocrTask?.cancel() }.buttonStyle(.plain) }.foregroundStyle(WB.secondary) }
                HStack {
                    Text(store.saveStatus).font(.system(size: 11))
                    Spacer()
                    Text("三位独立评审").font(.system(size: 11))
                }.foregroundStyle(WB.secondary.opacity(0.8)).padding(.top, 10)
            }.frame(maxWidth: 820).padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 36).frame(maxWidth: .infinity)
        }.background(WB.canvas)
    }
    private var taskTabs: some View {
        HStack(spacing: 10) {
            ForEach(store.task.exam.tasks) { task in
                Button { store.select(task) } label: {
                    Text(task.title).font(.system(size: 14, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 9)
                        .foregroundStyle(store.task == task ? WB.blue : WB.secondary)
                        .background(store.task == task ? WB.tint : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            Spacer()
            Button { store.showLibrary = true } label: { Label("我的题库", systemImage: "books.vertical") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WB.secondary)
        }
    }
    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("题目").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(store.questionLabel).font(.system(size: 12)).foregroundStyle(WB.secondary)
                IconButton(symbol: editingQuestion ? "checkmark" : "pencil", help: editingQuestion ? "完成编辑" : "编辑题目") { editingQuestion.toggle() }
            }
            if editingQuestion {
                PlainTextEditor(text: $store.question, fontSize: 15, identifier: "questionEditor").frame(height: 230).background(WB.canvas, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text(store.question).font(.system(size: 16)).lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let data = store.questionImage, let image = NSImage(data: data) {
                DisclosureGroup("题目原图") { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 230).padding(.top, 8) }.font(.system(size: 12)).foregroundStyle(WB.secondary)
            }
            HStack {
                Text(store.task.fullTitle).font(.system(size: 11)).foregroundStyle(WB.secondary)
                Spacer()
                Button { importImages(.question) } label: { Label("导入题目图片", systemImage: "photo") }.buttonStyle(QuietButtonStyle()).disabled(isRecognizing)
            }
        }.padding(28).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(WB.line.opacity(0.8)))
    }
    private func submit() {
        store.submitConfigured(configuration: .load(), onComplete: onReview)
    }
    private func importImages(_ purpose: OCRPurpose) {
        guard !isRecognizing, !store.isGrading else { return }
        if purpose != .question && !store.isInSession { return }
        ocrTask = Task {
            let urls = await ImageImporter.selectImages()
            guard !urls.isEmpty else { ocrTask = nil; return }
            isRecognizing = true
            defer { isRecognizing = false; ocrTask = nil }
            do { let pages = try await VisionOCRService().recognize(urls: urls); try Task.checkCancellation(); ocrImport = OCRImport(pages: pages, purpose: purpose) }
            catch is CancellationError { }
            catch { store.error = error.localizedDescription }
        }
    }
}
struct BlueIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 11) { configuration.icon.foregroundStyle(WB.blue); configuration.title } }
}

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit
import PencilKit

private enum PadPage: String, CaseIterable, Identifiable {
    case write = "答题", bank = "题库", history = "历史记录", practice = "错题复习", statistics = "统计", settings = "设置"
    var id: String { rawValue }
    var symbol: String { switch self { case .write: "square.and.pencil"; case .bank: "books.vertical"; case .history: "clock"; case .practice: "rectangle.on.rectangle"; case .statistics: "chart.bar"; case .settings: "gearshape" } }
}
struct PadWorkspace: View {
    @Bindable var store: PadStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: PadPage? = .write
    var body: some View {
        NavigationSplitView {
            List(PadPage.allCases, selection: $page) { item in Label(item.rawValue, systemImage: item.symbol).tag(item) }
                .navigationTitle("WriteBench")
                .safeAreaInset(edge: .bottom) { Text("iPad · 本地保存").font(.caption).foregroundStyle(.secondary).padding() }
        } detail: {
            NavigationStack {
                Group {
                    switch page ?? .write {
                    case .write: PadWriting(store: store)
                    case .bank: PadBank(store: store) { page = .write }
                    case .history: PadHistory()
                    case .practice: PadPractice()
                    case .statistics: PadStatistics()
                    case .settings: PadSettings(store: store)
                    }
                }.background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .task { store.attach(context); do { try DeepSeekCredentials.restore() } catch { store.error = error.localizedDescription } }
        .onChange(of: page) { _, _ in store.pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.pause(); store.cancel() }
        }
        .alert("请检查", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
        .sheet(item: $store.result) { PadReport(session: $0) }
    }
}
struct PadWriting: View {
    @Environment(\.modelContext) private var context
    @Bindable var store: PadStore
    @State private var handwriting = false
    @State private var erasing = false
    @State private var confirmClear = false
    @State private var canvasID = UUID()
    @State private var command: PadEditor.EditorCommand?
    @State private var importImages = false
    @State private var importText = false
    @State private var scanning = false
    @State private var ocr: OCRImport?
    @State private var submitDialog = false
    @State private var ocrDestination = OCRPurpose.question
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                controls
                if store.isGrading {
                    HStack { ProgressView(); Text(store.status); Spacer(); Button("停止评阅") { store.cancel() } }.padding().background(WB.tint, in: RoundedRectangle(cornerRadius: 12))
                }
                if geometry.size.width >= 850 {
                    HStack(alignment: .top, spacing: 20) { questionPanel.frame(width: geometry.size.width * 0.35); answerPanel }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView { VStack(spacing: 20) { questionPanel.frame(minHeight: 270); answerPanel.frame(height: max(430, geometry.size.height * 0.65)).id("answer-card") } }
                            .onChange(of: handwriting) { _, active in
                                if active { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("answer-card", anchor: .top) } }
                            }
                    }
                }
            }.padding(20)
        }
        .navigationTitle(store.task.fullTitle).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } label: { Image(systemName: "keyboard.chevron.compact.down") }.accessibilityLabel("收起键盘") }; ToolbarItem(placement: .topBarTrailing) { Button("交卷") { store.pause(); if handwriting && store.pencilDrawing != nil { store.error = "请先识别并校对手写作答，再交卷。" } else { submitDialog = true } }.disabled(store.isGrading).accessibilityIdentifier("submit") } }
        .confirmationDialog("选择评阅方式", isPresented: $submitDialog, titleVisibility: .visible) {
            Button("快速评阅 · 1 位评审") { store.submit(quick: true) }
            Button("完整评阅 · 3 位评审与汇总") { store.submit(quick: false) }
        } message: { Text("评阅会发送题目和作答至 DeepSeek，并使用你的 API 余额。交卷后计时暂停。") }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--ocr-review-testing") {
                ocr = OCRImport(pages: [OCRPage(name: "OCR 校对测试", imageData: Data(), text: "Dear Alex,\nPlease attend the reading programme.", warning: nil)], purpose: .question)
            }
            #endif
        }
        .onReceive(clock) { now = $0 }
        .task(id: store.essay) { do { try await Task.sleep(for: .milliseconds(400)); _ = store.save() } catch {} }
        .task(id: store.pencilDrawing) { do { try await Task.sleep(for: .milliseconds(400)); _ = store.save() } catch {} }
        .task(id: store.richText) { do { try await Task.sleep(for: .milliseconds(400)); _ = store.save() } catch {} }
        .task(id: store.question) { do { try await Task.sleep(for: .milliseconds(400)); _ = store.save() } catch {} }
        .fileImporter(isPresented: $importImages, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                scanning = true
                Task {
                    defer { scanning = false }
                    do { ocr = OCRImport(pages: try await VisionOCRService().recognize(urls: urls), purpose: ocrDestination) }
                    catch { store.error = error.localizedDescription }
                }
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importText, allowedContentTypes: [.plainText, .pdf]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 10 * 1024 * 1024 else { throw CETBankError.invalid("文件超过 10 MB") }
                let text: String
                if url.pathExtension.lowercased() == "pdf" {
                    guard let pdf = PDFDocument(url: url), pdf.pageCount <= 50 else { throw CETBankError.invalid("无法读取 PDF，或页数超过 50 页") }
                    text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n\n")
                } else { text = try String(contentsOf: url, encoding: .utf8) }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CETBankError.invalid("没有可读取的文字。扫描件请使用图片识别。") }
                store.question = text; store.questionImage = nil; store.label = url.lastPathComponent; _ = store.save()
            } catch { store.error = error.localizedDescription }
        }
        .sheet(item: $ocr) { imported in
            PadOCRReview(imported: imported) { text in
                if imported.purpose == .essay { store.essay = text; store.richText = nil; store.sourceImages = imported.pages.map(\.imageData); store.inputMode = .handwritten } else { store.question = text; store.questionImage = imported.pages.first?.imageData; store.label = "图片导入 · 已校对" }
                _ = store.save()
            }
        }
    }
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack { selectors; Spacer(); timerControls }
            VStack(alignment: .leading, spacing: 12) { selectors; timerControls }
        }
    }
    private var selectors: some View {
        HStack {
            Picker("考试", selection: Binding(get: { store.task.exam }, set: { if let task = $0.tasks.first { store.select(task) } })) {
                ForEach(Exam.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("exam-picker")
            Picker("题型", selection: Binding(get: { store.task }, set: { store.select($0) })) { ForEach(store.task.exam.tasks) { Text($0.title).tag($0) } }
        }.disabled(store.isGrading)
    }
    private var timerControls: some View {
        HStack {
            Text(String(format: "%02d:%02d", Int(store.time(at: now)) / 60, Int(store.time(at: now)) % 60)).monospacedDigit().accessibilityIdentifier("elapsed")
            Button(store.running ? "暂停" : "开始 / 继续") { if store.running { store.pause() } else { store.start() } }.buttonStyle(.bordered).disabled(store.isGrading)
        }
    }
    private var questionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("题目").font(.headline); Spacer(); Button("随机抽题") { store.randomQuestion() }.disabled(store.isGrading) }
            Text(store.label).font(.caption).foregroundStyle(.secondary)
            if let data = store.questionImage, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).accessibilityLabel("题目原图")
            }
            TextEditor(text: $store.question).font(.body).scrollContentBackground(.hidden).frame(minHeight: 160).disabled(store.isGrading).accessibilityIdentifier("question-editor")
            if scanning { ProgressView("正在识别图片…") }
            Menu("从图片导入", systemImage: "doc.viewfinder") {
                Button("识别题目") { ocrDestination = .question; importImages = true }
                Button("识别手写作答") { ocrDestination = .essay; importImages = true }
            }.disabled(scanning || store.isGrading)
            Button("保存题目到题库") {
                do {
                    let prompt = QuestionBank.key(store.question)
                    let exists = try context.fetch(FetchDescriptor<SavedQuestion>()).contains { $0.subtype == store.task.rawValue && QuestionBank.key($0.prompt) == prompt }
                    if !exists {
                        let item = SavedQuestion(title: store.label == "原创练习" ? "自定义题目" : store.label, task: store.task, prompt: store.question, image: store.questionImage)
                        context.insert(item)
                        do { try context.save() } catch { context.delete(item); throw error }
                    }
                } catch { store.error = error.localizedDescription }
            }.disabled(store.isGrading || store.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("导入文本 / PDF") { importText = true }.disabled(store.isGrading)
            Text(store.task.wordGuidance).font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private var answerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("答题卡").font(.headline)
                Spacer()
                Text(store.task.targetLanguage == "Simplified Chinese" ? "\(store.essay.count) 字符" : "\(WordCounter.count(store.essay)) words").foregroundStyle(.secondary).accessibilityIdentifier("word-count")
            }
            Picker("作答方式", selection: $handwriting) { Text("键盘输入").tag(false); Text("手写纸").tag(true) }.pickerStyle(.segmented).disabled(store.isGrading)
            if handwriting {
                HStack {
                    Toggle("橡皮擦", isOn: $erasing).toggleStyle(.button)
                    Button("识别并校对手写") { recognizeDrawing() }.disabled(scanning || store.isGrading || store.pencilDrawing == nil)
                    Spacer()
                    Button("清空", role: .destructive) { confirmClear = true }.disabled(store.isGrading)
                }.buttonStyle(.bordered)
                PadHandwriting(data: $store.pencilDrawing, erasing: erasing, editable: !store.isGrading).id(canvasID)
                Text("手写后先识别并校对，再交卷。笔迹会随草稿保存。").font(.caption).foregroundStyle(.secondary)
            } else {
            HStack(spacing: 16) {
                Button("四个空格") { command = .spaces(UUID()) }
                ForEach([NSTextAlignment.left, .center, .right], id: \.rawValue) { alignment in
                    Button { command = .alignment(alignment, UUID()) } label: { Image(systemName: alignment == .left ? "text.alignleft" : alignment == .center ? "text.aligncenter" : "text.alignright") }
                        .accessibilityLabel(alignment == .left ? "左对齐" : alignment == .center ? "居中" : "右对齐")
                }
            }.disabled(store.isGrading).buttonStyle(.bordered)
            PadEditor(text: $store.essay, richText: $store.richText, identifier: "answer-editor", editable: !store.isGrading, command: command)
            }
            HStack {
                Image(systemName: "checkmark.circle").foregroundStyle(WB.green)
                Text(store.savedAt == nil ? "自动保存草稿" : "草稿已保存").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Tab 插入四个空格").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
            .alert("清空手写笔迹？", isPresented: $confirmClear) { Button("清空笔迹", role: .destructive) { store.pencilDrawing = nil; canvasID = UUID(); _ = store.save() }; Button("取消", role: .cancel) {} }
    }
    private func recognizeDrawing() {
        guard let data = store.pencilDrawing, let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { store.error = "请先在手写纸上作答。"; return }
        let rect = drawing.bounds.insetBy(dx: -24, dy: -24)
        guard rect.width <= 8000, rect.height <= 8000 else { store.error = "手写范围过大，请分段识别。"; return }
        let image = drawing.image(from: rect, scale: min(2, 3200 / max(rect.width, rect.height)))
        guard let cg = image.cgImage else { return }
        let size = CGSize(width: cg.width, height: cg.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let flattened = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill(); renderer.fill(CGRect(origin: .zero, size: size)); image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = flattened.pngData() else { return }
        scanning = true
        Task {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { scanning = false; try? FileManager.default.removeItem(at: file) }
            do {
                try png.write(to: file)
                ocr = OCRImport(pages: try await VisionOCRService().recognize(urls: [file]), purpose: .essay)
                handwriting = false
            } catch { store.error = error.localizedDescription }
        }
    }
}
struct PadOCRReview: View {
    let imported: OCRImport
    let confirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var verified = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("对照原图校对，确认后填入\(imported.purpose.rawValue)。").foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(imported.pages) { page in
                            VStack {
                                if let image = UIImage(data: page.imageData) { Image(uiImage: image).resizable().scaledToFit().frame(width: 260, height: 200) }
                                Text(page.name).font(.caption)
                                if let warning = page.warning { Text(warning).font(.caption).foregroundStyle(.orange).frame(width: 260) }
                            }
                        }
                    }
                }
                TextEditor(text: $text).accessibilityIdentifier("ocr-review-editor")
                Toggle("我已对照原图核对所有页面", isOn: $verified)
            }.padding().navigationTitle("校对识别结果")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("确认填入") { confirm(text); dismiss() }.disabled(!verified || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.onAppear { text = imported.pages.map(\.text).joined(separator: "\n\n") }
    }
}

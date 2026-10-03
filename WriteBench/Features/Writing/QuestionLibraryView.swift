import SwiftUI
import SwiftData

struct QuestionLibraryView: View {
    enum Source: String, CaseIterable, Identifiable { case builtIn = "内置题目", saved = "我的题库"; var id: String { rawValue } }
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedQuestion.date, order: .reverse) private var questions: [SavedQuestion]
    @Query(filter: #Predicate<EssaySession> { !$0.isDemo }) private var sessions: [EssaySession]
    @Bindable var store: WritingStore
    @State private var source: Source = .builtIn
    @State private var task: WritingTask?
    @State private var search = ""
    @State private var unpractisedOnly = false
    @State private var label: String?
    @State private var title = ""
    @State private var year = ""
    @State private var newLabel = ""
    @State private var error: String?

    private struct Item: Identifiable {
        let id: String
        let task: WritingTask
        let title: String
        let prompt: String
        var image: Data? = nil
        var year: Int? = nil
        var label = ""
        var saved: SavedQuestion? = nil
    }
    private var currentTask: WritingTask { task ?? store.task }
    private var practiceIndex: PracticeIndex { PracticeIndex(sessions) }
    private var labels: [String] { Array(Set(questions.filter { $0.subtype == currentTask.rawValue }.map(\.label).filter { !$0.isEmpty })).sorted() }
    private func items(_ index: PracticeIndex) -> [Item] {
        let all: [Item] = source == .builtIn
            ? QuestionBank.questions(for: currentTask).map { Item(id: $0.id, task: $0.task, title: $0.title, prompt: $0.prompt) }
            : questions.filter { $0.subtype == currentTask.rawValue }.map {
                Item(id: $0.id.uuidString, task: currentTask, title: $0.title, prompt: $0.prompt, image: $0.image, year: $0.year, label: $0.label, saved: $0)
            }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { item in
            (query.isEmpty || [item.title, item.prompt, item.label].contains { $0.localizedCaseInsensitiveContains(query) })
                && (!unpractisedOnly || index.attempts(item.task, item.prompt).isEmpty)
                && (source == .builtIn || label == nil || item.label == label)
        }
    }
    var body: some View {
        let index = practiceIndex, visible = items(index)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "题库", subtitle: "内置题目均为原创练习；导入或识别的题目可保存到我的题库。")
                Spacer()
                IconButton(symbol: "xmark", help: "Close") { dismiss() }
            }
            HStack(spacing: 12) {
                Picker("来源", selection: $source) { ForEach(Source.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().fixedSize()
                Picker("题型", selection: Binding(get: { currentTask }, set: { task = $0; label = nil })) {
                    ForEach(store.task.exam.tasks) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 140)
                if source == .saved && !labels.isEmpty {
                    Picker("标签", selection: $label) {
                        Text("全部标签").tag(Optional<String>.none)
                        ForEach(labels, id: \.self) { Text($0).tag(Optional($0)) }
                    }.labelsHidden().frame(width: 120)
                }
                Spacer()
                Toggle("只看未练习", isOn: $unpractisedOnly).toggleStyle(.checkbox).font(.system(size: 12))
                Button { if let pick = (visible.filter { index.attempts($0.task, $0.prompt).isEmpty }.randomElement() ?? visible.randomElement()) { use(pick) } } label: {
                    Label("随机一道", systemImage: "dice")
                }.buttonStyle(QuietButtonStyle()).disabled(visible.isEmpty).help("优先抽取还没练过的题")
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(WB.secondary)
                TextField("搜索题目", text: $search).textFieldStyle(.plain)
            }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(WB.line))
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(visible) { item in row(item, attempts: index.attempts(item.task, item.prompt)) }
                    if visible.isEmpty {
                        EmptyState(symbol: "books.vertical", title: source == .saved ? "把好题留在这里" : "没有符合条件的题目",
                                   detail: source == .saved ? "在写作页导入或识别题目，再在下方命名保存。" : "换一个题型，或关闭“只看未练习”。")
                    }
                }
            }
            if source == .saved { saveBar }
            if let error { Text(error).foregroundStyle(WB.amber).font(.system(size: 12)) }
        }.padding(28).frame(width: 760, height: 640).background(WB.canvas)
    }
    private func row(_ item: Item, attempts: [EssaySession]) -> some View {
        Button { use(item) } label: {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                        if let year = item.year { Text(String(year)).font(.system(size: 11)).foregroundStyle(WB.blue) }
                        if item.image != nil { Label("配图", systemImage: "photo").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                        if !item.label.isEmpty { Text(item.label).font(.system(size: 11)).foregroundStyle(WB.secondary).padding(.horizontal, 6).padding(.vertical, 2).background(WB.tint, in: Capsule()) }
                        Spacer()
                        if let latest = attempts.last {
                            Text("已练 \(attempts.count) 次 · 最近 \(latest.finalScore.scoreText) / \(Int(item.task.maxScore))").font(.system(size: 11)).foregroundStyle(WB.green)
                        } else { Text("未练习").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                    }
                    Text(item.prompt).font(.system(size: 12)).foregroundStyle(WB.secondary).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.buttonStyle(.plain)
            .contextMenu { if let saved = item.saved { Button("从我的题库删除", role: .destructive) { delete(saved) } } }
    }
    private var saveBar: some View {
        HStack(spacing: 8) {
            TextField("题目名称，例如：2024 英语一 · 邀请信", text: $title).textFieldStyle(.roundedBorder)
            TextField("年份", text: $year).textFieldStyle(.roundedBorder).frame(width: 64)
            TextField("标签", text: $newLabel).textFieldStyle(.roundedBorder).frame(width: 100)
            Button("保存当前题目") { save() }.buttonStyle(QuietButtonStyle())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.question.isEmpty)
        }.help("保存写作页当前的\(store.task.title)题目")
    }
    private func use(_ item: Item) {
        if store.useQuestion(item.prompt, title: item.title, task: item.task, image: item.image) { dismiss() }
    }
    private func save() {
        do {
            let details = try EssayFolderDetails(title: title, year: year, label: newLabel)
            let question = SavedQuestion(title: details.title, task: store.task, prompt: store.question, image: store.questionImage, year: details.year, label: details.label)
            context.insert(question)
            do { try context.save(); title = ""; year = ""; newLabel = ""; error = nil; task = store.task }
            catch { context.delete(question); throw error }
        } catch { self.error = error.localizedDescription }
    }
    private func delete(_ question: SavedQuestion) {
        context.delete(question)
        do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

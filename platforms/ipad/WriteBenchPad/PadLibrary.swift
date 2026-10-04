import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PadBank: View {
    @Bindable var store: PadStore
    let chosen: () -> Void
    @Query private var saved: [SavedQuestion]
    @State private var task: WritingTask = .cet6Writing
    @State private var search = ""
    @State private var importing = false
    @State private var revision = 0
    private var questions: [BankQuestion] {
        _ = revision
        return (QuestionBank.questions(for: task) + saved.filter { $0.subtype == task.rawValue }.map { BankQuestion(id: $0.id.uuidString, task: task, title: $0.title, prompt: $0.prompt) }).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.prompt.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            Section {
                Picker("题型", selection: $task) { ForEach(WritingTask.allCases) { Text($0.fullTitle).tag($0) } }.accessibilityIdentifier("bank-task")
            }
            Section("\(questions.count) 道题 · 点击查看正文") {
                ForEach(questions) { item in
                    NavigationLink { ScrollView { VStack(alignment: .leading, spacing: 24) {
                        Text(item.title).font(.title2.bold())
                        Text(QuestionText.attributed(item.prompt)).font(.body).textSelection(.enabled)
                        Button("用这道题练习") { store.choose(item); chosen() }.buttonStyle(.borderedProminent).disabled(store.isGrading).accessibilityIdentifier("use-question")
                    }.padding(24) }.navigationTitle("题目正文") } label: { VStack(alignment: .leading, spacing: 8) { Text(item.title).font(.headline); Text(QuestionText.plain(item.prompt)).lineLimit(2).foregroundStyle(.secondary) } }.accessibilityIdentifier("bank-question")
                }
            }
        }.navigationTitle("题库").searchable(text: $search, prompt: "搜索题目或正文")
            .toolbar { Button("导入六级题库 JSON") { importing = true } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    _ = try CETQuestionBank.importData(Data(contentsOf: url)); revision += 1
                } catch { store.error = error.localizedDescription }
            }
    }
}
struct PadHistory: View {
    @Query(sort: \EssaySession.date, order: .reverse) private var sessions: [EssaySession]
    var body: some View {
        List {
            if sessions.isEmpty { ContentUnavailableView("还没有评阅记录", systemImage: "clock", description: Text("完成一次评阅后，可以在这里回看原稿、修改建议和参考版本。")) }
            ForEach(sessions) { session in
                NavigationLink { PadReport(session: session) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) { Text(session.task.fullTitle).font(.headline); Text(session.date, style: .date).foregroundStyle(.secondary) }
                        Spacer(); Text("\(session.finalScore.scoreText) / \(session.task.maxScore.scoreText)").font(.title3.monospacedDigit())
                    }
                }
            }
        }.navigationTitle("历史记录")
    }
}
struct PadReport: View {
    let session: EssaySession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.finalScore.scoreText).font(.system(size: 52, weight: .semibold, design: .rounded))
                        Text("/ \(session.task.maxScore.scoreText)").font(.title2).foregroundStyle(.secondary)
                        Spacer(); Text(session.task.fullTitle).font(.headline)
                    }
                    if let report = session.report {
                        Text(report.reviewers.count == 1 ? "快速评阅 · 1 位评审" : "完整评阅 · 3 位评审").foregroundStyle(.secondary)
                        Text(report.synthesis?.summary ?? report.reviewers.first?.response.summary ?? "").font(.body)
                        ForEach(report.corrections) { correction in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(correction.original).strikethrough().foregroundStyle(.secondary)
                                Text(correction.corrected).foregroundStyle(WB.green)
                                Text(correction.explanation).font(.callout)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(WB.tint, in: RoundedRectangle(cornerRadius: 12))
                        }
                        ForEach(report.translationLessons, id: \.number) { lesson in
                            DisclosureGroup("句子 \(lesson.number)：\(lesson.source)") {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(lesson.groups.enumerated()), id: \.offset) { _, group in
                                        Text(group.source).bold(); Text(group.translation)
                                        ForEach(Array(group.vocabulary.enumerated()), id: \.offset) { _, word in Text("\(word.word) · \(word.partOfSpeech) · \(word.contextualMeaning)").font(.callout) }
                                        Text(group.techniques.joined(separator: "\n")).foregroundStyle(.secondary)
                                    }
                                    Text(lesson.referenceTranslation).bold(); Text(lesson.assemblyNotes.joined(separator: "\n")); Text(lesson.studentAdvice)
                                }.padding(.vertical)
                            }
                        }
                        DisclosureGroup("各评审意见") { ForEach(report.reviewers, id: \.judge) { reviewer in VStack(alignment: .leading, spacing: 8) { Text("\(reviewer.judge.title) · \(reviewer.response.score.scoreText)").bold(); Text(reviewer.response.summary) }.padding(.vertical) } }
                    }
                    DisclosureGroup("题目与提交原稿") { VStack(alignment: .leading, spacing: 20) { Text(QuestionText.attributed(session.question))
                        if let data = session.questionImage, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360) }
                        Text(session.originalEssay) }.padding(.vertical).textSelection(.enabled) }
                    Text("参考版本").font(.title2.bold()); Text(session.correctedEssay).textSelection(.enabled)
                    ShareLink(item: "\(session.task.fullTitle)\n\(session.finalScore.scoreText)/\(session.task.maxScore.scoreText)\n\n\(session.originalEssay)\n\n参考版本\n\(session.correctedEssay)", label: { Label("分享复习文本", systemImage: "square.and.arrow.up") })
                }.padding(24).frame(maxWidth: 980)
            }.navigationTitle("评阅报告").toolbar { Button("完成") { dismiss() } }
        }
    }
}
struct PadPractice: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ReviewCard.dueDate) private var cards: [ReviewCard]
    @State private var revealed = Set<String>()
    @State private var error: String?
    var body: some View {
        List {
            let due = cards.filter(\.isDue)
            if due.isEmpty { ContentUnavailableView("当前没有待复习卡片", systemImage: "checkmark.circle", description: Text("评阅中的错误与表达会自动生成复习卡片。")) }
            ForEach(due, id: \.key) { card in
                VStack(alignment: .leading, spacing: 12) {
                    Text(card.prompt).font(.headline)
                    if revealed.contains(card.key) {
                        Text(card.answer).foregroundStyle(WB.green); Text(card.explanation); Text(card.context).font(.callout).foregroundStyle(.secondary)
                        HStack { Button("还不会") { review(card, .again) }; Spacer(); Button("记住了") { review(card, .good) } }.buttonStyle(.bordered)
                    } else { Button("显示答案") { revealed.insert(card.key) } }
                }.padding(.vertical, 8)
            }
        }.navigationTitle("错题复习").task { do { try ReviewCardSync.sync(context) } catch { self.error = error.localizedDescription } }
            .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") {} } message: { Text(error ?? "") }
    }
    private func review(_ card: ReviewCard, _ grade: ReviewGrade) {
        SpacedRepetition.apply(grade, to: card)
        do { try context.save() } catch { self.error = error.localizedDescription }
    }
}
struct PadStatistics: View {
    @Query private var sessions: [EssaySession]
    var body: some View {
        List {
            Section("练习积累") {
                LabeledContent("完成评阅", value: "\(sessions.count) 次")
                LabeledContent("累计作答", value: "\(sessions.reduce(0) { $0 + $1.wordCount }) words")
                LabeledContent("累计用时", value: "\(Int(sessions.reduce(0) { $0 + $1.writingDuration }) / 60) 分钟")
            }
            ForEach(WritingTask.allCases) { task in
                let values = sessions.filter { $0.subtype == task.rawValue }
                if !values.isEmpty { Section(task.fullTitle) { LabeledContent("练习次数", value: "\(values.count)"); LabeledContent("平均得分", value: "\((values.reduce(0) { $0 + $1.finalScore } / Double(values.count)).scoreText) / \(task.maxScore.scoreText)") } }
            }
        }.navigationTitle("统计")
    }
}

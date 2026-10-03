import SwiftUI
import SwiftData

/// Spaced review of past corrections and saved expressions.
struct PracticeView: View {
    enum Tab: String, CaseIterable, Identifiable { case review = "间隔复习", expressions = "表达库"; var id: String { rawValue } }
    @Environment(\.modelContext) private var context
    @Query(sort: \ReviewCard.dueDate) private var cards: [ReviewCard]
    @State private var tab: Tab = .review
    @State private var kind: ReviewCardKind?
    @State private var queue: [ReviewCard] = []
    @State private var position = 0
    @State private var reviewed = 0
    @State private var remembered = 0
    @State private var attempt = ""
    @State private var revealed = false
    @State private var inSession = false
    @State private var search = ""
    @State private var addingExpression = false
    @State private var error: String?
    @FocusState private var answerFocused: Bool

    private var active: [ReviewCard] { cards.filter { !$0.archived } }
    private func due(_ kind: ReviewCardKind?) -> [ReviewCard] { active.filter { $0.isDue && (kind == nil || $0.cardKind == kind) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    SectionHeading(title: "Practice what you missed.", subtitle: "复习 · 错题与表达按 1 / 2 / 4 / 8 / 16 天间隔重复，隔 16 天仍记得即掌握。")
                    Spacer()
                    Picker("", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if tab == .review { reviewTab } else { expressionTab }
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(WB.amber) }
            }.padding(32)
        }
        .task { do { try ReviewCardSync.sync(context) } catch { self.error = error.localizedDescription } }
        .sheet(isPresented: $addingExpression) { ExpressionEditor() }
    }

    // MARK: Review

    @ViewBuilder private var reviewTab: some View {
        HStack(spacing: 16) {
            metric("待复习", "\(due(nil).count)", note: "错题 \(due(.mistake).count) · 表达 \(due(.expression).count)")
            metric("学习中", "\(active.filter { !$0.mastered }.count)", note: "尚未掌握的卡片")
            metric("已掌握", "\(active.filter(\.mastered).count)", note: "可在错题或表达库中取消")
        }
        if inSession, position < queue.count { reviewCard(queue[position]) }
        else if inSession { finished }
        else { startCard }
    }
    private var startCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("开始一轮复习").font(.system(size: 18, weight: .semibold))
                Picker("内容", selection: $kind) {
                    Text("全部").tag(Optional<ReviewCardKind>.none)
                    Text("错题").tag(Optional(ReviewCardKind.mistake))
                    Text("表达").tag(Optional(ReviewCardKind.expression))
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(due(kind).isEmpty ? (active.isEmpty ? "完成一次评阅后，逐句修改和推荐表达会自动生成复习卡。" : "今天没有到期的卡片。明天再来，或去表达库添加新的表达。")
                     : "错题：看原句，写出改正后的说法。表达：看中文释义，写出英文表达。先自己写，再看答案，按实际情况选择“记住了”或“还没记住”。")
                    .font(.system(size: 13)).foregroundStyle(WB.secondary).lineSpacing(4)
                HStack { Spacer(); Button("开始复习 \(due(kind).count) 张") { start() }.buttonStyle(PrimaryButtonStyle()).disabled(due(kind).isEmpty).accessibilityIdentifier("startPractice") }
            }
        }
    }
    private func reviewCard(_ card: ReviewCard) -> some View {
        Card(padding: 28) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Text(card.cardKind == .mistake ? "错题 · \(card.category)" : "表达").font(.system(size: 12, weight: .semibold)).foregroundStyle(WB.blue)
                    if let task = card.task { Text(task.fullTitle).font(.system(size: 11)).foregroundStyle(WB.secondary) }
                    if card.lapseCount > 0 { Text("忘记过 \(card.lapseCount) 次").font(.system(size: 11)).foregroundStyle(WB.amber) }
                    Spacer()
                    Text("\(position + 1) / \(queue.count)").font(.system(size: 12)).monospacedDigit().foregroundStyle(WB.secondary)
                    Button("结束") { inSession = false }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WB.secondary)
                }
                if card.cardKind == .mistake {
                    Text("原句").font(.system(size: 12)).foregroundStyle(WB.secondary)
                    Text(highlighted(card.prompt, in: card.context)).font(.system(size: 18)).lineSpacing(6).textSelection(.enabled)
                    Text("改正标记的部分：").font(.system(size: 12)).foregroundStyle(WB.secondary)
                } else {
                    Text(card.prompt).font(.system(size: 20, weight: .medium)).textSelection(.enabled)
                    Text("写出对应的表达：").font(.system(size: 12)).foregroundStyle(WB.secondary)
                }
                TextField(card.cardKind == .mistake ? "改正后的写法" : "Expression", text: $attempt)
                    .textFieldStyle(.plain).font(.system(size: 16)).padding(12)
                    .background(WB.canvas, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(WB.line))
                    .focused($answerFocused).disabled(revealed).onSubmit { if !revealed { revealed = true } }
                    .accessibilityIdentifier("practiceAnswer")
                if revealed {
                    VStack(alignment: .leading, spacing: 10) {
                        if !attempt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label(CorrectionMatcher.equivalent(attempt, card.answer) ? "与参考答案一致" : "与参考答案不同，可对照判断是否同样正确",
                                  systemImage: CorrectionMatcher.equivalent(attempt, card.answer) ? "checkmark.circle" : "arrow.left.arrow.right")
                                .font(.system(size: 12)).foregroundStyle(CorrectionMatcher.equivalent(attempt, card.answer) ? WB.green : WB.secondary)
                        }
                        Text(card.answer).font(.system(size: 18, weight: .semibold)).foregroundStyle(WB.ink).textSelection(.enabled)
                        if !card.explanation.isEmpty { Text(card.explanation).font(.system(size: 13)).foregroundStyle(WB.secondary).lineSpacing(4).textSelection(.enabled) }
                        if card.cardKind == .expression && !card.context.isEmpty { Text(card.context).font(.system(size: 13)).italic().foregroundStyle(WB.secondary).textSelection(.enabled) }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(WB.tint.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Button("标记为已掌握") { SpacedRepetition.setMastered(card, true); advance(remembered: true) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WB.secondary)
                        Spacer()
                        Button("还没记住") { grade(card, .again) }.buttonStyle(QuietButtonStyle()).keyboardShortcut("1", modifiers: [])
                        Button("记住了") { grade(card, .good) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut("2", modifiers: [])
                    }
                } else {
                    HStack { Spacer(); Button("显示答案") { revealed = true }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.return, modifiers: .command) }
                }
            }
        }
    }
    private var finished: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("本轮完成").font(.system(size: 20, weight: .semibold))
                Text("复习 \(reviewed) 次，记住 \(remembered) 次。没记住的卡片 10 分钟后会再次到期。").font(.system(size: 13)).foregroundStyle(WB.secondary)
                HStack { Spacer(); Button("返回") { inSession = false }.buttonStyle(QuietButtonStyle()); Button("再来一轮") { start() }.buttonStyle(PrimaryButtonStyle()).disabled(due(kind).isEmpty) }
            }
        }
    }
    private func highlighted(_ span: String, in sentence: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = CorrectionMatcher.range(of: span, in: sentence), let lower = AttributedString.Index(range.lowerBound, within: text),
           let upper = AttributedString.Index(range.upperBound, within: text) {
            text[lower..<upper].backgroundColor = WB.amber.opacity(0.18)
            text[lower..<upper].underlineStyle = .single
        }
        return text
    }
    private func start() {
        queue = due(kind).shuffled().sorted { $0.dueDate < $1.dueDate }
        position = 0; reviewed = 0; remembered = 0; attempt = ""; revealed = false; inSession = true; answerFocused = true
    }
    private func grade(_ card: ReviewCard, _ grade: ReviewGrade) {
        SpacedRepetition.apply(grade, to: card)
        if grade == .again { queue.append(card) }
        advance(remembered: grade == .good)
    }
    private func advance(remembered success: Bool) {
        reviewed += 1; if success { remembered += 1 }
        do { try context.save() } catch { self.error = error.localizedDescription }
        position += 1; attempt = ""; revealed = false; answerFocused = true
    }

    // MARK: Expressions

    @ViewBuilder private var expressionTab: some View {
        let expressions = active.filter { $0.cardKind == .expression }.filter {
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || [$0.answer, $0.prompt, $0.context].contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { $0.createdAt > $1.createdAt }
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(WB.secondary)
            TextField("搜索表达或释义", text: $search).textFieldStyle(.plain)
            Spacer()
            Button { addingExpression = true } label: { Label("添加表达", systemImage: "plus") }.buttonStyle(QuietButtonStyle())
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(WB.line))
        if expressions.isEmpty {
            Card { EmptyState(symbol: "text.quote", title: "积累自己的表达", detail: "评审会从改进作文中推荐值得记住的表达，也可以手动添加。") }
        }
        ForEach(expressions) { card in
            Card(padding: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(card.answer).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                        Text(card.prompt).font(.system(size: 13)).foregroundStyle(WB.secondary).textSelection(.enabled)
                        if !card.context.isEmpty { Text(card.context).font(.system(size: 12)).italic().foregroundStyle(WB.secondary).textSelection(.enabled) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(card.mastered ? "已掌握" : "熟练度 \(card.box) / \(SpacedRepetition.intervals.count)").font(.system(size: 11)).foregroundStyle(card.mastered ? WB.green : WB.secondary)
                        Menu {
                            Button(card.mastered ? "重新学习" : "标记为已掌握") { SpacedRepetition.setMastered(card, !card.mastered); save() }
                            Button("从表达库移除", role: .destructive) { card.archived = true; save() }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(WB.secondary) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
                    }
                }
            }
        }
    }
    private func save() { do { try context.save() } catch { self.error = error.localizedDescription } }
    private func metric(_ title: String, _ value: String, note: String) -> some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 13)).foregroundStyle(WB.secondary)
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(note).font(.system(size: 10)).foregroundStyle(WB.secondary)
            }
        }
    }
}

private struct ExpressionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var phrase = ""
    @State private var meaning = ""
    @State private var example = ""
    @State private var task: WritingTask = .ieltsTask2
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加表达").font(.system(size: 20, weight: .semibold))
            TextField("表达，例如：strike a balance between A and B", text: $phrase).textFieldStyle(.roundedBorder)
            TextField("中文释义", text: $meaning).textFieldStyle(.roundedBorder)
            TextField("例句（可选）", text: $example).textFieldStyle(.roundedBorder)
            Picker("题型", selection: $task) { ForEach(WritingTask.allCases) { Text($0.fullTitle).tag($0) } }.frame(width: 300)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(WB.amber) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button("添加") {
                    do { try ReviewCardSync.addExpression(phrase: phrase, meaning: meaning, example: example, task: task, in: context); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 520).background(WB.canvas)
    }
}

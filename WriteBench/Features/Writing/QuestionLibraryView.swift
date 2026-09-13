import SwiftUI
import SwiftData

struct QuestionLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedQuestion.date, order: .reverse) private var questions: [SavedQuestion]
    @Bindable var store: WritingStore
    @State private var title = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { SectionHeading(title: "我的真题库", subtitle: "保存你导入的题目。内置示例均为原创练习。") ; Spacer(); IconButton(symbol: "xmark", help: "Close") { dismiss() } }
            HStack { TextField("题目名称，例如：2024 英语一 · 邀请信", text: $title).textFieldStyle(.roundedBorder); Button("保存当前题目") { save() }.buttonStyle(QuietButtonStyle()).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.question.isEmpty) }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(questions.filter { WritingTask(rawValue: $0.subtype)?.exam == store.task.exam }) { question in
                        Button { if let task = WritingTask(rawValue: question.subtype) { store.select(task) }; store.question = question.prompt; store.questionLabel = question.title; store.questionImage = question.image; dismiss() } label: {
                            Card(padding: 18) { VStack(alignment: .leading, spacing: 8) { Text(question.title).font(.system(size: 15, weight: .semibold)); Text(question.prompt).font(.system(size: 12)).foregroundStyle(WB.secondary).lineLimit(3) } }
                        }.buttonStyle(.plain)
                    }
                    if questions.filter({ WritingTask(rawValue: $0.subtype)?.exam == store.task.exam }).isEmpty { EmptyState(symbol: "books.vertical", title: "把好题留在这里", detail: "在写作页输入或识别题目，再为它命名保存。") }
                }
            }
            if let error { Text(error).foregroundStyle(WB.amber).font(.system(size: 12)) }
        }.padding(28).frame(width: 670, height: 540).background(WB.canvas)
    }
    private func save() {
        let question = SavedQuestion(title: title, task: store.task, prompt: store.question, image: store.questionImage)
        context.insert(question)
        do { try context.save(); title = "" } catch { context.delete(question); self.error = error.localizedDescription }
    }
}

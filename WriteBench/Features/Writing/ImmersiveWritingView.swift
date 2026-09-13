import SwiftUI

/// The only workspace that can edit or submit an answer.
struct ImmersiveWritingView: View {
    @Bindable var store: WritingStore
    var isRecognizing: Bool
    var onSubmit: () -> Void
    var onImport: () -> Void
    var onCancelOCR: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Button { store.leaveAnswering() } label: { Label("保存并离开", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WB.secondary).disabled(store.isGrading || isRecognizing).accessibilityIdentifier("leaveAnswering")
                Spacer()
                Text(store.task.fullTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(WB.secondary)
                Spacer()
                Label(store.timerText, systemImage: "clock").font(.system(size: 14)).monospacedDigit().foregroundStyle(WB.ink).accessibilityLabel("作答用时 \(store.timerText)")
                Button("交卷", action: onSubmit).buttonStyle(ExamSubmitStyle()).disabled(store.essay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isGrading || isRecognizing).keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("handInEssay")
            }.padding(.horizontal, 32).frame(height: 62)
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
            HSplitView {
                question.frame(minWidth: 250, idealWidth: 330, maxWidth: 440)
                answer.frame(minWidth: 490, maxWidth: .infinity)
            }.padding(.horizontal, 24).padding(.vertical, 28)
        }.background(.white).foregroundStyle(WB.ink)
            .overlay {
                if store.isGrading || isRecognizing {
                    Color.white.opacity(0.96).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().controlSize(.regular)
                        Text(store.isGrading ? "正在评阅" : "正在识别手写稿").font(.system(size: 20, weight: .medium))
                        Text(store.isGrading ? "三位评审正在独立评阅你的作答。" : "识别后请逐页校对，再确认评分。").font(.system(size: 13)).foregroundStyle(WB.secondary)
                        Button("取消") { if store.isGrading { store.gradingTask?.cancel() } else { onCancelOCR() } }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
    }
    private var question: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("试题").font(.system(size: 12, weight: .medium)).foregroundStyle(WB.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(store.question).font(.system(size: 15)).lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if let data = store.questionImage, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("题目原图") }
                }
            }.scrollIndicators(.hidden)
        }.padding(.leading, 8).padding(.trailing, 28)
    }
    private var answer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(store.task.exam == .ielts ? "Answer" : "答题区").font(.system(size: 12, weight: .medium)).foregroundStyle(WB.secondary)
                Spacer()
                if store.showsLiveWordCount { Text("\(store.words) words").font(.system(size: 12)).monospacedDigit().foregroundStyle(WB.secondary).accessibilityIdentifier("liveWordCount") }
            }
            PlainTextEditor(text: $store.essay, fontSize: store.task.exam == .ielts ? 18 : 20, editable: !store.isGrading, identifier: "essayEditor", ruled: store.task.exam != .ielts, requestFocus: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Rectangle().stroke(Color.black.opacity(0.12), lineWidth: 0.75))
            HStack {
                Text(store.saveStatus).font(.system(size: 10)).foregroundStyle(WB.secondary.opacity(0.7))
                Spacer()
                Button("导入手写稿", action: onImport).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WB.secondary).disabled(store.isGrading || isRecognizing).accessibilityIdentifier("importHandwritten")
            }
        }.padding(.leading, 28).padding(.trailing, 8)
    }
}
private struct ExamSubmitStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 9)
            .background(WB.blue.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 7))
    }
}

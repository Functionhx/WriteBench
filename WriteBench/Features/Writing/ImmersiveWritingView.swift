import SwiftUI

/// The only workspace that can edit or submit an answer.
struct ImmersiveWritingView: View {
    @AppStorage("showLiveWordCount") private var showLiveWordCount = false
    @AppStorage("examTimeLimit") private var examTimeLimit = false
    @AppStorage("editorFont") private var editorFont = EditorFont.sans
    @AppStorage("editorFontSize") private var editorFontSize = 18.0
    @AppStorage("editorRuled") private var editorRuled = true
    @Bindable var store: WritingStore
    var isRecognizing: Bool
    var onSubmit: () -> Void
    var onQuickSubmit: () -> Void
    var onImport: () -> Void
    var onCancelOCR: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Button { store.leaveAnswering() } label: { Label("保存并离开", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WB.secondary).disabled(isRecognizing).accessibilityIdentifier("leaveAnswering")
                Spacer()
                Text(store.task.fullTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(WB.secondary)
                Spacer()
                timer
                Button("快速单评", action: onQuickSubmit).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WB.secondary)
                    .disabled(store.essay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isGrading || isRecognizing)
                    .keyboardShortcut(.return, modifiers: [.command, .shift]).help("只请一位评审，适合草稿；⇧⌘↩").accessibilityIdentifier("quickHandIn")
                Button("交卷", action: onSubmit).buttonStyle(ExamSubmitStyle()).disabled(store.essay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isGrading || isRecognizing).keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("handInEssay")
            }.padding(.horizontal, 32).frame(height: 62)
            Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
            HSplitView {
                question.frame(minWidth: 250, idealWidth: 330, maxWidth: 440)
                answer.frame(minWidth: 490, maxWidth: .infinity)
            }.padding(.horizontal, 24).padding(.vertical, 28)
        }.background(.white).foregroundStyle(WB.ink)
            .overlay {
                if isRecognizing {
                    Color.white.opacity(0.96).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().controlSize(.regular)
                        Text("正在识别手写稿").font(.system(size: 20, weight: .medium))
                        Text("识别后请逐页校对，再确认评分。").font(.system(size: 13)).foregroundStyle(WB.secondary)
                        Button("取消") { onCancelOCR() }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
    }
    @ViewBuilder private var timer: some View {
        if examTimeLimit {
            let limit = TimeInterval(store.task.suggestedMinutes * 60), remaining = limit - store.elapsed
            let text = remaining >= 0 ? "剩余 \(WritingStore.clock(remaining))" : "超时 +\(WritingStore.clock(-remaining))"
            Label(text, systemImage: remaining >= 0 ? "timer" : "exclamationmark.circle").font(.system(size: 14, weight: remaining < 300 ? .medium : .regular)).monospacedDigit()
                .foregroundStyle(remaining < 300 ? WB.amber : WB.ink)
                .help("考试限时 \(store.task.suggestedMinutes) 分钟 · 已用 \(store.timerText)")
                .accessibilityLabel(remaining >= 0 ? "剩余时间 \(WritingStore.clock(remaining))" : "已超时 \(WritingStore.clock(-remaining))")
        } else {
            Label(store.timerText, systemImage: "clock").font(.system(size: 14)).monospacedDigit().foregroundStyle(WB.ink).accessibilityLabel("作答用时 \(store.timerText)")
        }
    }
    private var question: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("试题").font(.system(size: 12, weight: .medium)).foregroundStyle(WB.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(QuestionText.attributed(store.question)).font(.system(size: 15)).lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if let data = store.questionImage, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("题目原图") }
                }
            }.scrollIndicators(.hidden)
        }.padding(.leading, 8).padding(.trailing, 28)
    }
    private var answer: some View {
        let sheet = store.task.answerSheet
        return VStack(alignment: .leading, spacing: sheet == nil ? 16 : 8) {
            HStack(alignment: .firstTextBaseline) {
                if let sheet {
                    Text(sheet.section).font(.system(size: 12, weight: .medium)).foregroundStyle(WB.ink)
                } else {
                    Text(store.task.exam == .ielts ? "Answer" : "答题区").font(.system(size: 12, weight: .medium)).foregroundStyle(WB.secondary)
                }
                Spacer()
                if showLiveWordCount { Text(store.task.targetLanguage == "Simplified Chinese" ? "\(store.essay.count) 字符" : "\(store.words) words").font(.system(size: 12)).monospacedDigit().foregroundStyle(WB.secondary).accessibilityIdentifier("liveWordCount") }
                if let sheet { Text(sheet.sheet).font(.system(size: 11)).foregroundStyle(AnswerSheet.magenta) }
            }
            PlainTextEditor(text: $store.essay, fontSize: editorFontSize, fontStyle: editorFont, editable: true, identifier: "essayEditor",
                            ruled: sheet != nil || (editorRuled && store.task.exam != .ielts), sheetNumber: sheet?.number, requestFocus: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Rectangle().stroke(sheet == nil ? Color.black.opacity(0.12) : Color.black.opacity(0.85), lineWidth: sheet == nil ? 0.75 : 1.2))
                .padding(sheet == nil ? 0 : 14)
                .overlay { if sheet != nil { AnswerSheet.CornerMarks() } }
            HStack {
                if sheet != nil {
                    Text("请在答题区域内作答，超出黑色矩形边框限定区域的答案无效").font(.system(size: 10)).foregroundStyle(AnswerSheet.magenta.opacity(0.85))
                    Text("·").foregroundStyle(WB.secondary.opacity(0.5))
                }
                Text(store.saveStatus).font(.system(size: 10)).foregroundStyle(WB.secondary.opacity(0.7))
                Spacer()
                Button("导入手写稿", action: onImport).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WB.secondary).disabled(store.isGrading || isRecognizing).accessibilityIdentifier("importHandwritten")
            }
        }.padding(.leading, 28).padding(.trailing, 8)
    }
}
/// Visual cues from the printed 考研 answer sheet.
enum AnswerSheet {
    static let magenta = Color(red: 0.86, green: 0.27, blue: 0.52)
    /// Solid registration squares at the sheet's corners.
    struct CornerMarks: View {
        var body: some View {
            VStack {
                HStack { mark; Spacer(); mark }
                Spacer()
                HStack { mark; Spacer(); mark }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        private var mark: some View { Rectangle().fill(Color.black.opacity(0.85)).frame(width: 8, height: 8) }
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

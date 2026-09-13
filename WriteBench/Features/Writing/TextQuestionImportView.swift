import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TextQuestionImportView: View {
    @Environment(\.dismiss) private var dismiss
    let task: WritingTask
    let hasAnswer: Bool
    var onImport: (String, String) -> Bool
    @State private var title = ""
    @State private var text = ""
    @State private var error: String?
    @State private var readingFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("导入题目文字").font(.system(size: 23, weight: .semibold))
                    Text(task.fullTitle).font(.system(size: 12)).foregroundStyle(WB.secondary)
                }
                Spacer()
                IconButton(symbol: "xmark", help: "取消导入") { dismiss() }
            }

            TextField("题目名称（选填）", text: $title)
                .textFieldStyle(.plain).font(.system(size: 14))
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(WB.line))
                .accessibilityLabel("题目名称")

            ZStack(alignment: .topLeading) {
                PlainTextEditor(text: $text, fontSize: 15, identifier: "textQuestionImportEditor", requestFocus: true)
                if text.isEmpty {
                    Text("在这里粘贴或输入完整题目…\n请包含作答要求、原文或必要的图表数据。")
                        .font(.system(size: 14)).foregroundStyle(WB.secondary.opacity(0.8))
                        .lineSpacing(7).padding(.horizontal, 13).padding(.vertical, 15)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WB.line))

            HStack(spacing: 12) {
                Button { importFile() } label: { Label("从文本文件导入", systemImage: "doc.text") }
                    .buttonStyle(QuietButtonStyle()).disabled(readingFile)
                if readingFile { ProgressView().controlSize(.small) }
                else { Text(".txt / .md · UTF-8 / UTF-16").font(.system(size: 11)).foregroundStyle(WB.secondary) }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(WB.amber).fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Text(hasAnswer ? "确认后替换当前题目，已有作答保留。" : "确认后填入当前题目并自动保存。")
                    .font(.system(size: 11)).foregroundStyle(WB.secondary)
                Spacer(minLength: 12)
                Button("取消") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button("确认导入") { confirm() }.buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(readingFile || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("confirmTextQuestionImport")
            }
        }.padding(28).frame(width: 660, height: 590).background(WB.canvas).foregroundStyle(WB.ink)
            .onChange(of: text) { _, _ in error = nil }
    }

    private func importFile() {
        readingFile = true
        Task {
            defer { readingFile = false }
            let panel = NSOpenPanel()
            panel.title = "导入题目文字"
            panel.prompt = "导入"
            panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            guard await panel.begin() == .OK, let url = panel.url else { return }
            do {
                let imported = try await QuestionTextReader().read(url)
                text = imported
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = url.deletingPathExtension().lastPathComponent }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    private func confirm() {
        do {
            let prompt = try QuestionTextReader.validated(text)
            if onImport(prompt, title) { dismiss() }
            else { error = "导入未保存，请稍后重试。" }
        } catch { self.error = error.localizedDescription }
    }
}

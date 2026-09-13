import SwiftUI

struct OCRConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @State var imported: OCRImport
    var initialQuestion: String
    var allowEssayImport = true
    var onConfirm: (OCRPurpose, String, String, [Data]) -> Void
    @State private var selected = 0
    @State private var verified = false
    @State private var question = ""
    private var essay: String { imported.pages.map(\.text).joined(separator: "\n\n") }
    private var valid: Bool {
        (allowEssayImport || imported.purpose == .question) && verified && !imported.pages.isEmpty && (imported.purpose == .question ? !essay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : WordCounter.count(essay) > 0 && !(imported.purpose == .combined ? question : initialQuestion).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("先校对，再评分。").font(.system(size: 23, weight: .semibold))
                    Text("OCR 可能误认字母、标点和换行。请让右侧文字准确反映你的原稿。").font(.system(size: 12)).foregroundStyle(WB.secondary)
                }
                Spacer()
                IconButton(symbol: "xmark", help: "Cancel OCR import") { dismiss() }
            }.padding(24)
            HStack {
                Picker("图片内容", selection: $imported.purpose) { ForEach(allowEssayImport ? OCRPurpose.allCases : [.question]) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width: 350)
                Spacer()
                Text("\(imported.pages.count) 页 · 仅在本机识别").font(.system(size: 12)).foregroundStyle(WB.secondary)
            }.padding(.horizontal, 24).padding(.bottom, 18)
            HSplitView {
                VStack(spacing: 12) {
                    HStack {
                        Text("ORIGINAL").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                        Spacer()
                        Text(imported.pages[selected].name).font(.system(size: 11)).lineLimit(1)
                    }.foregroundStyle(WB.secondary)
                    ScrollView([.vertical, .horizontal]) {
                        if let image = NSImage(data: imported.pages[selected].imageData) {
                            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 440).padding(10).accessibilityLabel("Original page \(selected + 1)")
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(WB.tint.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    HStack(spacing: 8) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(imported.pages.indices, id: \.self) { index in
                                    Button("\(index + 1)") { selected = index }.buttonStyle(QuietButtonStyle()).overlay(RoundedRectangle(cornerRadius: 11).stroke(selected == index ? WB.blue : .clear))
                                }
                            }
                        }.scrollIndicators(.hidden).frame(height: 36)
                        Spacer(minLength: 0)
                        IconButton(symbol: "arrow.left", help: "Move page earlier") { movePage(-1) }.disabled(selected == 0)
                        IconButton(symbol: "arrow.right", help: "Move page later") { movePage(1) }.disabled(selected == imported.pages.count - 1)
                    }
                }.padding(20).frame(minWidth: 330, idealWidth: 460)
                VStack(alignment: .leading, spacing: 12) {
                    Text(imported.purpose == .question ? "QUESTION TEXT" : "ESSAY TEXT · PAGE \(selected + 1)").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(WB.secondary)
                    if imported.purpose == .combined {
                        Text("将题目移到下方题目框，作文框只保留你的作答。").font(.system(size: 12)).foregroundStyle(WB.blue)
                        PlainTextEditor(text: $question, fontSize: 13, identifier: "ocrQuestionEditor").frame(height: 115).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(WB.line))
                    }
                    if imported.purpose == .question || imported.purpose == .combined { Text("含图表的题目，请在文字中补充数据和图示含义；评审读取的是你确认的文字。").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                    if let warning = imported.pages[selected].warning { Label(warning, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(WB.amber) }
                    PlainTextEditor(text: Binding(get: { imported.pages[selected].text }, set: { imported.pages[selected].text = $0; verified = false }), identifier: "ocrEssayEditor")
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(WB.line))
                    Text("\(WordCounter.count(essay)) words across all pages").font(.system(size: 11)).foregroundStyle(WB.secondary)
                }.padding(20).frame(minWidth: 380, idealWidth: 470)
            }
            HStack {
                Toggle("我已逐页核对文字，已修正识别错误", isOn: $verified).font(.system(size: 12)).toggleStyle(.checkbox)
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(QuietButtonStyle())
                Button(imported.purpose == .question ? "确认并填入题目" : "Confirm & Grade") {
                    let purpose = imported.purpose
                    let confirmedQuestion = purpose == .question ? essay : purpose == .combined ? question : initialQuestion
                    onConfirm(purpose, confirmedQuestion, purpose == .question ? "" : essay, imported.pages.map(\.imageData))
                    dismiss()
                }.buttonStyle(PrimaryButtonStyle()).disabled(!valid)
            }.padding(22).background(.white)
        }.frame(minWidth: 900, idealWidth: 1040, minHeight: 680, idealHeight: 780).background(WB.canvas).foregroundStyle(WB.ink)
            .onChange(of: imported.purpose) { _, _ in verified = false }
            .onChange(of: question) { _, _ in verified = false }
    }
    private func movePage(_ direction: Int) { let next = selected + direction; guard imported.pages.indices.contains(next) else { return }; imported.pages.swapAt(selected, next); selected = next; verified = false }
}

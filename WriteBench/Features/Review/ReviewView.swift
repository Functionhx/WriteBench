import SwiftUI
import SwiftData

struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: EssaySession
    var onRewrite: (EssaySession) -> Void
    @State private var didCopyReview = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(session.task.isTranslation ? "Translation review" : "Writing review", systemImage: "checkmark.seal").font(.system(size: 16, weight: .semibold)).labelStyle(BlueIconLabelStyle())
                Spacer()
                Text(session.task.fullTitle).foregroundStyle(WB.secondary)
                Button {
                    guard let text = ReviewTextExporter.text(for: session) else { return }
                    NSPasteboard.general.clearContents()
                    didCopyReview = NSPasteboard.general.setString(text, forType: .string)
                    copyFeedbackTask?.cancel()
                    copyFeedbackTask = Task {
                        do { try await Task.sleep(for: .seconds(2)); didCopyReview = false } catch { }
                    }
                } label: {
                    Label(didCopyReview ? "Copied" : "Copy", systemImage: didCopyReview ? "checkmark" : "doc.on.doc")
                }.buttonStyle(QuietButtonStyle()).disabled(session.report == nil)
                    .help("复制评分、评语和修改建议").accessibilityLabel("复制评审结果")
                IconButton(symbol: "xmark", help: "Close review") { dismiss() }
            }.padding(22).background(.white)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let report = session.report {
                        if report.isDemo {
                            Label("演示模式 · 示例分数，不代表真实写作水平，不计入统计。", systemImage: "info.circle").font(.system(size: 13)).foregroundStyle(WB.secondary).padding(15).frame(maxWidth: .infinity, alignment: .leading).background(WB.tint, in: RoundedRectangle(cornerRadius: 12))
                        }
                        scoreCard(report)
                        Card {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("评阅结论").font(.system(size: 18, weight: .semibold))
                                Text(report.conclusion).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled)
                                Text("采用中位分评审的结论；下方保留三位评审的独立意见。").font(.system(size: 11)).foregroundStyle(WB.secondary)
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 22) {
                                feedback("写得好的地方", symbol: "checkmark.circle", color: WB.green, items: report.strengths, empty: "这份评阅未单列优点，可结合评审意见查看。")
                                feedback("不足的地方", symbol: "exclamationmark.circle", color: WB.amber, items: report.weaknesses, empty: "评审未单列主要不足，请结合评分维度查看。")
                                feedback("下一稿怎么改", symbol: "pencil.line", color: WB.blue, items: report.improvements, empty: "请参考下方逐句修改与改进版本。")
                            }
                        }
                        HStack(spacing: 14) {
                            ForEach(report.reviewers) { reviewer in
                                Card(padding: 18) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack { Text(reviewer.judge.title).font(.system(size: 13, weight: .semibold)); Spacer(); Image(systemName: "checkmark.circle.fill").foregroundStyle(WB.green) }
                                        Text(reviewer.response.score.scoreText).font(.system(size: 29, weight: .semibold, design: .rounded))
                                        Text(reviewer.judge.role).font(.system(size: 11)).foregroundStyle(WB.secondary)
                                        Text(reviewer.provider?.title ?? reviewer.model).font(.system(size: 10)).foregroundStyle(WB.secondary)
                                        Text("\(reviewer.model) · \(reviewer.reasoningEffort?.uppercased() ?? "")").font(.system(size: 10)).foregroundStyle(WB.secondary).lineLimit(1).help(reviewer.model)
                                    }
                                }
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 20) {
                                HStack { Text("At a glance").font(.system(size: 17, weight: .semibold)); Spacer(); Text("Diagnostic scale · / 10").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                                dimension(session.task.isTranslation ? "Meaning & completeness" : "Task Completion", value: report.dimension(\.taskCompletion))
                                dimension("Language", value: report.dimension(\.language))
                                dimension("Coherence", value: report.dimension(\.coherence))
                                dimension("Register", value: report.dimension(\.register))
                                if session.task.exam == .ielts { Text("These are practice diagnostics. The examiner’s overall band also considers lexical resource and grammatical range; this is a single-task estimate.").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 18) {
                                Text("Examiner comments").font(.system(size: 18, weight: .semibold))
                                ForEach(report.reviewers) { reviewer in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(reviewer.judge.title) · \(reviewer.judge.role)").font(.system(size: 12, weight: .semibold)).foregroundStyle(WB.blue)
                                        Text(reviewer.response.summary).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                                        ForEach(reviewer.response.majorErrors, id: \.self) { Text("• " + $0).font(.system(size: 13)).foregroundStyle(WB.amber) }
                                        ForEach(reviewer.response.minorErrors, id: \.self) { Text("• " + $0).font(.system(size: 12)).foregroundStyle(WB.secondary) }
                                    }
                                }
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack { Text("Sentence corrections").font(.system(size: 18, weight: .semibold)); Spacer(); Text("\(report.corrections.count) suggestions").font(.system(size: 12)).foregroundStyle(WB.secondary) }
                                if report.corrections.isEmpty { Text(report.isDemo ? "演示只包含少量本地示例规则。真实逐句修改请使用 DeepSeek 评分。" : "评审未标注逐句修改。请结合上方评语检查任务完成情况。").font(.system(size: 14)).foregroundStyle(WB.secondary) }
                                ForEach(report.corrections) { correction in CorrectionRow(correction: correction) }
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack { Text(session.task.isTranslation ? "参考改译" : "Improved version").font(.system(size: 18, weight: .semibold)); Spacer(); Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.correctedEssay, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(QuietButtonStyle()) }
                                Text(session.task.isTranslation ? "结合原文检查译义与表达，参考译文并非唯一正确答案。" : "Language reviewer’s suggested revision").font(.system(size: 12)).foregroundStyle(WB.secondary)
                                Text(session.correctedEssay).font(.system(size: 15)).lineSpacing(7).textSelection(.enabled)
                            }
                        }
                        Card {
                            DisclosureGroup("Original question & essay") {
                                VStack(alignment: .leading, spacing: 20) {
                                    Text(session.question).foregroundStyle(WB.secondary)
                                    if let data = session.questionImage, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 260) }
                                    Text(session.originalEssay)
                                    if let data = session.sourceImages, let pages = try? JSONDecoder().decode([Data].self, from: data) {
                                        ForEach(pages.indices, id: \.self) { index in
                                            if let image = NSImage(data: pages[index]) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 350).accessibilityLabel("Handwritten page \(index + 1)") }
                                        }
                                    }
                                }.font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).padding(.top, 16)
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Rewrite").font(.system(size: 18, weight: .semibold))
                                Text("把反馈写进下一稿。重写将在沉浸式答题页进行，草稿自动保存。").font(.system(size: 13)).foregroundStyle(WB.secondary)
                                if !session.finalRewrite.isEmpty { Text(session.finalRewrite).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled) }
                                HStack { Spacer(); Button(session.finalRewrite.isEmpty ? "开始重写" : "继续重写") { onRewrite(session) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("startRewrite") }
                            }
                        }
                        Text("\(session.task.targetLanguage == "Simplified Chinese" ? "\(session.originalEssay.count) characters" : "\(session.wordCount) words") · \(Int(session.writingDuration / 60)) min · \(session.inputMode.capitalized) · \(session.date.formatted(date: .abbreviated, time: .shortened))\nRubric \(session.rubricVersion) · Prompt \(session.graderPromptVersion) · \(session.modelName)").font(.system(size: 10)).foregroundStyle(WB.secondary).textSelection(.enabled)
                    } else {
                        EmptyState(symbol: "exclamationmark.triangle", title: "Unable to read this review", detail: "The saved review data is invalid. Your original question and essay are preserved below.")
                        Card { VStack(alignment: .leading, spacing: 20) { Text(session.question).foregroundStyle(WB.secondary); Text(session.originalEssay) }.textSelection(.enabled) }
                    }
                }.padding(28)
            }
        }.frame(minWidth: 820, idealWidth: 960, minHeight: 620, idealHeight: 840).background(WB.canvas).foregroundStyle(WB.ink)
    }
    private func scoreCard(_ report: GradingReport) -> some View {
        Card(padding: 28) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(report.isDemo ? "DEMO " : "")WRITING SCORE").font(.system(size: 11, weight: .semibold)).tracking(1.6).foregroundStyle(WB.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(report.finalScore.scoreText).font(.system(size: 62, weight: .semibold, design: .rounded)).foregroundStyle(WB.blue)
                        Text("/ \(Int(session.task.maxScore))").font(.system(size: 24)).foregroundStyle(WB.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 13) {
                    Label(report.confidence.title, systemImage: report.confidence == .low ? "exclamationmark.circle" : "checkmark.shield").font(.system(size: 14, weight: .medium)).foregroundStyle(report.confidence == .low ? WB.amber : WB.green).padding(.horizontal, 14).padding(.vertical, 9).background((report.confidence == .low ? WB.amber : WB.green).opacity(0.08), in: Capsule())
                    Text("Median of 3 independent reviewers").font(.system(size: 12)).foregroundStyle(WB.secondary)
                    Text("Reviewer spread: \(report.spread.scoreText)").font(.system(size: 11)).foregroundStyle(WB.secondary)
                    if report.confidence == .low { Text("Reviewer disagreement · inspect each review").font(.system(size: 11)).foregroundStyle(WB.amber) }
                }
            }
        }
    }
    private func dimension(_ title: String, value: Double) -> some View {
        HStack(spacing: 20) {
            Text(title).font(.system(size: 13)).frame(width: 125, alignment: .leading)
            GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(WB.tint); Capsule().fill(WB.blue.opacity(0.7)).frame(width: proxy.size.width * value / 10) } }.frame(height: 6)
            Text(value.scoreText).font(.system(size: 13, weight: .medium)).monospacedDigit().frame(width: 35, alignment: .trailing)
        }
    }
    private func feedback(_ title: String, symbol: String, color: Color, items: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
            if items.isEmpty { Text(empty).font(.system(size: 12)).foregroundStyle(WB.secondary) }
            ForEach(items, id: \.self) { Text("• " + $0).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled) }
        }
    }
}
struct CorrectionRow: View {
    let correction: Correction
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(correction.category.rawValue).font(.system(size: 11, weight: .semibold)).foregroundStyle(WB.blue); if correction.severity == .major { Text("High priority").font(.system(size: 10)).foregroundStyle(WB.amber) } }
            Text(correction.original).font(.system(size: 14)).foregroundStyle(WB.secondary).strikethrough(color: WB.secondary.opacity(0.4))
            Label(correction.corrected, systemImage: "arrow.turn.down.right").font(.system(size: 14, weight: .medium)).foregroundStyle(WB.ink)
            Text(correction.explanation).font(.system(size: 12)).foregroundStyle(WB.secondary).lineSpacing(4)
        }.textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(WB.canvas, in: RoundedRectangle(cornerRadius: 12))
    }
}

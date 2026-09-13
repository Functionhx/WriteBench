import SwiftUI

struct BackgroundGradingView: View {
    @Bindable var job: BackgroundGradingJob
    var onCancel: () -> Void
    var onDismiss: () -> Void
    var onReview: (EssaySession) -> Void
    @State private var showingDetails = false
    @State private var pendingReview: EssaySession?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { clock in
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    if job.phase.isRunning { ProgressView().controlSize(.small) }
                    else { Image(systemName: job.phase == .completed ? "checkmark.circle.fill" : "info.circle").foregroundStyle(job.phase == .completed ? WB.green : WB.amber) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.phase.title).font(.system(size: 13, weight: .semibold))
                        Text("\(job.submission.input.task.fullTitle) · \(job.submission.countText)").font(.system(size: 11)).foregroundStyle(WB.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("\(job.completedCount)/3 位完成 · \(job.elapsedText(at: clock.date))").font(.system(size: 11)).monospacedDigit().foregroundStyle(WB.secondary)
                    Button(job.phase.isRunning ? "查看进度" : "评阅详情") { showingDetails = true }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("showGradingProgress")
                    if job.phase.isRunning {
                        Button("取消", action: onCancel).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WB.secondary).disabled(job.phase == .cancelling)
                    } else {
                        if let session = job.session { Button("查看结果") { onReview(session) }.buttonStyle(QuietButtonStyle()).foregroundStyle(WB.blue).accessibilityIdentifier("openBackgroundReview") }
                        IconButton(symbol: "xmark", help: "收起评阅状态", action: onDismiss)
                    }
                }
                ProgressView(value: Double(job.completedCount), total: 3).tint(WB.blue)
                    .accessibilityLabel("已完成 \(job.completedCount) 位评审，共 3 位")
            }.padding(.horizontal, 32).padding(.vertical, 12).background(WB.tint.opacity(0.65))
        }
        .sheet(isPresented: $showingDetails, onDismiss: {
            if let session = pendingReview { pendingReview = nil; onReview(session) }
        }) {
            GradingProgressView(job: job, onCancel: onCancel) { session in pendingReview = session; showingDetails = false }
        }
    }
}

struct GradingProgressView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var job: BackgroundGradingJob
    var onCancel: () -> Void
    var onReview: (EssaySession) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(job.phase.title).font(.system(size: 22, weight: .semibold))
                    Text("\(job.submission.input.task.fullTitle) · 已交卷 \(job.submission.countText)").font(.system(size: 12)).foregroundStyle(WB.secondary)
                }
                Spacer()
                IconButton(symbol: "xmark", help: "关闭进度窗口") { dismiss() }
            }.padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(job.phase == .completed ? "三位独立评审已完成，完整结论与总分已保存到历史。" : job.phase == .failed || job.phase == .cancelled ? "本次未生成总分。已收到的评语片段不作为最终评分，提交原稿保留在下方。" : "进度按实际完成的评审计数。下方为实时评语，总分将在三位评审全部完成后生成。").font(.system(size: 12)).foregroundStyle(WB.secondary)
                    ForEach(Judge.allCases) { judge in
                        Card(padding: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(judge.title).font(.system(size: 14, weight: .semibold))
                                    Text(job.configuration?.provider(for: judge).title ?? judge.role).font(.system(size: 11)).foregroundStyle(WB.secondary)
                                    Spacer()
                                    Text(job.judges[judge]?.rawValue ?? "等待").font(.system(size: 11)).foregroundStyle(job.judges[judge] == .completed ? WB.green : WB.secondary)
                                    if let result = job.results[judge] { Text("\(result.response.score.scoreText) / \(Int(job.submission.input.task.maxScore))").font(.system(size: 13, weight: .semibold)).foregroundStyle(WB.blue) }
                                }
                                Text(job.previews[judge].flatMap { $0.isEmpty ? nil : $0 } ?? placeholder(for: judge))
                                    .font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if let detail = job.detail { Label(detail, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(WB.amber).textSelection(.enabled) }
                    DisclosureGroup("本次提交的题目与作答") {
                        VStack(alignment: .leading, spacing: 16) { Text(job.submission.input.question).foregroundStyle(WB.secondary); Text(job.submission.input.essay) }
                            .font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    }.font(.system(size: 12))
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            HStack {
                Text("可切换页面或最小化窗口；退出应用会中断未完成评阅。").font(.system(size: 11)).foregroundStyle(WB.secondary)
                Spacer()
                if job.phase.isRunning {
                    Button("取消评阅", action: onCancel).buttonStyle(QuietButtonStyle()).disabled(job.phase == .cancelling)
                    Button("后台继续") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.cancelAction)
                } else if let session = job.session {
                    Button("查看结果") { onReview(session) }.buttonStyle(PrimaryButtonStyle())
                } else { Button("返回") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction) }
            }.padding(24).background(.white)
        }.frame(width: 760, height: 670).background(WB.canvas).foregroundStyle(WB.ink)
    }
    private func placeholder(for judge: Judge) -> String {
        switch job.judges[judge] {
        case .cancelled: "该评审已停止。"
        case .failed: "该评审未返回完整评阅。"
        case .waiting: "正在检查连接，尚未发起评阅。"
        default: job.configuration?.provider(for: judge) == .codex ? "Codex 正在独立评阅，完成后显示评语。" : "等待评审返回评语。MAX 思考可能需要数分钟。"
        }
    }
}

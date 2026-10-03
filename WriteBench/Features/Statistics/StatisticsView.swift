import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    enum ModeFilter: String, CaseIterable, Identifiable { case all = "全部评阅", full = "三评", quick = "快速单评"; var id: String { rawValue } }
    private struct Point: Identifiable {
        let session: EssaySession
        let report: GradingReport?
        var id: UUID { session.id }
        var date: Date { session.date }
        var percent: Double { session.finalScore / session.task.maxScore * 100 }
        var mode: GradingMode { report?.gradingMode ?? .full }
    }
    private struct DimensionPoint: Identifiable {
        let id = UUID()
        let date: Date
        let name: String
        let value: Double
    }
    private static let dimensionColors: KeyValuePairs<String, Color> = ["任务 / 译义": WB.blue, "语言": WB.green, "连贯": WB.amber, "语域": Color(red: 0.5, green: 0.38, blue: 0.78)]

    @Query(sort: \EssaySession.date) private var sessions: [EssaySession]
    @State private var task: WritingTask?
    @State private var mode: ModeFilter = .all
    private var points: [Point] {
        sessions.filter { !$0.isDemo && (task == nil || $0.subtype == task?.rawValue) }.map { Point(session: $0, report: $0.report) }
            .filter { mode == .all || ($0.mode == .quick) == (mode == .quick) }
    }
    var body: some View {
        let points = points
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(title: "Small steps. Visible progress.", subtitle: "Statistics · 看自己和自己比：趋势、变化与常犯的问题。")
                    Spacer()
                    Picker("评阅方式", selection: $mode) { ForEach(ModeFilter.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 110)
                    Picker("Task", selection: $task) { Text("All tasks").tag(Optional<WritingTask>.none); ForEach(WritingTask.allCases) { Text($0.fullTitle).tag(Optional($0)) } }.frame(width: 210)
                }
                HStack(spacing: 16) {
                    metric("Essays", value: "\(points.count)", symbol: "doc.text", note: "Completed reviews")
                    metric("Average score", value: points.isEmpty ? "—" : String(format: "%.0f%%", average(points)), symbol: "chart.line.uptrend.xyaxis", note: "Normalized to each task’s maximum")
                    recentChange(points)
                    metric("Writing time", value: points.isEmpty ? "—" : String(format: "%.1f min", points.reduce(0) { $0 + $1.session.writingDuration / 60 } / Double(points.count)), symbol: "stopwatch", note: "Average per essay")
                }
                scoreTrend(points)
                dimensionTrend(points)
                patterns(points)
                usage(points)
                Text("分数换算为各题型满分的百分比，便于跨题型比较自己的变化；IELTS 单项任务分不是完整 Writing 成绩。快速单评只有一位评审，与三评混看时请留意。同一篇中重复的修改只计一次。")
                    .font(.system(size: 11)).foregroundStyle(WB.secondary).lineSpacing(4)
            }.padding(32)
        }
    }
    private func average(_ points: some Collection<Point>) -> Double { points.isEmpty ? 0 : points.reduce(0) { $0 + $1.percent } / Double(points.count) }
    @ViewBuilder private func recentChange(_ points: [Point]) -> some View {
        let window = min(5, points.count / 2)
        if window >= 2 {
            let recent = average(points.suffix(window)), earlier = average(points.dropLast(window).suffix(window)), delta = recent - earlier
            metric("Recent change", value: String(format: "%@%.1f", delta >= 0 ? "+" : "", delta), symbol: delta >= 0 ? "arrow.up.right" : "arrow.down.right",
                   note: "近 \(window) 篇比之前 \(window) 篇 · 百分点", tint: delta > 0 ? WB.green : delta < 0 ? WB.amber : WB.blue)
        } else {
            metric("Recent change", value: "—", symbol: "arrow.up.right", note: "至少 4 篇后显示近期变化")
        }
    }
    private func scoreTrend(_ points: [Point]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text("Score trend").font(.system(size: 18, weight: .semibold)); Spacer(); Text("% of task maximum · 虚线为最近 3 篇平均").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                if points.isEmpty { EmptyState(symbol: "chart.xyaxis.line", title: "Progress needs a first point.", detail: "Complete a review to start your score trend.") }
                else {
                    Chart {
                        ForEach(points) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Score %", point.percent), series: .value("Series", "得分"))
                                .foregroundStyle(WB.blue.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1.5))
                            PointMark(x: .value("Date", point.date), y: .value("Score %", point.percent))
                                .foregroundStyle(point.mode == .quick ? WB.blue.opacity(0.4) : WB.blue).symbolSize(point.mode == .quick ? 28 : 40)
                                .accessibilityLabel("\(point.session.task.fullTitle), \(point.date.formatted(date: .abbreviated, time: .omitted))\(point.mode == .quick ? ", 快速单评" : "")")
                                .accessibilityValue("\(point.session.finalScore.scoreText) out of \(Int(point.session.task.maxScore))")
                        }
                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            LineMark(x: .value("Date", point.date), y: .value("Score %", average(points[max(0, index - 2)...index])), series: .value("Series", "平均"))
                                .foregroundStyle(WB.green).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        }
                    }.chartYScale(domain: 0...100).chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in AxisGridLine().foregroundStyle(WB.line); AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } } } }.frame(height: 265)
                }
            }
        }
    }
    private func dimensionTrend(_ points: [Point]) -> some View {
        let names = Self.dimensionColors.map(\.key)
        let data = points.flatMap { point -> [DimensionPoint] in
            guard let report = point.report else { return [] }
            let values = [report.dimension(\.taskCompletion), report.dimension(\.language), report.dimension(\.coherence), report.dimension(\.register)]
            return zip(names, values).map { DimensionPoint(date: point.date, name: $0.0, value: $0.1) }
        }
        return Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Dimensions").font(.system(size: 18, weight: .semibold)); Spacer(); Text("诊断分 / 10 · 三评取中位数").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                if data.isEmpty { Text("完成评阅后显示各维度的变化。").font(.system(size: 14)).foregroundStyle(WB.secondary).padding(.vertical, 20) }
                else {
                    Chart(data) { item in
                        LineMark(x: .value("Date", item.date), y: .value("Score", item.value)).foregroundStyle(by: .value("维度", item.name)).interpolationMethod(.monotone)
                        PointMark(x: .value("Date", item.date), y: .value("Score", item.value)).foregroundStyle(by: .value("维度", item.name)).symbolSize(18)
                    }.chartForegroundStyleScale(Self.dimensionColors).chartYScale(domain: 0...10).chartLegend(position: .top, alignment: .leading).frame(height: 230)
                }
            }
        }
    }
    private func patterns(_ points: [Point]) -> some View {
        let categories = MistakeCategory.allCases.map { category in
            (category: category, count: points.reduce(0) { $0 + ($1.report?.corrections.filter { $0.category == category }.count ?? 0) })
        }.filter { $0.count > 0 }.sorted { $0.count > $1.count }
        return Card {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Patterns to work on").font(.system(size: 18, weight: .semibold)); Spacer(); Text("在 Mistakes 中查看每类的近期变化").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                if categories.isEmpty { Text("Recurring correction categories will appear after your first review.").font(.system(size: 14)).foregroundStyle(WB.secondary).padding(.vertical, 20) }
                else {
                    Chart(categories, id: \.category) { item in BarMark(x: .value("Corrections", item.count), y: .value("Category", item.category.rawValue)).foregroundStyle(WB.blue.opacity(0.7)).cornerRadius(4).annotation(position: .trailing) { Text("\(item.count)").font(.system(size: 11)).foregroundStyle(WB.secondary) } }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }.frame(height: CGFloat(max(3, categories.count)) * 35)
                }
            }
        }
    }
    @ViewBuilder private func usage(_ points: [Point]) -> some View {
        let reports = points.compactMap(\.report)
        let durations = reports.compactMap(\.duration)
        let byProvider = GradingProvider.allCases.compactMap { provider -> (GradingProvider, TokenUsage)? in
            let usages = reports.flatMap(\.reviewers).filter { $0.provider == provider }.compactMap(\.usage)
            guard let first = usages.first else { return nil }
            return (provider, usages.dropFirst().reduce(first, +))
        }
        let costs = reports.compactMap { UsageCost.cost($0) }
        if !byProvider.isEmpty || !durations.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Review cost").font(.system(size: 18, weight: .semibold))
                    if !durations.isEmpty { usageRow("平均评阅用时", UsageCost.duration(durations.reduce(0, +) / Double(durations.count)) + " · \(durations.count) 次有记录") }
                    ForEach(byProvider, id: \.0) { provider, usage in usageRow(provider.title, UsageCost.summary(usage)) }
                    if !costs.isEmpty { usageRow("DeepSeek 估算", "合计 \(UsageCost.yuan(costs.reduce(0, +))) · 平均每篇 \(UsageCost.yuan(costs.reduce(0, +) / Double(costs.count)))") }
                    Text("1.5 之前的评阅没有用量记录。花费按设置中填写的 DeepSeek 价格估算；Codex 使用 ChatGPT 额度。").font(.system(size: 11)).foregroundStyle(WB.secondary)
                }
            }
        }
    }
    private func usageRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 16) { Text(title).font(.system(size: 12, weight: .medium)).frame(width: 140, alignment: .leading); Text(value).font(.system(size: 12)).foregroundStyle(WB.secondary).textSelection(.enabled) }
    }
    private func metric(_ title: String, value: String, symbol: String, note: String, tint: Color = WB.blue) -> some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text(title).font(.system(size: 13)).foregroundStyle(WB.secondary); Spacer(); Image(systemName: symbol).foregroundStyle(tint) }
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(tint == WB.blue ? WB.ink : tint).minimumScaleFactor(0.7).lineLimit(1)
                Text(note).font(.system(size: 10)).foregroundStyle(WB.secondary)
            }
        }
    }
}

import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query(sort: \EssaySession.date) private var sessions: [EssaySession]
    @State private var task: WritingTask?
    private var real: [EssaySession] { sessions.filter { !$0.isDemo && (task == nil || $0.subtype == task?.rawValue) } }
    private var average: Double { real.isEmpty ? 0 : real.reduce(0) { $0 + $1.finalScore / $1.task.maxScore * 100 } / Double(real.count) }
    private var averageMinutes: Double { real.isEmpty ? 0 : real.reduce(0) { $0 + $1.writingDuration / 60 } / Double(real.count) }
    private var categories: [(category: MistakeCategory, count: Int)] { MistakeCategory.allCases.map { category in (category, real.reduce(0) { $0 + ($1.report?.corrections.filter { $0.category == category }.count ?? 0) }) }.filter { $0.count > 0 }.sorted { $0.count > $1.count } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(title: "Small steps. Visible progress.", subtitle: "Statistics · A clearer picture of your writing practice.")
                    Spacer()
                    Picker("Task", selection: $task) { Text("All tasks").tag(Optional<WritingTask>.none); ForEach(WritingTask.allCases) { Text($0.fullTitle).tag(Optional($0)) } }.frame(width: 210)
                }
                HStack(spacing: 16) {
                    metric("Essays", value: "\(real.count)", symbol: "doc.text", note: "Completed reviews")
                    metric("Average score", value: real.isEmpty ? "—" : String(format: "%.0f%%", average), symbol: "chart.line.uptrend.xyaxis", note: "Normalized to each task’s maximum")
                    metric("Writing time", value: real.isEmpty ? "—" : String(format: "%.1f min", averageMinutes), symbol: "stopwatch", note: "Average per essay")
                }
                Card {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack { Text("Score trend").font(.system(size: 18, weight: .semibold)); Spacer(); Text("% of task maximum").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                        if real.isEmpty { EmptyState(symbol: "chart.xyaxis.line", title: "Progress needs a first point.", detail: "Complete a DeepSeek review to start your score trend. Demo results are excluded.") }
                        else {
                            Chart(real) { session in
                                LineMark(x: .value("Date", session.date), y: .value("Score %", session.finalScore / session.task.maxScore * 100)).foregroundStyle(WB.blue.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.linear)
                                PointMark(x: .value("Date", session.date), y: .value("Score %", session.finalScore / session.task.maxScore * 100)).foregroundStyle(WB.blue).symbolSize(40)
                                    .accessibilityLabel("\(session.task.fullTitle), \(session.date.formatted(date: .abbreviated, time: .omitted))")
                                    .accessibilityValue("\(session.finalScore.scoreText) out of \(Int(session.task.maxScore))")
                            }.chartYScale(domain: 0...100).chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in AxisGridLine().foregroundStyle(WB.line); AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } } } }.frame(height: 265)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Patterns to work on").font(.system(size: 18, weight: .semibold))
                        if categories.isEmpty { Text("Recurring correction categories will appear after your first review.").font(.system(size: 14)).foregroundStyle(WB.secondary).padding(.vertical, 20) }
                        else {
                            Chart(categories, id: \.category) { item in BarMark(x: .value("Corrections", item.count), y: .value("Category", item.category.rawValue)).foregroundStyle(WB.blue.opacity(0.7)).cornerRadius(4).annotation(position: .trailing) { Text("\(item.count)").font(.system(size: 11)).foregroundStyle(WB.secondary) } }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }.frame(height: CGFloat(max(3, categories.count)) * 35)
                        }
                    }
                }
                Text("Demo reviews are excluded. Scores are normalized to compare different task scales; an IELTS task score is not an overall Writing band. Duplicate reviewer corrections count once per essay.").font(.system(size: 11)).foregroundStyle(WB.secondary).lineSpacing(4)
            }.padding(32)
        }
    }
    private func metric(_ title: String, value: String, symbol: String, note: String) -> some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text(title).font(.system(size: 13)).foregroundStyle(WB.secondary); Spacer(); Image(systemName: symbol).foregroundStyle(WB.blue) }
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                Text(note).font(.system(size: 10)).foregroundStyle(WB.secondary)
            }
        }
    }
}

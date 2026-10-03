import SwiftUI
import SwiftData

struct MistakesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \EssaySession.date, order: .reverse) private var sessions: [EssaySession]
    @Query private var cards: [ReviewCard]
    var onOpen: (EssaySession) -> Void
    @State private var selected: MistakeCategory?
    @State private var hideMastered = true
    private struct Example: Identifiable {
        let session: EssaySession
        let correction: Correction
        let card: ReviewCard?
        var id: String { session.id.uuidString + correction.id }
        var mastered: Bool { card?.mastered == true }
    }
    private struct Trend { let recent: Double; let earlier: Double; let window: Int }
    var body: some View {
        let byKey = Dictionary(cards.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let real = sessions.filter { !$0.isDemo }
        let reports = real.map { ($0, $0.report?.corrections ?? []) }
        let examples = reports.flatMap { session, corrections in
            corrections.map { Example(session: session, correction: $0, card: byKey[ReviewCardSync.mistakeKey(session: session.id, correction: $0)]) }
        }
        let visible = examples.filter { !hideMastered || !$0.mastered }
        let categories = summarize(visible, reports)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionHeading(title: "Notice the pattern. Change it.", subtitle: "Mistakes · The feedback that matters, collected from your essays.")
                    Spacer()
                    Toggle("隐藏已掌握", isOn: $hideMastered).toggleStyle(.checkbox).font(.system(size: 12))
                }
                if examples.isEmpty {
                    Card { EmptyState(symbol: "text.badge.checkmark", title: "A little more aware, every time.", detail: "Corrections from real reviews appear here, grouped by category. Demo examples are excluded.") }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                        ForEach(categories, id: \.category) { item in
                            Button { selected = selected == item.category ? nil : item.category } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Text(item.category.rawValue).font(.system(size: 13, weight: .medium)); Spacer(); Text("\(item.count)").font(.system(size: 20, weight: .semibold, design: .rounded)) }
                                    if let trend = item.trend { trendLabel(trend) }
                                }.padding(18).foregroundStyle(selected == item.category ? WB.blue : WB.ink).background(selected == item.category ? WB.tint : .white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(selected == item.category ? WB.blue.opacity(0.65) : WB.line))
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack { Text(selected?.rawValue ?? "All corrections").font(.system(size: 18, weight: .semibold)); Spacer(); if selected != nil { Button("Show all") { selected = nil }.buttonStyle(QuietButtonStyle()) } }
                    ForEach(visible.filter { selected == nil || $0.correction.category == selected }) { item in
                        Card(padding: 18) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(item.session.task.fullTitle).font(.system(size: 12, weight: .medium))
                                    Text(item.session.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundStyle(WB.secondary)
                                    Spacer()
                                    Button { toggleMastered(item) } label: {
                                        Label(item.mastered ? "已掌握" : "标记已掌握", systemImage: item.mastered ? "checkmark.circle.fill" : "circle")
                                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(item.mastered ? WB.green : WB.secondary)
                                    Button("Open essay →") { onOpen(item.session) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WB.blue)
                                }
                                CorrectionRow(correction: item.correction).opacity(item.mastered ? 0.6 : 1)
                            }
                        }
                    }
                }
            }.padding(32)
        }
        .task { _ = try? ReviewCardSync.sync(context) }
    }
    private struct CategorySummary { let category: MistakeCategory; let count: Int; let trend: Trend? }
    private func summarize(_ visible: [Example], _ reports: [(EssaySession, [Correction])]) -> [CategorySummary] {
        var summaries: [CategorySummary] = []
        for category in MistakeCategory.allCases {
            let count = visible.filter { $0.correction.category == category }.count
            let change = trend(category, reports)
            if count > 0 || change != nil { summaries.append(CategorySummary(category: category, count: count, trend: change)) }
        }
        return summaries.sorted { $0.count == $1.count ? $0.category.rawValue < $1.category.rawValue : $0.count > $1.count }
    }
    /// Corrections per essay in the latest attempts versus the attempts before them.
    private func trend(_ category: MistakeCategory, _ reports: [(EssaySession, [Correction])]) -> Trend? {
        let window = min(5, reports.count / 2)
        guard window >= 2 else { return nil }
        func rate(_ slice: ArraySlice<(EssaySession, [Correction])>) -> Double { Double(slice.reduce(0) { $0 + $1.1.filter { $0.category == category }.count }) / Double(slice.count) }
        let recent = rate(reports.prefix(window)), earlier = rate(reports.dropFirst(window).prefix(window))
        return recent == 0 && earlier == 0 ? nil : Trend(recent: recent, earlier: earlier, window: window)
    }
    private func trendLabel(_ trend: Trend) -> some View {
        let fewer = trend.recent < trend.earlier, same = trend.recent == trend.earlier
        return Label("近 \(trend.window) 篇 \(String(format: "%.1f", trend.recent)) / 篇，之前 \(String(format: "%.1f", trend.earlier))",
                     systemImage: same ? "equal" : fewer ? "arrow.down.right" : "arrow.up.right")
            .font(.system(size: 10)).foregroundStyle(same ? WB.secondary : fewer ? WB.green : WB.amber)
    }
    private func toggleMastered(_ item: Example) {
        var card = item.card
        if card == nil {
            _ = try? ReviewCardSync.sync(context)
            let key = ReviewCardSync.mistakeKey(session: item.session.id, correction: item.correction)
            card = try? context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.key == key })).first
        }
        guard let card else { return }
        SpacedRepetition.setMastered(card, !card.mastered)
        try? context.save()
    }
}

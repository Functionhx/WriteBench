import SwiftUI
import SwiftData

struct MistakesView: View {
    @Query(sort: \EssaySession.date, order: .reverse) private var sessions: [EssaySession]
    var onOpen: (EssaySession) -> Void
    @State private var selected: MistakeCategory?
    private var examples: [(session: EssaySession, correction: Correction)] { sessions.filter { !$0.isDemo }.flatMap { session in (session.report?.corrections ?? []).map { (session, $0) } } }
    private var categories: [(category: MistakeCategory, count: Int)] { MistakeCategory.allCases.map { c in (c, examples.filter { $0.correction.category == c }.count) }.sorted { $0.count == $1.count ? $0.category.rawValue < $1.category.rawValue : $0.count > $1.count } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(title: "Notice the pattern. Change it.", subtitle: "Mistakes · The feedback that matters, collected from your essays.")
                if examples.isEmpty {
                    Card { EmptyState(symbol: "text.badge.checkmark", title: "A little more aware, every time.", detail: "Corrections from real reviews appear here, grouped by category. Demo examples are excluded.") }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(categories, id: \.category) { item in
                            Button { selected = selected == item.category ? nil : item.category } label: {
                                HStack { Text(item.category.rawValue).font(.system(size: 13, weight: .medium)); Spacer(); Text("\(item.count)").font(.system(size: 20, weight: .semibold, design: .rounded)) }.padding(18).foregroundStyle(selected == item.category ? WB.blue : WB.ink).background(selected == item.category ? WB.tint : .white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(selected == item.category ? WB.blue.opacity(0.65) : WB.line))
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack { Text(selected?.rawValue ?? "All corrections").font(.system(size: 18, weight: .semibold)); Spacer(); if selected != nil { Button("Show all") { selected = nil }.buttonStyle(QuietButtonStyle()) } }
                    ForEach(Array(examples.filter { selected == nil || $0.correction.category == selected }.enumerated()), id: \.offset) { _, item in
                        Card(padding: 18) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack { Text(item.session.task.fullTitle).font(.system(size: 12, weight: .medium)); Text(item.session.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundStyle(WB.secondary); Spacer(); Button("Open essay →") { onOpen(item.session) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WB.blue) }
                                CorrectionRow(correction: item.correction)
                            }
                        }
                    }
                }
            }.padding(32)
        }
    }
}

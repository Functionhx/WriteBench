import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(filter: #Predicate<EssaySession> { !$0.isDemo }, sort: \EssaySession.date, order: .reverse) private var sessions: [EssaySession]
    var onOpen: (EssaySession) -> Void
    @State private var search = ""
    @State private var exam: Exam?
    private var filtered: [EssaySession] { sessions.filter { (exam == nil || $0.exam == exam?.rawValue) && (search.isEmpty || $0.question.localizedCaseInsensitiveContains(search) || $0.originalEssay.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "Your writing, revisited.", subtitle: "History · Every essay, every review, every rewrite.")
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(WB.secondary)
                    TextField("Search questions and essays", text: $search).textFieldStyle(.plain)
                    Spacer()
                    Picker("Exam", selection: $exam) { Text("All exams").tag(Optional<Exam>.none); ForEach(Exam.allCases) { Text($0.title).tag(Optional($0)) } }.frame(width: 190)
                }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(WB.line))
                if filtered.isEmpty { Card { EmptyState(symbol: "clock.arrow.circlepath", title: sessions.isEmpty ? "Your next essay starts a story." : "No matching essays", detail: sessions.isEmpty ? "Submit your first essay to keep its score, feedback and rewrite here." : "Try another search or exam filter.") } }
                else {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            HStack { Text("DATE").frame(width: 130, alignment: .leading); Text("EXAM / QUESTION").frame(maxWidth: .infinity, alignment: .leading); Text("SCORE").frame(width: 90); Text("CONFIDENCE").frame(width: 110) }.font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(WB.secondary).padding(20)
                            ForEach(filtered) { session in
                                Button { onOpen(session) } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 5) { Text(session.date.formatted(date: .abbreviated, time: .omitted)); Text(session.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(WB.secondary) }.frame(width: 118, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 7) { HStack { Text(session.task.fullTitle).fontWeight(.medium); if session.isDemo { Text("DEMO").font(.system(size: 9, weight: .bold)).foregroundStyle(WB.blue).padding(4).background(WB.tint, in: RoundedRectangle(cornerRadius: 4)) } }; Text(session.question.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 12)).foregroundStyle(WB.secondary).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(session.finalScore.scoreText) / \(Int(session.task.maxScore))").font(.system(size: 14, weight: .semibold)).foregroundStyle(WB.blue).frame(width: 90)
                                        Text(session.confidence).font(.system(size: 12)).foregroundStyle(session.confidence == "Low" ? WB.amber : WB.green).frame(width: 96)
                                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(WB.secondary)
                                    }.font(.system(size: 13)).padding(20).contentShape(Rectangle()).overlay(alignment: .top) { Rectangle().fill(WB.line.opacity(0.55)).frame(height: 1) }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.padding(32)
        }
    }
}

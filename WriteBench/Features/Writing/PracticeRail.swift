import SwiftUI
import SwiftData

struct PracticeRail: View {
    @Query(sort: \EssaySession.date) private var sessions: [EssaySession]
    @Bindable var store: WritingStore
    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [WB.tint, WB.canvas], startPoint: .topLeading, endPoint: .bottomTrailing)
                Landscape()
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.92, blue: 0.7), Color(red: 1, green: 0.82, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 30, height: 30).offset(x: 235, y: 28)
                VStack(alignment: .leading, spacing: 13) {
                    Text(greeting + ",\nwriter.").font(.system(size: 24, weight: .semibold, design: .rounded)).lineSpacing(3)
                    Text("A little progress each day\nadds up to big results.").font(.system(size: 13)).foregroundStyle(WB.secondary).lineSpacing(5)
                }.padding(24)
            }.frame(height: 211).clipShape(RoundedRectangle(cornerRadius: 20))
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    Text("选择你的练习模式").font(.system(size: 14, weight: .semibold)).padding(.bottom, 1)
                    ForEach(Exam.allCases) { exam in
                        Button { store.select(exam.tasks[0]) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: exam.symbol).font(.system(size: 23, weight: .light)).frame(width: 48, height: 48).foregroundStyle(store.task.exam == exam ? WB.blue : WB.secondary).background(WB.tint, in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(exam.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(WB.ink)
                                    Text(exam.detail).font(.system(size: 10)).foregroundStyle(WB.secondary)
                                }
                                Spacer(minLength: 0)
                                if store.task.exam == exam { Image(systemName: "checkmark.circle.fill").foregroundStyle(WB.blue).font(.system(size: 17)) }
                            }.padding(8).background(store.task.exam == exam ? WB.tint.opacity(0.45) : WB.canvas.opacity(0.4), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(store.task.exam == exam ? WB.blue.opacity(0.7) : WB.line, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack { Text("今日练习").font(.system(size: 15, weight: .semibold)); Spacer(); Text("\(sessions.filter { !$0.isDemo && Calendar.current.isDateInToday($0.date) }.count) 篇").font(.system(size: 12)).foregroundStyle(WB.secondary) }
                    HStack {
                        ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { index in
                            VStack(spacing: 10) { Text(["M", "T", "W", "T", "F", "S", "S"][index]).font(.system(size: 10)); Circle().fill(practiced(on: index) ? WB.blue : .white).overlay(Circle().stroke(practiced(on: index) ? WB.blue : WB.line, lineWidth: 1.2)).frame(width: 16, height: 16).accessibilityLabel(practiced(on: index) ? "Practiced" : "No review") }.frame(maxWidth: .infinity).foregroundStyle(WB.secondary)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Good writing is\nclear thinking made visible.").font(.system(size: 17)).lineSpacing(6)
                Text("— Bill Wheeler").font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .trailing).foregroundStyle(WB.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(WB.tint.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
            Spacer(minLength: 0)
        }
    }
    private func practiced(on day: Int) -> Bool {
        var calendar = Calendar.current; calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start, let date = calendar.date(byAdding: .day, value: day, to: start) else { return false }
        return sessions.contains { !$0.isDemo && calendar.isDate($0.date, inSameDayAs: date) }
    }
    private var greeting: String { let hour = Calendar.current.component(.hour, from: Date()); return hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening" }
}

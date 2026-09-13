import SwiftUI
import SwiftData

enum Destination: String, CaseIterable, Identifiable {
    case write = "Write", history = "History", statistics = "Statistics", mistakes = "Mistakes", settings = "Settings"
    var id: String { rawValue }
    var symbol: String { switch self { case .write: "square.and.pencil"; case .history: "clock"; case .statistics: "chart.bar.xaxis"; case .mistakes: "text.badge.xmark"; case .settings: "gearshape" } }
}
struct WorkspaceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var review: EssaySession?
    @State private var destination: Destination = .write
    @State private var store = WritingStore()
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if !store.isInSession { sidebar.frame(width: 200) }
                VStack(spacing: 0) {
                    if !store.isInSession { header }
                    if destination == .write {
                        WritingView(store: store, onReview: { review = $0 }).frame(maxWidth: .infinity)

                    } else {
                        switch destination {
                        case .statistics: StatisticsView()
                        case .mistakes: MistakesView(onOpen: { review = $0 })
                        case .settings: SettingsView()
                        case .history: HistoryView(onOpen: { review = $0 })
                        case .write: EmptyView()
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(WB.canvas).foregroundStyle(WB.ink)
        }.frame(minWidth: 980, minHeight: 700)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.isInSession)
        .background(WindowImmersionBridge(isImmersed: store.isInSession))
        .task { store.attach(context) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { store.tick(); store.persistDraft() } }
        .onChange(of: destination) { _, next in if next != .write { store.tick(); store.persistDraft() } }
        .sheet(item: $review) { session in ReviewView(session: session) { store.beginRewrite($0); destination = .write; review = nil } }
        .alert("未配置 DeepSeek API Key", isPresented: $store.needsAPIKey) {
            Button("继续作答", role: .cancel) { }
            Button("前往设置") { if store.leaveAnswering() { destination = .settings } }
        } message: {
            Text("评卷需要 DeepSeek API Key。作文草稿已保存在本机，本次未生成评分。请前往设置填入 API Key 后再交卷。")
        }
        .alert("WriteBench", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                BrandMark(size: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text("WriteBench").font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }.padding(.top, 53).padding(.bottom, 33).padding(.horizontal, 22)
            VStack(spacing: 7) {
                ForEach(Destination.allCases) { item in
                    Button { destination = item } label: {
                        HStack(spacing: 17) {
                            Image(systemName: item.symbol).font(.system(size: 19, weight: .regular)).frame(width: 23)
                            Text(item.rawValue).font(.system(size: 16, weight: destination == item ? .medium : .regular))
                            Spacer()
                        }.padding(.horizontal, 16).frame(height: 49)
                            .foregroundStyle(destination == item ? WB.blue : WB.secondary)
                            .background(destination == item ? Color(red: 0.87, green: 0.91, blue: 1) : .clear, in: RoundedRectangle(cornerRadius: 13))
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(NavigationButtonStyle()).accessibilityIdentifier("nav_\(item.rawValue)")
                }
            }.padding(.horizontal, 18)
            Spacer(minLength: 24)
            Text("WriteBench · 本机保存").font(.system(size: 10)).foregroundStyle(WB.secondary.opacity(0.7)).padding(24)
        }.background(Color.white)
            .overlay(alignment: .trailing) { Rectangle().fill(WB.line.opacity(0.6)).frame(width: 1) }
    }

    private var header: some View {
        HStack(spacing: 38) {
            ForEach(Exam.allCases) { exam in
                Button { store.select(exam.tasks[0]); destination = .write } label: {
                    VStack(spacing: 0) {
                        Text(exam.title).font(.system(size: 17, weight: store.task.exam == exam ? .semibold : .medium)).frame(height: 69)
                        Capsule().fill(store.task.exam == exam ? WB.blue : .clear).frame(width: 58, height: 3)
                    }.foregroundStyle(store.task.exam == exam ? WB.blue : WB.ink)
                }.buttonStyle(.plain).accessibilityIdentifier("exam_\(exam.rawValue)")
            }
            Spacer()
            IconButton(symbol: "gearshape", help: "Settings") { destination = .settings }
        }.padding(.horizontal, 34).background(.white.opacity(0.55))
            .overlay(alignment: .bottom) { Rectangle().fill(WB.line.opacity(0.7)).frame(height: 1) }
    }
}

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(filter: #Predicate<EssaySession> { !$0.isDemo }, sort: \EssaySession.date, order: .reverse) private var sessions: [EssaySession]
    @Query private var folderMetadata: [EssayFolderMetadata]
    var onOpen: (EssaySession) -> Void
    @State private var search = ""
    @State private var exam: Exam?
    @State private var year: Int?
    @State private var label: String?
    @State private var editingGroup: EssayHistoryGroup?
    private var metadataByKey: [String: EssayFolderMetadata] { Dictionary(uniqueKeysWithValues: folderMetadata.map { ($0.key, $0) }) }
    private var years: [Int] { Array(Set(folderMetadata.compactMap(\.questionYear))).sorted(by: >) }
    private var labels: [String] { Array(Set(folderMetadata.map(\.label).filter { !$0.isEmpty })).sorted() }
    @State private var expanded: Set<EssayHistoryGroup.Key> = []
    private var groups: [EssayHistoryGroup] {
        EssayHistoryGroup.make(from: sessions).filter {
            $0.matches(search: search, exam: exam, year: year, label: label, metadata: metadataByKey[$0.id.storageKey])
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "Your writing, revisited.", subtitle: "每道题一个目录，留住每一稿的进步。")
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(WB.secondary)
                    TextField("Search questions and essays", text: $search).textFieldStyle(.plain)
                    Spacer()
                    if !years.isEmpty {
                        Picker("年份", selection: $year) {
                            Text("全部年份").tag(Optional<Int>.none)
                            ForEach(years, id: \.self) { Text(String($0)).tag(Optional($0)) }
                        }.labelsHidden().frame(width: 110)
                    }
                    if !labels.isEmpty {
                        Picker("标签", selection: $label) {
                            Text("全部标签").tag(Optional<String>.none)
                            ForEach(labels, id: \.self) { Text($0).tag(Optional($0)) }
                        }.labelsHidden().frame(width: 120)
                    }
                    Picker("Exam", selection: $exam) {
                        Text("All exams").tag(Optional<Exam>.none)
                        ForEach(Exam.allCases) { Text($0.title).tag(Optional($0)) }
                    }.frame(width: 160)
                }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WB.line))
                if groups.isEmpty {
                    Card {
                        EmptyState(symbol: "folder", title: sessions.isEmpty ? "Your next essay starts a story." : "No matching essays",
                            detail: sessions.isEmpty ? "交卷后，同题作答与重写会保存在一个目录里。" : "Try another search or exam filter.")
                    }
                } else {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("题目 / 修改记录").frame(maxWidth: .infinity, alignment: .leading)
                                Text("最近得分").frame(width: 120)
                                Text("置信度").frame(width: 90)
                                Color.clear.frame(width: 24, height: 1)
                            }.font(.system(size: 11, weight: .semibold)).foregroundStyle(WB.secondary).padding(20)
                            ForEach(groups) { group in
                                folder(group)
                                if expanded.contains(group.id) { versions(group) }
                            }
                        }
                    }
                    Text("同一题型、题目及题图的记录自动归组。点击“重写”提交的新稿会记录来源，旧记录按交卷时间排列。")
                        .font(.system(size: 11)).foregroundStyle(WB.secondary)
                }
            }.padding(32)
        }
        .sheet(item: $editingGroup) { group in
            HistoryFolderEditor(group: group, metadata: metadataByKey[group.id.storageKey])
        }
        .onChange(of: years) { _, available in if let year, !available.contains(year) { self.year = nil } }
        .onChange(of: labels) { _, available in if let label, !available.contains(label) { self.label = nil } }
    }
    private func folder(_ group: EssayHistoryGroup) -> some View {
        let isExpanded = expanded.contains(group.id)
        let metadata = metadataByKey[group.id.storageKey]
        let customTitle = metadata?.title ?? ""
        return HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded { expanded.remove(group.id) } else { expanded.insert(group.id) }
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(WB.secondary).frame(width: 10)
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.system(size: 23, weight: .light)).foregroundStyle(WB.blue).frame(width: 30)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 10) {
                            ExamTaskBadge(task: group.latest.task)
                            Text("\(group.versions.count) 稿").font(.system(size: 11)).foregroundStyle(WB.secondary)
                        }
                        if !customTitle.isEmpty {
                            Text(customTitle).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        }
                        Text(group.questionTitle.isEmpty ? "图片题目" : group.questionTitle)
                            .font(.system(size: 12)).foregroundStyle(WB.secondary).lineLimit(1)
                        HStack(spacing: 8) {
                            if let year = metadata?.questionYear { Text(String(year)).foregroundStyle(WB.blue) }
                            if let label = metadata?.label, !label.isEmpty { Text(label).lineLimit(1) }
                            Text("最近提交 · \(group.latest.date.formatted(date: .abbreviated, time: .shortened))").lineLimit(1)
                        }.font(.system(size: 10)).foregroundStyle(WB.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 5) {
                        Text("\(group.latest.finalScore.scoreText) / \(Int(group.latest.task.maxScore))")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(WB.blue)
                        if group.versions.count > 1 {
                            Text("\(group.first.finalScore.scoreText) → \(group.latest.finalScore.scoreText)")
                                .font(.system(size: 11)).foregroundStyle(WB.secondary)
                        }
                    }.frame(width: 120)
                    confidence(group.latest).frame(width: 90)
                }.padding(.vertical, 20).padding(.leading, 20).padding(.trailing, 4).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("\(group.latest.task.fullTitle)，\(group.versions.count) 稿，\(isExpanded ? "收起" : "展开")修改记录")
                .help(isExpanded ? "收起修改记录" : "展开全部版本")
            Menu {
                Button("编辑题目信息…") { editingGroup = group }
            } label: { Image(systemName: "ellipsis").foregroundStyle(WB.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24).padding(.trailing, 16)
                .help("自定义名称、年份和标签").accessibilityLabel("编辑题目信息")
        }.background(isExpanded ? WB.tint.opacity(0.35) : .white)
            .overlay(alignment: .top) { WB.line.opacity(0.55).frame(height: 1) }
    }
    private func versions(_ group: EssayHistoryGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.versions.enumerated()), id: \.element.id) { index, session in
                Button { onOpen(session) } label: {
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(WB.blue).frame(width: 32, height: 32)
                            .background(WB.tint, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Text("第 \(index + 1) 稿").font(.system(size: 13, weight: .medium))
                                if let parent = group.parentNumber(of: session) {
                                    Label("基于第 \(parent) 稿", systemImage: "arrow.turn.down.right")
                                        .font(.system(size: 11)).foregroundStyle(WB.secondary)
                                }
                            }
                            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11)).foregroundStyle(WB.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(session.finalScore.scoreText) / \(Int(session.task.maxScore))")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(WB.blue).frame(width: 120)
                        confidence(session).frame(width: 66)
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(WB.secondary).frame(width: 10)
                    }.padding(.vertical, 15).padding(.leading, 64).padding(.trailing, 60)
                        .contentShape(Rectangle()).overlay(alignment: .top) { WB.line.opacity(0.4).frame(height: 1).padding(.leading, 64) }
                }.buttonStyle(.plain).help("打开第 \(index + 1) 稿的完整评阅")
            }
        }
    }
    private func confidence(_ session: EssaySession) -> some View {
        Text(session.confidence).font(.system(size: 12)).foregroundStyle(session.confidence == "Low" ? WB.amber : WB.green)
    }
}

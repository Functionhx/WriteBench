import SwiftUI
import SwiftData

struct HistoryFolderEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let group: EssayHistoryGroup
    let metadata: EssayFolderMetadata?
    @State private var title: String
    @State private var year: String
    @State private var label: String
    @State private var error: String?
    init(group: EssayHistoryGroup, metadata: EssayFolderMetadata?) {
        self.group = group; self.metadata = metadata
        _title = State(initialValue: metadata?.title ?? "")
        _year = State(initialValue: metadata?.questionYear.map(String.init) ?? "")
        _label = State(initialValue: metadata?.label ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("题目信息").font(.system(size: 21, weight: .semibold))
                Spacer()
                IconButton(symbol: "xmark", help: "取消编辑") { dismiss() }
            }
            Text("\(group.latest.task.fullTitle) · \(group.versions.count) 稿")
                .font(.system(size: 12)).foregroundStyle(WB.secondary)
            VStack(alignment: .leading, spacing: 17) {
                field("自定义名称", placeholder: "例如：邀请信练习", value: $title)
                field("题目年份", placeholder: "例如：2024（可留空）", value: $year)
                field("自定义标签", placeholder: "例如：真题、模拟题或自己的分类", value: $label)
            }
            Text("名称留空时使用题型名称。年份指题目年份，与交卷日期分开；本目录下的所有稿件共用这些信息。")
                .font(.system(size: 11)).foregroundStyle(WB.secondary).lineSpacing(3)
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(WB.amber) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button("保存") {
                    do {
                        try EssayFolderDetails(title: title, year: year, label: label)
                            .save(key: group.id.storageKey, existing: metadata, in: context)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440).background(WB.canvas).foregroundStyle(WB.ink)
    }
    private func field(_ name: String, placeholder: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.system(size: 12, weight: .medium))
            TextField(placeholder, text: value).textFieldStyle(.plain).font(.system(size: 13))
                .padding(11).background(.white, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(WB.line)).accessibilityLabel(name)
        }
    }
}

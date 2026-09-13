import SwiftUI

/// Exam and task stay visible even when a question folder has a custom title.
struct ExamTaskBadge: View {
    let task: WritingTask
    private var subtype: String {
        switch task {
        case .kaoyanSmall: "英语一 · 小作文"
        case .kaoyanLarge: "英语一 · 大作文"
        case .cet6Writing: "写作"
        case .ieltsTask1: "Task 1 · 小作文"
        case .ieltsTask2: "Task 2 · 大作文"
        default: task.title
        }
    }
    var body: some View {
        HStack(spacing: 8) {
            Label(task.exam.title, systemImage: task.exam.symbol)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(WB.ink)
            Text(subtype).font(.system(size: 11, weight: .medium)).foregroundStyle(WB.blue)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(WB.tint, in: RoundedRectangle(cornerRadius: 6))
        }.lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
    }
}

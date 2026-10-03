import SwiftUI

struct TranslationLessonCard: View {
    let lessons: [TranslationLesson]
    @State private var expanded: Set<String> = []
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                Text("意群精讲").font(.system(size: 18, weight: .semibold))
                Text("拆句 → 词汇与翻译要点 → 意群译文 → 完整译文").font(.system(size: 12)).foregroundStyle(WB.secondary)
                ForEach(Array(lessons.enumerated()), id: \.offset) { _, lesson in
                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(lesson.number) }, set: { value in
                        if value { expanded.insert(lesson.number) } else { expanded.remove(lesson.number) }
                    })) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(lesson.source).font(.system(size: 14)).lineSpacing(4)
                            ForEach(Array(lesson.groups.enumerated()), id: \.offset) { index, group in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("意群 \(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(WB.blue)
                                    Text(group.source).font(.system(size: 14, weight: .medium)).lineSpacing(4)
                                    if !group.vocabulary.isEmpty {
                                        Text("重点词汇").font(.system(size: 12, weight: .semibold))
                                        ForEach(Array(group.vocabulary.enumerated()), id: \.offset) { _, word in
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("\(word.word) · \(word.partOfSpeech)").font(.system(size: 13, weight: .medium))
                                                Text("常见义：\(word.commonMeaning)\n本句义：\(word.contextualMeaning)").font(.system(size: 12)).foregroundStyle(WB.secondary).lineSpacing(3)
                                            }
                                        }
                                    }
                                    if !group.techniques.isEmpty {
                                        Text("翻译要点").font(.system(size: 12, weight: .semibold))
                                        ForEach(group.techniques, id: \.self) { Text("• " + $0).font(.system(size: 13)).foregroundStyle(WB.secondary).lineSpacing(4) }
                                    }
                                    Label(group.translation, systemImage: "arrow.turn.down.right").font(.system(size: 14)).lineSpacing(4)
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(WB.canvas, in: RoundedRectangle(cornerRadius: 12))
                            }
                            Text("组合后的完整译文").font(.system(size: 14, weight: .semibold))
                            Text(lesson.referenceTranslation).font(.system(size: 14)).lineSpacing(5)
                            if !lesson.assemblyNotes.isEmpty {
                                Text("如何组合意群").font(.system(size: 13, weight: .semibold))
                                ForEach(lesson.assemblyNotes, id: \.self) { Text("• " + $0).font(.system(size: 13)).foregroundStyle(WB.secondary).lineSpacing(4) }
                            }
                            if !lesson.studentAdvice.isEmpty {
                                Text("对照你的译文").font(.system(size: 13, weight: .semibold))
                                Text(lesson.studentAdvice).font(.system(size: 13)).lineSpacing(4)
                            }
                        }.padding(.top, 12).textSelection(.enabled)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("第 \(lesson.number) 句 · \(lesson.groups.count) 个意群").font(.system(size: 14, weight: .semibold))
                            Text(lesson.source).font(.system(size: 12)).foregroundStyle(WB.secondary).lineLimit(2)
                        }
                    }.tint(WB.blue)
                    Divider()
                }
            }
        }.onAppear { if expanded.isEmpty, let first = lessons.first { expanded.insert(first.number) } }
    }
}

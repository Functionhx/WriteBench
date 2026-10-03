import SwiftUI

/// Word-level comparison of two drafts. English splits into words; Chinese compares character by character.
enum RevisionDiff {
    struct Result {
        var text: AttributedString
        var inserted: Int
        var removed: Int
    }
    static let removedColor = Color(red: 0.72, green: 0.24, blue: 0.2)
    static func tokens(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9]+(?:[’'\-][A-Za-z0-9]+)*|\s+|."#, options: [.dotMatchesLineSeparators]) else { return text.map(String.init) }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    static func compare(_ old: String, _ new: String) -> Result {
        let before = tokens(old), after = tokens(new)
        let difference = after.difference(from: before)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var output = AttributedString(), i = 0, j = 0
        let isWord: (String) -> Bool = { !$0.allSatisfy(\.isWhitespace) }
        while i < before.count || j < after.count {
            if i < before.count, removed.contains(i) {
                if isWord(before[i]) {
                    // Removed whitespace is not drawn, so keep struck words apart from their neighbours.
                    if let last = output.characters.last, !last.isWhitespace { output += AttributedString(" ") }
                    var run = AttributedString(before[i])
                    run.foregroundColor = removedColor; run.strikethroughStyle = .single; run.backgroundColor = removedColor.opacity(0.08)
                    output += run
                    if j < after.count, isWord(after[j]) { output += AttributedString(" ") }
                }
                i += 1
            } else if j < after.count, inserted.contains(j) {
                var run = AttributedString(after[j])
                if isWord(after[j]) { run.foregroundColor = WB.green; run.backgroundColor = WB.green.opacity(0.1) }
                output += run
                j += 1
            } else {
                if j < after.count { output += AttributedString(after[j]) }
                i += 1; j += 1
            }
        }
        return Result(text: output, inserted: inserted.filter { isWord(after[$0]) }.count, removed: removed.filter { isWord(before[$0]) }.count)
    }
}

/// The student's answer with every locatable correction highlighted. Clicking a highlight shows that correction.
struct AnnotatedEssayView: View {
    let essay: String
    let corrections: [Correction]
    @State private var selected: Int?
    private static let scheme = "writebench-correction"

    private var annotated: (text: AttributedString, located: Int) {
        var text = AttributedString(essay), taken: [Range<String.Index>] = [], located = 0
        for (index, correction) in corrections.enumerated() {
            guard let range = CorrectionMatcher.range(of: correction.original, in: essay), !taken.contains(where: { $0.overlaps(range) }),
                  let lower = AttributedString.Index(range.lowerBound, within: text), let upper = AttributedString.Index(range.upperBound, within: text) else { continue }
            taken.append(range); located += 1
            let color = correction.severity == .major ? WB.amber : WB.blue
            text[lower..<upper].backgroundColor = color.opacity(selected == index ? 0.32 : 0.14)
            text[lower..<upper].underlineStyle = Text.LineStyle(pattern: .solid, color: color.opacity(0.7))
            text[lower..<upper].link = URL(string: "\(Self.scheme)://\(index)")
        }
        return (text, located)
    }
    var body: some View {
        let result = annotated
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("在原文中查看").font(.system(size: 13, weight: .semibold))
                legend("主要问题", WB.amber); legend("次要问题", WB.blue)
                Spacer()
                Text(result.located == corrections.count ? "点击高亮处查看修改" : "已标出 \(result.located) / \(corrections.count) 处 · 点击高亮处查看修改")
                    .font(.system(size: 11)).foregroundStyle(WB.secondary)
            }
            Text(result.text).font(.system(size: 15)).lineSpacing(7).tint(WB.ink).foregroundStyle(WB.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == Self.scheme, let index = url.host().flatMap(Int.init), corrections.indices.contains(index) else { return .discarded }
                    selected = selected == index ? nil : index
                    return .handled
                })
                .accessibilityIdentifier("annotatedEssay")
            if let selected, corrections.indices.contains(selected) {
                HStack(alignment: .top) {
                    CorrectionRow(correction: corrections[selected])
                    IconButton(symbol: "xmark", help: "收起") { self.selected = nil }
                }
            }
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(WB.line))
    }
    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.25)).frame(width: 14, height: 9); Text(title) }.font(.system(size: 11)).foregroundStyle(WB.secondary)
    }
}

/// How this draft moved relative to the draft it was based on.
struct RevisionComparisonCard: View {
    let session: EssaySession
    let baseline: EssaySession
    let baselineNumber: String
    @State private var showDiff = true
    var body: some View {
        let current = session.report, previous = baseline.report
        let delta = session.finalScore - baseline.finalScore
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("与\(baselineNumber)相比").font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Text("\(baseline.date.formatted(date: .abbreviated, time: .shortened)) → \(session.date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(WB.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(Self.signed(delta)).font(.system(size: 40, weight: .semibold, design: .rounded)).foregroundStyle(Self.color(delta))
                    Text("分 · \(baseline.finalScore.scoreText) → \(session.finalScore.scoreText) / \(Int(session.task.maxScore))").font(.system(size: 14)).foregroundStyle(WB.secondary)
                    Spacer()
                    if current?.gradingMode != previous?.gradingMode {
                        Text("两稿评阅方式不同，分差仅供参考").font(.system(size: 11)).foregroundStyle(WB.amber)
                    }
                }
                if let current, let previous {
                    HStack(spacing: 12) {
                        change(session.task.isTranslation ? "译义" : "任务", previous.dimension(\.taskCompletion), current.dimension(\.taskCompletion))
                        change("语言", previous.dimension(\.language), current.dimension(\.language))
                        change("连贯", previous.dimension(\.coherence), current.dimension(\.coherence))
                        change("语域", previous.dimension(\.register), current.dimension(\.register))
                        change("主要问题", Double(previous.corrections.filter { $0.severity == .major }.count), Double(current.corrections.filter { $0.severity == .major }.count), lowerIsBetter: true, integer: true)
                    }
                }
                let diff = RevisionDiff.compare(baseline.originalEssay, session.originalEssay)
                DisclosureGroup(isExpanded: $showDiff) {
                    Text(diff.text).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                } label: {
                    Text("逐词对比 · 新增 \(diff.inserted) · 删除 \(diff.removed)").font(.system(size: 13, weight: .medium))
                }
            }
        }
    }
    private func change(_ title: String, _ old: Double, _ new: Double, lowerIsBetter: Bool = false, integer: Bool = false) -> some View {
        let delta = new - old
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(WB.secondary)
            Text(integer ? "\(Int(old)) → \(Int(new))" : "\(old.scoreText) → \(new.scoreText)").font(.system(size: 13, weight: .medium)).monospacedDigit()
            Text(delta == 0 ? "持平" : integer ? (delta > 0 ? "+\(Int(delta))" : "\(Int(delta))") : Self.signed(delta)).font(.system(size: 11)).foregroundStyle(Self.color(lowerIsBetter ? -delta : delta))
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(WB.canvas, in: RoundedRectangle(cornerRadius: 10))
    }
    static func signed(_ value: Double) -> String { value > 0 ? "+\(value.scoreText)" : value < 0 ? value.scoreText : "±0" }
    static func color(_ value: Double) -> Color { value > 0 ? WB.green : value < 0 ? RevisionDiff.removedColor : WB.secondary }
}

/// The draft a review should be compared with: its recorded parent, else the latest earlier attempt at the same question.
@MainActor enum RevisionBaseline {
    static func find(for session: EssaySession, among sessions: [EssaySession]) -> (session: EssaySession, label: String)? {
        let group = sessions.filter {
            !$0.isDemo && $0.subtype == session.subtype && QuestionBank.key($0.question) == QuestionBank.key(session.question) && $0.questionImage == session.questionImage
        }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        let baseline: EssaySession?
        if let parentID = session.parentSessionID, parentID != session.id, let parent = sessions.first(where: { $0.id == parentID }) { baseline = parent }
        else { baseline = group.last { $0.date < session.date } }
        guard let baseline else { return nil }
        if let index = group.firstIndex(where: { $0.id == baseline.id }) { return (baseline, "第 \(index + 1) 稿") }
        return (baseline, "上一稿")
    }
}

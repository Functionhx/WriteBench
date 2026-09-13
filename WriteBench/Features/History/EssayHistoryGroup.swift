import Foundation
import CryptoKit

/// A non-destructive presentation of saved attempts. Legacy records need no rewrite.
@MainActor struct EssayHistoryGroup: Identifiable {
    struct Key: Hashable {
        let subtype: String
        let question: String
        let imageDigest: String?
        var storageKey: String {
            let parts = [subtype, question, imageDigest ?? ""]
            let value = parts.map { "\($0.utf8.count):" + $0 }.joined()
            return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }
    let id: Key
    let versions: [EssaySession]
    var first: EssaySession { versions[0] }
    var latest: EssaySession { versions[versions.count - 1] }
    var questionTitle: String { first.question.split(whereSeparator: \.isNewline).joined(separator: " ") }

    private init(key: Key, versions: [EssaySession]) {
        id = key
        self.versions = versions.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }
    static func make(from sessions: [EssaySession]) -> [Self] {
        let grouped = Dictionary(grouping: sessions.filter { !$0.isDemo }) { session in
            Key(subtype: session.subtype,
                question: session.question.replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                imageDigest: session.questionImage.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() })
        }
        return grouped.map { Self(key: $0.key, versions: $0.value) }.sorted {
            $0.latest.date == $1.latest.date ? $0.latest.id.uuidString < $1.latest.id.uuidString : $0.latest.date > $1.latest.date
        }
    }
    func matches(search: String, exam: Exam?, year: Int? = nil, label: String? = nil, metadata: EssayFolderMetadata? = nil) -> Bool {
        guard exam == nil || latest.exam == exam?.rawValue else { return false }
        guard year == nil || metadata?.questionYear == year,
              label == nil || metadata?.label == label else { return false }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [metadata?.title ?? "", metadata?.label ?? ""].contains { $0.localizedCaseInsensitiveContains(query) } || versions.contains {
            [$0.question, $0.originalEssay, $0.finalRewrite].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
    func parentNumber(of session: EssaySession) -> Int? {
        guard let parentID = session.parentSessionID,
              parentID != session.id,
              let index = versions.firstIndex(where: { $0.id == parentID }) else { return nil }
        return index + 1
    }
}

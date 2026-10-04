import Foundation

struct CETBankEntry: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var task: String
    var year: Int
    var month: Int
    var set: Int
    var title: String
    var prompt: String
    var sourceUrl: String
    var verification: String
    var writingTask: WritingTask? { WritingTask(rawValue: task) }
    var hasPrompt: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
struct CETBankDocument: Codable, Sendable {
    var schemaVersion: Int
    var questions: [CETBankEntry]
    func validated(requirePrompts: Bool, now: Date = Date()) throws -> [CETBankEntry] {
        guard schemaVersion == 1, !questions.isEmpty, questions.count <= 1000 else { throw CETBankError.invalid("题库版本或数量无效") }
        var ids = Set<String>()
        let calendar = Calendar(identifier: .gregorian)
        for item in questions {
            guard !item.id.isEmpty, ids.insert(item.id).inserted, ["cet6Writing", "cet6Translation"].contains(item.task),
                  (2022...2026).contains(item.year), [3, 6, 9, 12].contains(item.month), (1...3).contains(item.set),
                  let date = calendar.date(from: DateComponents(year: item.year, month: item.month, day: 1)), date <= now,
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.prompt.count <= 100_000,
                  let url = URL(string: item.sourceUrl), ["https", "http"].contains(url.scheme ?? ""), url.host != nil,
                  ["sourceIndex", "userImported"].contains(item.verification)
            else { throw CETBankError.invalid("题目 \(item.id) 的年份、题型、套次、来源或标识无效") }
            if requirePrompts && !item.hasPrompt { throw CETBankError.invalid("题目 \(item.title) 只有来源索引，没有正文，不能作为练习题导入") }
        }
        return questions
    }
}
enum CETBankError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { message } else { nil } }
}
enum CETQuestionBank {
    static var storage: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WriteBench/QuestionBank/cet6-custom.json") }
    static func decode(_ data: Data, requirePrompts: Bool) throws -> [CETBankEntry] {
        guard data.count <= 10 * 1024 * 1024 else { throw CETBankError.invalid("题库文件超过 10 MB") }
        return try JSONDecoder().decode(CETBankDocument.self, from: data).validated(requirePrompts: requirePrompts)
    }
    static func entries(storage: URL = storage) throws -> [CETBankEntry] {
        guard let url = Bundle.main.url(forResource: "cet6-2022-2026-index", withExtension: "json") else { throw CETBankError.invalid("内置来源索引未找到") }
        let base = try decode(Data(contentsOf: url), requirePrompts: false)
        let custom = FileManager.default.fileExists(atPath: storage.path) ? try decode(Data(contentsOf: storage), requirePrompts: true) : []
        var values = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        for item in custom { values[item.id] = item }
        return values.values.sorted { ($0.year, $0.month, $0.set, $0.task) > ($1.year, $1.month, $1.set, $1.task) }
    }
    @discardableResult static func importData(_ data: Data, storage: URL = storage) throws -> Int {
        let imported = try decode(data, requirePrompts: true).map { entry in var entry = entry; entry.verification = "userImported"; return entry }
        let previous = FileManager.default.fileExists(atPath: storage.path) ? try decode(Data(contentsOf: storage), requirePrompts: true) : []
        var values = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for item in imported { values[item.id] = item }
        let result = CETBankDocument(schemaVersion: 1, questions: values.values.sorted { $0.id < $1.id })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = try encoder.encode(result)
        try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: storage, options: .atomic)
        return imported.count
    }
}

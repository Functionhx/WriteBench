import Foundation
import Testing
@testable import WriteBench

private func entry(_ id: String = "fixture", prompt: String = "Write an essay about careful planning.") -> CETBankEntry {
    CETBankEntry(id: id, task: "cet6Writing", year: 2024, month: 6, set: 1, title: "导入测试", prompt: prompt, sourceUrl: "https://example.com/fixture", verification: "userImported")
}
private func bankData(_ entries: [CETBankEntry], version: Int = 1) throws -> Data {
    try JSONEncoder().encode(CETBankDocument(schemaVersion: version, questions: entries))
}
@Test func cetProvidedPaperCoverage() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let entries = try CETQuestionBank.entries(storage: folder.appendingPathComponent("empty.json"))
    #expect(entries.count == 66)
    #expect(entries.filter { $0.task == "cet6Writing" }.count == 33)
    #expect(entries.filter { $0.task == "cet6Translation" }.count == 33)
    #expect(entries.allSatisfy { $0.hasPrompt && $0.verification == "providedDocument" })
    #expect(Set(entries.map(\.prompt)).count == 66)
    #expect(entries.allSatisfy { $0.prompt.hasPrefix("Directions:") && !$0.prompt.contains("懒笔记") && !$0.prompt.contains("参考范文") })
    #expect(entries.contains { $0.year == 2022 && $0.month == 9 })
    #expect(entries.contains { $0.year == 2023 && $0.month == 3 })
    #expect(!entries.contains { $0.year == 2026 && $0.month == 12 })
}
@Test func cetIndexIsNotPlayable() throws {
    #expect(throws: CETBankError.self) { try CETQuestionBank.decode(bankData([entry(prompt: "")]), requirePrompts: true) }
    #expect(try CETQuestionBank.decode(bankData([entry(prompt: "")]), requirePrompts: false).count == 1)
}
@Test func cetInvalidMetadataRejected() throws {
    var invalid = entry(); invalid.task = "kaoyanLarge"
    #expect(throws: CETBankError.self) { try CETQuestionBank.decode(bankData([invalid]), requirePrompts: true) }
    invalid = entry(); invalid.sourceUrl = "file:///etc/passwd"
    #expect(throws: CETBankError.self) { try CETQuestionBank.decode(bankData([invalid]), requirePrompts: true) }
    #expect(throws: CETBankError.self) { try CETQuestionBank.decode(bankData([entry(), entry()]), requirePrompts: true) }
    #expect(throws: CETBankError.self) { try CETQuestionBank.decode(bankData([entry()], version: 2), requirePrompts: true) }
}
@Test func cetFutureExamRejected() throws {
    var invalid = entry(); invalid.year = 2026; invalid.month = 12
    let document = CETBankDocument(schemaVersion: 1, questions: [invalid])
    #expect(throws: CETBankError.self) { try document.validated(requirePrompts: true, now: Date(timeIntervalSince1970: 1_791_000_000)) }
}
@Test func cetImportMergesAndFailedImportPreservesFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cet-bank-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("bank.json")
    #expect(try CETQuestionBank.importData(bankData([entry("a"), entry("b")]), storage: storage) == 2)
    let before = try Data(contentsOf: storage)
    #expect(throws: CETBankError.self) { try CETQuestionBank.importData(bankData([entry("c", prompt: "")]), storage: storage) }
    #expect(try Data(contentsOf: storage) == before)
    #expect(try CETQuestionBank.importData(bankData([entry("a", prompt: "Updated original practice question.")]), storage: storage) == 1)
    let result = try CETQuestionBank.decode(Data(contentsOf: storage), requirePrompts: true)
    #expect(result.count == 2)
    #expect(result.first { $0.id == "a" }?.prompt == "Updated original practice question.")
    #expect(result.allSatisfy { $0.verification == "userImported" })
}

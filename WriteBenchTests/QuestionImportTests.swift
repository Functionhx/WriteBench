import Foundation
import SwiftData
import Testing
@testable import WriteBench

@Test func questionImportPreservesChineseAndParagraphsAcrossEncodings() throws {
    let input = "请将以下段落译成汉语。\r\n\r\nLearning takes time.\r1. Keep practising."
    let expected = "请将以下段落译成汉语。\n\nLearning takes time.\n1. Keep practising."
    for (encoding, bom): (String.Encoding, [UInt8]) in [(.utf8, []), (.utf8, [0xEF, 0xBB, 0xBF]), (.utf16LittleEndian, [0xFF, 0xFE]), (.utf16BigEndian, [0xFE, 0xFF])] {
        let data = Data(bom) + (try #require(input.data(using: encoding)))
        #expect(try QuestionTextReader.decode(data) == expected)
    }
}

@Test func questionImportRejectsEmptyBinaryAndOversizedFiles() {
    for data in [Data(), Data(" \n\t".utf8), Data([0xFF, 0x80]), Data("Question\0binary".utf8), Data(repeating: 65, count: QuestionTextReader.maximumBytes + 1)] {
        #expect(throws: (any Error).self) { try QuestionTextReader.decode(data) }
    }
}

@Test func questionImportReadsARealTextFile() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("writebench-question-\(UUID()).txt")
    let question = "把这段中文译成英语。\n\n阅读使人不断成长。"
    try Data(question.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(try await QuestionTextReader().read(url) == question)
}

@Test @MainActor func importingQuestionPersistsWithoutLosingTheAnswerOrOtherTaskDrafts() throws {
    let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = WritingStore()
    store.attach(ModelContext(container))
    store.select(.cet6Translation)
    store.essay = "An existing translation."
    store.elapsed = 420
    store.inputMode = .handwritten
    store.sourceImages = [Data([4, 5, 6])]
    store.questionImage = Data([1, 2, 3])
    let previousQuestion = store.question
    #expect(!store.importQuestion(text: "\n ", title: ""))
    #expect(store.question == previousQuestion)
    #expect(store.questionImage != nil)
    #expect(store.importQuestion(text: "  请将这段中文译成英语。\n\n阅读使人不断成长。  ", title: " 我的六级题目 "))
    #expect(store.stage == .preparation && !store.timerRunning)
    let restored = WritingStore()
    restored.attach(ModelContext(container))
    #expect(restored.question == WritingTask.kaoyanSmall.sampleQuestion)
    restored.select(.cet6Translation)
    #expect(restored.question == "请将这段中文译成英语。\n\n阅读使人不断成长。")
    #expect(restored.questionLabel == "我的六级题目")
    #expect(restored.questionImage == nil)
    #expect(restored.essay == "An existing translation.")
    #expect(restored.elapsed == 420)
    #expect(restored.inputMode == .handwritten)
    #expect(restored.sourceImages == [Data([4, 5, 6])])
    #expect(restored.startAnswering())
    #expect(!restored.importQuestion(text: "Cannot replace an active exam.", title: ""))
    #expect(restored.questionLabel == "我的六级题目")
}

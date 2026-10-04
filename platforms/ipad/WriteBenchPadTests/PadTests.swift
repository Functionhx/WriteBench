import XCTest
import SwiftData
import UIKit
@testable import WriteBenchPad

@MainActor final class PadTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, EssayFolderMetadata.self, ReviewCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    func testBundledCETBankAndRubrics() throws {
        let entries = try CETQuestionBank.entries(storage: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertEqual(entries.filter { $0.task == "cet6Writing" }.count, 33)
        XCTAssertEqual(entries.filter { $0.task == "cet6Translation" }.count, 33)
        XCTAssertTrue(entries.allSatisfy(\.hasPrompt))
        for task in WritingTask.allCases { XCTAssertFalse(try RubricLoader.load(task).isEmpty) }
    }
    func testDraftWhitespaceAndParagraphFormattingRestore() throws {
        let container = try container(); let store = PadStore(); store.attach(container.mainContext)
        store.essay = "    Notice\n\nBody    text\nUniversity Library"
        let styled = NSMutableAttributedString(string: store.essay)
        let style = NSMutableParagraphStyle(); style.alignment = .right
        styled.addAttribute(.paragraphStyle, value: style, range: (store.essay as NSString).range(of: "University Library"))
        store.richText = try styled.data(from: NSRange(location: 0, length: styled.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        XCTAssertTrue(store.save())
        let restored = PadStore(); restored.attach(container.mainContext)
        XCTAssertEqual(restored.essay, store.essay); XCTAssertEqual(restored.richText, store.richText)
        XCTAssertFalse(restored.running)
    }
    func testTimerPausesForInvalidSubmission() throws {
        let container = try container(); let store = PadStore(); store.attach(container.mainContext)
        store.start(); XCTAssertTrue(store.running)
        store.submit(quick: true)
        XCTAssertFalse(store.running); XCTAssertNotNil(store.error); XCTAssertFalse(store.isGrading)
        let snapshot = store.elapsed; XCTAssertEqual(store.time(at: Date().addingTimeInterval(60)), snapshot)
    }
    func testTaskSwitchKeepsIndependentDrafts() throws {
        let container = try container(); let store = PadStore(); store.attach(container.mainContext)
        store.essay = "Writing answer"; store.start(); store.select(.cet6Translation)
        XCTAssertFalse(store.running); XCTAssertEqual(store.essay, "")
        store.essay = "Translation answer"; store.select(.cet6Writing)
        XCTAssertEqual(store.essay, "Writing answer")
        store.select(.cet6Translation); XCTAssertEqual(store.essay, "Translation answer")
    }
    func testPortableBackupPreservesFormattingWithoutCredentials() throws {
        let source = try container(); let store = PadStore(); store.attach(source.mainContext)
        store.essay = "    Portable draft"; store.richText = Data("format fixture".utf8); store.pencilDrawing = Data("pencil fixture".utf8); XCTAssertTrue(store.save())
        let data = try BackupService.export(from: source.mainContext)
        let destination = try container(); let summary = try BackupService.restore(data, into: destination.mainContext)
        XCTAssertEqual(summary.added, 1)
        let drafts = try destination.mainContext.fetch(FetchDescriptor<WritingDraft>())
        XCTAssertEqual(drafts.first?.essay, store.essay); XCTAssertEqual(drafts.first?.richText, store.richText); XCTAssertEqual(drafts.first?.pencilDrawing, store.pencilDrawing)
        let text = String(decoding: data, as: UTF8.self); XCTAssertFalse(text.contains("apiKey")); XCTAssertFalse(text.contains("api-key"))
    }
    func testRealVisionOCR() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ocr-sample-1", withExtension: "png"))
        let pages = try await VisionOCRService().recognize(urls: [fixture])
        XCTAssertEqual(pages.count, 1); XCTAssertTrue(pages[0].text.contains("Alex")); XCTAssertFalse(pages[0].imageData.isEmpty)
    }
    func testDeviceFamilyExcludesIPhone() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int], [2])
    }
    func testSpacedRepetitionAdvancesCard() {
        let card = ReviewCard(key: "fixture", kind: .mistake, sessionID: nil, subtype: WritingTask.cet6Writing.rawValue, prompt: "a information", answer: "information", explanation: "不可数", context: "")
        let now = Date(); SpacedRepetition.apply(.good, to: card, now: now)
        XCTAssertEqual(card.box, 1); XCTAssertGreaterThan(card.dueDate, now)
        SpacedRepetition.apply(.again, to: card, now: now); XCTAssertEqual(card.box, 0)
    }
}

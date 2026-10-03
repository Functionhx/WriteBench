import Foundation
import SwiftData

/// A portable JSON copy of everything WriteBench stores locally. API keys and Codex credentials are never included.
struct BackupArchive: Codable {
    static let formatName = "WriteBench backup"
    var format = BackupArchive.formatName
    var version = 1
    var exportedAt: Date
    var appVersion: String
    var sessions: [SessionRecord]
    var drafts: [DraftRecord]
    var questions: [QuestionRecord]
    var folders: [FolderRecord]
    var cards: [CardRecord]

    struct SessionRecord: Codable {
        var id: UUID, date: Date, exam: String, subtype: String, question: String, originalEssay: String, correctedEssay: String, finalRewrite: String
        var writingDuration: Double, wordCount: Int, inputMode: String, reviewerResults: Data, finalScore: Double, confidence: String
        var detectedMistakes: Data, rubricVersion: String, graderPromptVersion: String, modelName: String, timestamp: Date, isDemo: Bool
        var parentSessionID: UUID?, questionImage: Data?, sourceImages: Data?
    }
    struct DraftRecord: Codable {
        var subtype: String, question: String, questionLabel: String, essay: String, elapsed: Double, inputMode: String, updatedAt: Date
        var rewriteSessionID: UUID?, questionImage: Data?, sourceImages: Data?
    }
    struct QuestionRecord: Codable {
        var id: UUID, title: String, subtype: String, prompt: String, date: Date, year: Int?, label: String, image: Data?
    }
    struct FolderRecord: Codable {
        var key: String, title: String, questionYear: Int?, label: String, updatedAt: Date
    }
    struct CardRecord: Codable {
        var key: String, kind: String, sessionID: UUID?, subtype: String, prompt: String, answer: String, explanation: String, context: String
        var category: String, severity: String, box: Int, dueDate: Date, reviewCount: Int, lapseCount: Int, mastered: Bool, archived: Bool
        var createdAt: Date, lastReviewedAt: Date?
    }
}

struct BackupSummary: Equatable {
    var added = 0
    var skipped = 0
    var text: String { skipped == 0 ? "已恢复 \(added) 条记录。" : "已恢复 \(added) 条记录，跳过 \(skipped) 条本机已有或无法读取的记录。" }
}

@MainActor enum BackupService {
    static var suggestedFileName: String { "WriteBench-备份-\(Date().formatted(.iso8601.year().month().day())).json" }

    static func export(from context: ModelContext) throws -> Data {
        let archive = BackupArchive(
            exportedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            sessions: try context.fetch(FetchDescriptor<EssaySession>(sortBy: [SortDescriptor(\.date)])).map {
                .init(id: $0.id, date: $0.date, exam: $0.exam, subtype: $0.subtype, question: $0.question, originalEssay: $0.originalEssay,
                      correctedEssay: $0.correctedEssay, finalRewrite: $0.finalRewrite, writingDuration: $0.writingDuration, wordCount: $0.wordCount,
                      inputMode: $0.inputMode, reviewerResults: $0.reviewerResults, finalScore: $0.finalScore, confidence: $0.confidence,
                      detectedMistakes: $0.detectedMistakes, rubricVersion: $0.rubricVersion, graderPromptVersion: $0.graderPromptVersion,
                      modelName: $0.modelName, timestamp: $0.timestamp, isDemo: $0.isDemo, parentSessionID: $0.parentSessionID,
                      questionImage: $0.questionImage, sourceImages: $0.sourceImages)
            },
            drafts: try context.fetch(FetchDescriptor<WritingDraft>()).map {
                .init(subtype: $0.subtype, question: $0.question, questionLabel: $0.questionLabel, essay: $0.essay, elapsed: $0.elapsed,
                      inputMode: $0.inputMode, updatedAt: $0.updatedAt, rewriteSessionID: $0.rewriteSessionID, questionImage: $0.questionImage, sourceImages: $0.sourceImages)
            },
            questions: try context.fetch(FetchDescriptor<SavedQuestion>()).map {
                .init(id: $0.id, title: $0.title, subtype: $0.subtype, prompt: $0.prompt, date: $0.date, year: $0.year, label: $0.label, image: $0.image)
            },
            folders: try context.fetch(FetchDescriptor<EssayFolderMetadata>()).map {
                .init(key: $0.key, title: $0.title, questionYear: $0.questionYear, label: $0.label, updatedAt: $0.updatedAt)
            },
            cards: try context.fetch(FetchDescriptor<ReviewCard>()).map {
                .init(key: $0.key, kind: $0.kind, sessionID: $0.sessionID, subtype: $0.subtype, prompt: $0.prompt, answer: $0.answer,
                      explanation: $0.explanation, context: $0.context, category: $0.category, severity: $0.severity, box: $0.box, dueDate: $0.dueDate,
                      reviewCount: $0.reviewCount, lapseCount: $0.lapseCount, mastered: $0.mastered, archived: $0.archived,
                      createdAt: $0.createdAt, lastReviewedAt: $0.lastReviewedAt)
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    /// Adds records this Mac does not have. Existing records are never overwritten; an empty draft may be filled.
    static func restore(_ data: Data, into context: ModelContext) throws -> BackupSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive: BackupArchive
        do { archive = try decoder.decode(BackupArchive.self, from: data) } catch { throw BackupError.unreadable }
        guard archive.format == BackupArchive.formatName else { throw BackupError.unreadable }
        guard archive.version <= 1 else { throw BackupError.newerVersion }
        var summary = BackupSummary()

        let sessionIDs = Set(try context.fetch(FetchDescriptor<EssaySession>()).map(\.id))
        for record in archive.sessions {
            guard !sessionIDs.contains(record.id), let task = WritingTask(rawValue: record.subtype),
                  let report = try? JSONDecoder().decode(GradingReport.self, from: record.reviewerResults) else { summary.skipped += 1; continue }
            let session = try EssaySession(task: task, question: record.question, essay: record.originalEssay, duration: record.writingDuration,
                                           inputMode: InputMode(rawValue: record.inputMode) ?? .typed, report: report, parentSessionID: record.parentSessionID)
            session.id = record.id; session.date = record.date; session.exam = record.exam; session.correctedEssay = record.correctedEssay
            session.finalRewrite = record.finalRewrite; session.wordCount = record.wordCount; session.reviewerResults = record.reviewerResults
            session.finalScore = record.finalScore; session.confidence = record.confidence; session.detectedMistakes = record.detectedMistakes
            session.rubricVersion = record.rubricVersion; session.graderPromptVersion = record.graderPromptVersion; session.modelName = record.modelName
            session.timestamp = record.timestamp; session.isDemo = record.isDemo; session.questionImage = record.questionImage; session.sourceImages = record.sourceImages
            context.insert(session); summary.added += 1
        }
        let drafts = Dictionary(try context.fetch(FetchDescriptor<WritingDraft>()).map { ($0.subtype, $0) }, uniquingKeysWith: { first, _ in first })
        for record in archive.drafts {
            guard let task = WritingTask(rawValue: record.subtype), !record.essay.isEmpty else { continue }
            if let existing = drafts[record.subtype], !existing.essay.isEmpty { summary.skipped += 1; continue }
            let draft = drafts[record.subtype] ?? WritingDraft(task: task)
            if drafts[record.subtype] == nil { context.insert(draft) }
            draft.question = record.question; draft.questionLabel = record.questionLabel; draft.essay = record.essay; draft.elapsed = record.elapsed
            draft.inputMode = record.inputMode; draft.updatedAt = record.updatedAt; draft.rewriteSessionID = record.rewriteSessionID
            draft.questionImage = record.questionImage; draft.sourceImages = record.sourceImages
            summary.added += 1
        }
        let questionIDs = Set(try context.fetch(FetchDescriptor<SavedQuestion>()).map(\.id))
        for record in archive.questions {
            guard !questionIDs.contains(record.id), let task = WritingTask(rawValue: record.subtype) else { summary.skipped += 1; continue }
            let question = SavedQuestion(title: record.title, task: task, prompt: record.prompt, image: record.image, year: record.year, label: record.label)
            question.id = record.id; question.date = record.date
            context.insert(question); summary.added += 1
        }
        let folderKeys = Set(try context.fetch(FetchDescriptor<EssayFolderMetadata>()).map(\.key))
        for record in archive.folders {
            guard !folderKeys.contains(record.key) else { summary.skipped += 1; continue }
            let folder = EssayFolderMetadata(key: record.key, title: record.title, questionYear: record.questionYear, label: record.label)
            folder.updatedAt = record.updatedAt
            context.insert(folder); summary.added += 1
        }
        let cardKeys = Set(try context.fetch(FetchDescriptor<ReviewCard>()).map(\.key))
        for record in archive.cards {
            guard !cardKeys.contains(record.key) else { summary.skipped += 1; continue }
            let card = ReviewCard(key: record.key, kind: ReviewCardKind(rawValue: record.kind) ?? .mistake, sessionID: record.sessionID, subtype: record.subtype,
                                  prompt: record.prompt, answer: record.answer, explanation: record.explanation, context: record.context,
                                  category: record.category, severity: record.severity, createdAt: record.createdAt)
            card.box = record.box; card.dueDate = record.dueDate; card.reviewCount = record.reviewCount; card.lapseCount = record.lapseCount
            card.mastered = record.mastered; card.archived = record.archived; card.lastReviewedAt = record.lastReviewedAt
            context.insert(card); summary.added += 1
        }
        do { try context.save() } catch { context.rollback(); throw error }
        return summary
    }
    enum BackupError: LocalizedError {
        case unreadable, newerVersion
        var errorDescription: String? {
            switch self {
            case .unreadable: "无法读取这个文件。请选择 WriteBench 导出的备份 JSON。"
            case .newerVersion: "这个备份来自更新版本的 WriteBench，请先更新应用。"
            }
        }
    }
}

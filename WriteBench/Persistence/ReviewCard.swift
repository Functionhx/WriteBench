import Foundation
import SwiftData
import CryptoKit

/// A spaced-repetition card: either a correction from a review or a reusable expression.
@Model final class ReviewCard {
    @Attribute(.unique) var key: String
    var kind: String
    var sessionID: UUID?
    var subtype: String
    /// Mistake: the student's original span. Expression: the Chinese meaning.
    var prompt: String
    /// Mistake: the corrected span. Expression: the phrase.
    var answer: String
    var explanation: String
    /// Mistake: the sentence it came from. Expression: an example sentence.
    var context: String
    var category: String
    var severity: String
    var box: Int
    var dueDate: Date
    var reviewCount: Int
    var lapseCount: Int
    var mastered: Bool
    /// Hidden by the user; kept so the sync does not recreate it.
    var archived: Bool
    var createdAt: Date
    var lastReviewedAt: Date?

    init(key: String, kind: ReviewCardKind, sessionID: UUID?, subtype: String, prompt: String, answer: String, explanation: String,
         context: String, category: String = "", severity: String = "", createdAt: Date = Date()) {
        self.key = key; self.kind = kind.rawValue; self.sessionID = sessionID; self.subtype = subtype
        self.prompt = prompt; self.answer = answer; self.explanation = explanation; self.context = context
        self.category = category; self.severity = severity
        box = 0; dueDate = createdAt; reviewCount = 0; lapseCount = 0; mastered = false; archived = false
        self.createdAt = createdAt
    }
    var cardKind: ReviewCardKind { ReviewCardKind(rawValue: kind) ?? .mistake }
    var task: WritingTask? { WritingTask(rawValue: subtype) }
    var isDue: Bool { !mastered && !archived && dueDate <= Date() }
}

enum ReviewCardKind: String, Codable, Sendable { case mistake, expression }

enum ReviewGrade { case again, good }

enum SpacedRepetition {
    /// Days until the next review after each successful recall. Recalling a card after the longest interval masters it.
    static let intervals = [1, 2, 4, 8, 16]
    static func apply(_ grade: ReviewGrade, to card: ReviewCard, now: Date = Date()) {
        card.reviewCount += 1; card.lastReviewedAt = now
        switch grade {
        case .again:
            card.lapseCount += 1; card.box = 0
            card.dueDate = now.addingTimeInterval(10 * 60)
        case .good:
            if card.box >= intervals.count { card.mastered = true; card.dueDate = now; return }
            card.box += 1
            card.dueDate = Calendar.current.date(byAdding: .day, value: intervals[card.box - 1], to: now) ?? now
        }
    }
    static func setMastered(_ card: ReviewCard, _ mastered: Bool, now: Date = Date()) {
        card.mastered = mastered
        if !mastered { card.box = 0; card.dueDate = now }
    }
}

@MainActor enum ReviewCardSync {
    static func mistakeKey(session: UUID, correction: Correction) -> String { digest("mistake|\(session.uuidString)|\(correction.id)") }
    static func expressionKey(phrase: String) -> String { digest("expression|" + phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
    private static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// Creates cards for corrections and expressions in saved reviews that do not have one yet. Returns the number added.
    @discardableResult static func sync(_ context: ModelContext) throws -> Int {
        let existing = Set(try context.fetch(FetchDescriptor<ReviewCard>()).map(\.key))
        var added = 0, seen = existing
        for session in try context.fetch(FetchDescriptor<EssaySession>(sortBy: [SortDescriptor(\.date)])) where !session.isDemo {
            guard let report = session.report else { continue }
            for correction in report.corrections {
                let key = mistakeKey(session: session.id, correction: correction)
                guard seen.insert(key).inserted else { continue }
                let sentence = CorrectionMatcher.range(of: correction.original, in: session.originalEssay)
                    .map { CorrectionMatcher.sentence(containing: $0, in: session.originalEssay) } ?? correction.original
                context.insert(ReviewCard(key: key, kind: .mistake, sessionID: session.id, subtype: session.subtype, prompt: correction.original,
                    answer: correction.corrected, explanation: correction.explanation, context: sentence,
                    category: correction.category.rawValue, severity: correction.severity.rawValue, createdAt: session.date))
                added += 1
            }
            for expression in report.expressions {
                let key = expressionKey(phrase: expression.phrase)
                guard seen.insert(key).inserted else { continue }
                context.insert(ReviewCard(key: key, kind: .expression, sessionID: session.id, subtype: session.subtype, prompt: expression.meaning,
                    answer: expression.phrase, explanation: "", context: expression.example, createdAt: session.date))
                added += 1
            }
        }
        if added > 0 { try context.save() }
        return added
    }
    @discardableResult static func addExpression(phrase: String, meaning: String, example: String, task: WritingTask, in context: ModelContext) throws -> ReviewCard {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines), meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !meaning.isEmpty else { throw CardError.empty }
        let key = expressionKey(phrase: phrase)
        if let found = try context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.key == key })).first {
            found.archived = false; try context.save(); return found
        }
        let card = ReviewCard(key: key, kind: .expression, sessionID: nil, subtype: task.rawValue, prompt: meaning, answer: phrase, explanation: "",
                              context: example.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(card)
        do { try context.save() } catch { context.delete(card); throw error }
        return card
    }
    enum CardError: LocalizedError {
        case empty
        var errorDescription: String? { "请填写表达和中文释义。" }
    }
}

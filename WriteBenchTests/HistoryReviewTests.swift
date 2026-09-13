import Foundation
import SwiftData
import Testing
@testable import WriteBench

@MainActor private func historySession(question: String = "Invite Alex.\nInclude the time.", task: WritingTask = .kaoyanSmall,
                                      score: Double = 8, date: TimeInterval = 100, parent: UUID? = nil) throws -> EssaySession {
    let response = JudgeResponse(score: score, taskCompletion: 8, language: 7, coherence: 8, register: 9,
        majorErrors: ["Check the verb form."], minorErrors: [], summary: "Clear purpose, but revise the verb form.",
        corrections: [Correction(original: "look forward to hear", corrected: "look forward to hearing", category: .grammar,
            severity: .minor, explanation: "Use a gerund after to here.")], improvedVersion: "SEPARATE IMPROVED ESSAY BODY",
        strengths: ["Clear purpose."], weaknesses: ["Incorrect verb form."], improvements: ["Check gerunds after prepositions."])
    let reviewers = Judge.allCases.map { ReviewerResult(judge: $0, response: response, model: "test-fixture", timestamp: Date(), provider: .deepSeek) }
    let report = try ScoreAggregator.aggregate(reviewers, task: task, isDemo: false)
    let session = try EssaySession(task: task, question: question, essay: "SEPARATE ORIGINAL ESSAY BODY", duration: 100,
        inputMode: .typed, report: report, parentSessionID: parent)
    session.date = Date(timeIntervalSince1970: date)
    return session
}

@Test @MainActor func historyGroupsOldAttemptsWithoutInventingAncestry() throws {
    let first = try historySession(score: 4.5), second = try historySession(question: "\nInvite Alex.\r\nInclude the time.\n", score: 7.5, date: 200)
    let branch = try historySession(score: 8, date: 300, parent: first.id)
    let groups = EssayHistoryGroup.make(from: [branch, second, first])
    let group = try #require(groups.first)
    #expect(groups.count == 1)
    #expect(group.versions.map(\.id) == [first.id, second.id, branch.id])
    #expect(group.first.finalScore == 4.5 && group.latest.finalScore == 8)
    #expect(group.parentNumber(of: second) == nil)
    #expect(group.parentNumber(of: branch) == 1) // A branch must not claim to follow the latest version.
    #expect(first.parentSessionID == nil && second.parentSessionID == nil)
    #expect(first.originalEssay == "SEPARATE ORIGINAL ESSAY BODY")
    first.originalEssay = "An earlier draft containing a unique search term."
    #expect(group.matches(search: "UNIQUE SEARCH", exam: .kaoyan))
    #expect(group.versions.count == 3) // Matching an older draft keeps its full context.
    #expect(!group.matches(search: "missing query", exam: nil))
    #expect(!group.matches(search: "", exam: .cet6))
}

@Test @MainActor func historyKeepsDistinctTasksPromptsAndQuestionImagesSeparate() throws {
    let original = try historySession()
    let anotherTask = try historySession(task: .cet6Writing, date: 400)
    let anotherPrompt = try historySession(question: "Invite Sam.\nInclude the time.", date: 300)
    let imageA = try historySession(date: 200), imageB = try historySession(date: 210)
    imageA.questionImage = Data([1]); imageB.questionImage = Data([2])
    let demo = try historySession(date: 500); demo.isDemo = true
    let groups = EssayHistoryGroup.make(from: [original, anotherTask, anotherPrompt, imageA, imageB, demo])
    #expect(groups.count == 5)
    #expect(groups.first?.latest.id == anotherTask.id)
    #expect(groups.allSatisfy { $0.versions.count == 1 })
    let reordered = EssayHistoryGroup.make(from: [imageB, anotherPrompt, anotherTask, imageA, original])
    #expect(reordered.map(\.id) == groups.map(\.id))
}

@Test @MainActor func revisionParentsSurviveADiskStoreReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("writebench-history-test-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.store")
    let sourceID: UUID, revisionID: UUID
    do {
        let container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(url: url))
        let context = ModelContext(container), source = try historySession()
        let revision = try historySession(date: 200, parent: source.id)
        sourceID = source.id; revisionID = revision.id
        context.insert(source); context.insert(revision); try context.save()
    }
    let reopened = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, configurations: ModelConfiguration(url: url))
    let sessions = try ModelContext(reopened).fetch(FetchDescriptor<EssaySession>())
    #expect(sessions.first(where: { $0.id == sourceID })?.parentSessionID == nil)
    #expect(sessions.first(where: { $0.id == revisionID })?.parentSessionID == sourceID)
    #expect(EssayHistoryGroup.make(from: sessions).count == 1)
}

@Test @MainActor func reviewCopyContainsAssessmentAndLeavesEssayCopySeparate() throws {
    let session = try historySession(score: 7.5)
    let text = try #require(ReviewTextExporter.text(for: session))
    for required in ["7.5 / 10", "置信度：High", "Clear purpose.", "Incorrect verb form.", "Check gerunds", "Judge A", "Judge B", "Judge C", "look forward to hearing", "Use a gerund", "DeepSeek"] {
        #expect(text.contains(required))
    }
    #expect(!text.contains(session.originalEssay))
    #expect(!text.contains(session.correctedEssay))
    #expect(session.correctedEssay == "SEPARATE IMPROVED ESSAY BODY")
    var json = try #require(try JSONSerialization.jsonObject(with: session.reviewerResults) as? [String: Any])
    var reviewers = try #require(json["reviewers"] as? [[String: Any]])
    for index in reviewers.indices {
        var response = try #require(reviewers[index]["response"] as? [String: Any])
        for key in ["strengths", "weaknesses", "improvements"] { response.removeValue(forKey: key) }
        reviewers[index]["response"] = response
    }
    json["reviewers"] = reviewers
    session.reviewerResults = try JSONSerialization.data(withJSONObject: json)
    let legacy = try #require(ReviewTextExporter.text(for: session))
    #expect(legacy.contains("本次评阅未单列此项。"))
    #expect(legacy.contains("Check the verb form."))
    session.reviewerResults = Data("invalid".utf8)
    #expect(ReviewTextExporter.text(for: session) == nil)
}

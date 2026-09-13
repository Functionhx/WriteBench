import Foundation
import SwiftData

@Model final class EssaySession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var exam: String
    var subtype: String
    var question: String
    var originalEssay: String
    var correctedEssay: String
    var finalRewrite: String
    var writingDuration: Double
    var wordCount: Int
    var inputMode: String
    var reviewerResults: Data
    var finalScore: Double
    var confidence: String
    var detectedMistakes: Data
    var rubricVersion: String
    var graderPromptVersion: String
    var modelName: String
    var timestamp: Date
    var isDemo: Bool
    // Optional for lightweight migration of reviews saved before revision tracking.
    var parentSessionID: UUID? = nil
    @Attribute(.externalStorage) var questionImage: Data?
    @Attribute(.externalStorage) var sourceImages: Data?
    var task: WritingTask { WritingTask(rawValue: subtype) ?? .kaoyanSmall }
    var report: GradingReport? { try? JSONDecoder().decode(GradingReport.self, from: reviewerResults) }
    init(task: WritingTask, question: String, essay: String, duration: Double, inputMode: InputMode, report: GradingReport, questionImage: Data? = nil, sourceImages: [Data] = [], parentSessionID: UUID? = nil) throws {
        id = UUID(); date = Date(); exam = task.exam.rawValue; subtype = task.rawValue
        self.question = question; originalEssay = essay; correctedEssay = report.improvedVersion; finalRewrite = ""
        writingDuration = duration; wordCount = WordCounter.count(essay); self.inputMode = inputMode.rawValue
        reviewerResults = try JSONEncoder().encode(report); finalScore = report.finalScore; confidence = report.confidence.rawValue
        detectedMistakes = try JSONEncoder().encode(report.corrections); rubricVersion = report.rubricVersion; graderPromptVersion = report.promptVersion
        modelName = Array(Set(report.reviewers.map(\.model))).sorted().joined(separator: ", ")
        timestamp = report.timestamp; isDemo = report.isDemo; self.questionImage = questionImage
        self.parentSessionID = parentSessionID
        self.sourceImages = sourceImages.isEmpty ? nil : try JSONEncoder().encode(sourceImages)
    }
}

@Model final class WritingDraft {
    @Attribute(.unique) var subtype: String
    var question: String
    var questionLabel: String
    var essay: String
    var elapsed: Double
    var inputMode: String
    var updatedAt: Date
    var rewriteSessionID: UUID? = nil
    @Attribute(.externalStorage) var questionImage: Data?
    @Attribute(.externalStorage) var sourceImages: Data?
    init(task: WritingTask) {
        subtype = task.rawValue; question = task.sampleQuestion; questionLabel = "原创练习"; essay = ""; elapsed = 0; inputMode = "typed"; updatedAt = Date()
    }
}

@Model final class SavedQuestion {
    @Attribute(.unique) var id: UUID
    var title: String
    var subtype: String
    var prompt: String
    var date: Date
    @Attribute(.externalStorage) var image: Data?
    init(title: String, task: WritingTask, prompt: String, image: Data? = nil) { id = UUID(); self.title = title; subtype = task.rawValue; self.prompt = prompt; date = Date(); self.image = image }
}

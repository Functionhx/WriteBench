import Foundation
import SwiftData

/// Question-level organization, shared by every past and future attempt in the folder.
@Model final class EssayFolderMetadata {
    @Attribute(.unique) var key: String
    var title: String
    var questionYear: Int?
    var label: String
    var updatedAt: Date
    init(key: String, title: String = "", questionYear: Int? = nil, label: String = "") {
        self.key = key; self.title = title; self.questionYear = questionYear; self.label = label; updatedAt = Date()
    }
}

struct EssayFolderDetails {
    var title: String
    var year: Int?
    var label: String
    init(title: String, year: String, label: String) throws {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearText = year.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.title.count <= 100, self.label.count <= 32 else { throw DetailsError.tooLong }
        if yearText.isEmpty { self.year = nil }
        else {
            guard yearText.count == 4, yearText.allSatisfy(\.isASCII), let value = Int(yearText), (1000...2999).contains(value) else { throw DetailsError.year }
            self.year = value
        }
    }
    private enum DetailsError: LocalizedError {
        case year, tooLong
        var errorDescription: String? {
            switch self {
            case .year: "请填写四位年份，例如 2024；不需要时可留空。"
            case .tooLong: "名称请控制在 100 字以内，标签在 32 字以内。"
            }
        }
    }
    @MainActor func save(key: String, existing: EssayFolderMetadata?, in context: ModelContext) throws {
        let item = existing ?? EssayFolderMetadata(key: key)
        let previous = (item.title, item.questionYear, item.label, item.updatedAt)
        if existing == nil { context.insert(item) }
        item.title = title; item.questionYear = year; item.label = label; item.updatedAt = Date()
        do { try context.save() }
        catch {
            if existing == nil { context.delete(item) }
            else { (item.title, item.questionYear, item.label, item.updatedAt) = previous }
            throw error
        }
    }
}

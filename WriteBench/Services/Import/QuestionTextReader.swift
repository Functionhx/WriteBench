import Foundation

enum QuestionTextImportError: LocalizedError {
    case empty, tooLarge, unsupportedEncoding, invalidText

    var errorDescription: String? {
        switch self {
        case .empty: "请先粘贴或输入题目文字。"
        case .tooLarge: "题目文件过大，请选择不超过 1 MB 的文本文件。"
        case .unsupportedEncoding: "无法读取文件编码，请将文件另存为 UTF-8 或 UTF-16 后导入。"
        case .invalidText: "文件包含非文本内容，请选择 .txt 或 .md 文本文件。"
        }
    }
}

/// Reads only user-selected files, off the main actor. Never sends imported text to a provider.
actor QuestionTextReader {
    static let maximumBytes = 1_048_576

    func read(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: Self.maximumBytes + 1) ?? Data()
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> String {
        guard data.count <= maximumBytes else { throw QuestionTextImportError.tooLarge }
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) {
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard let text else { throw QuestionTextImportError.unsupportedEncoding }
        return try validated(text)
    }

    static func validated(_ text: String) throws -> String {
        guard text.utf8.count <= maximumBytes else { throw QuestionTextImportError.tooLarge }
        let withoutBOM = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let normalized = withoutBOM.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw QuestionTextImportError.empty }
        guard !normalized.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 9 && $0.value != 10 }) else {
            throw QuestionTextImportError.invalidText
        }
        return normalized
    }
}

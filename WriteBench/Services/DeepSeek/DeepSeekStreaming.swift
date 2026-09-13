import Foundation

protocol StreamingHTTPTransport: HTTPTransport {
    /// Return false from onEvent to close the response immediately after [DONE].
    func stream(for request: URLRequest, onEvent: @escaping @Sendable (String) async throws -> Bool) async throws
}

/// SSE framing is independent of network chunk boundaries and preserves UTF-8 and multi-line data.
struct ServerSentEvents {
    private var line = Data()
    private var fields: [String] = []
    private var eventBytes = 0
    mutating func append(_ byte: UInt8) throws -> String? {
        guard line.count < 1_048_576 else { throw GradingError.invalidResponse("流式消息过大") }
        guard byte == 10 else { line.append(byte); return nil }
        if line.last == 13 { line.removeLast() }
        guard let value = String(data: line, encoding: .utf8) else { throw GradingError.invalidResponse("流式消息编码无效") }
        line.removeAll(keepingCapacity: true)
        if value.isEmpty {
            guard !fields.isEmpty else { return nil }
            let event = fields.joined(separator: "\n")
            fields.removeAll(keepingCapacity: true); eventBytes = 0
            return event
        }
        if value.hasPrefix("data:") {
            var data = value.dropFirst(5)
            if data.first == " " { data = data.dropFirst() }
            eventBytes += data.utf8.count
            guard eventBytes <= 1_048_576 else { throw GradingError.invalidResponse("流式消息过大") }
            fields.append(String(data))
        }
        return nil
    }
}

actor DeepSeekStreamAccumulator {
    private var content = ""
    private var model: String?
    private var finishReason: String?
    private var done = false
    private var lastPreview = ""
    private var lastEmittedAt = Date.distantPast

    func consume(_ event: String, onPreview: @Sendable (String) async -> Void) async throws -> Bool {
        try Task.checkCancellation()
        if event == "[DONE]" { done = true; return false }
        let chunk: Chunk
        do { chunk = try JSONDecoder().decode(Chunk.self, from: Data(event.utf8)) }
        catch { throw GradingError.invalidResponse("流式消息格式无效") }
        if let name = chunk.model { model = name }
        guard chunk.choices.count <= 1 else { throw GradingError.invalidResponse("返回了多份评阅") }
        if let choice = chunk.choices.first {
            guard choice.index == 0 else { throw GradingError.invalidResponse("流式评阅序号无效") }
            if let delta = choice.delta.content {
                content += delta
                guard content.utf8.count <= 2_097_152 else { throw GradingError.invalidResponse("评阅内容过长") }
            }
            if let reason = choice.finish_reason { finishReason = reason }
            // reasoning_content is deliberately not decoded, retained, or displayed.
            if !content.isEmpty, lastPreview.isEmpty || Date().timeIntervalSince(lastEmittedAt) >= 0.12 || finishReason != nil {
                lastEmittedAt = Date()
                let preview = JSONSummaryPreview.extract(from: content)
                if !preview.isEmpty, preview != lastPreview {
                    lastPreview = preview
                    await onPreview(preview)
                }
            }
        }
        return true
    }
    func completed() throws -> (content: String, model: String) {
        guard done, finishReason == "stop", let model, !model.isEmpty, !content.isEmpty else {
            throw GradingError.invalidResponse("流式评阅中断或输出被截断")
        }
        return (content, model)
    }
    private struct Chunk: Decodable {
        let model: String?
        let choices: [Choice]
        struct Choice: Decodable {
            let index: Int
            let delta: Delta
            let finish_reason: String?
        }
        struct Delta: Decodable { let content: String? }
    }
}

/// Preview only a root JSON summary string. Incomplete previews never enter the grading decoder.
/// A small string tokenizer handles split escapes and surrogate pairs without regex or prose parsing.
enum JSONSummaryPreview {
    static func extract(from text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var index = 0, depth = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\"" {
                guard let token = string(in: scalars, at: index) else { return "" }
                index = token.next
                if depth == 1, token.complete, token.value == "summary" {
                    while index < scalars.count, CharacterSet.whitespacesAndNewlines.contains(scalars[index]) { index += 1 }
                    guard index < scalars.count, scalars[index] == ":" else { continue }
                    index += 1
                    while index < scalars.count, CharacterSet.whitespacesAndNewlines.contains(scalars[index]) { index += 1 }
                    guard index < scalars.count, scalars[index] == "\"", let value = string(in: scalars, at: index) else { return "" }
                    return String(value.value.prefix(4_000))
                }
                if !token.complete { return "" }
            } else {
                if scalar == "{" || scalar == "[" { depth += 1 }
                if scalar == "}" || scalar == "]" { depth -= 1 }
                index += 1
            }
        }
        return ""
    }
    private static func string(in s: [Unicode.Scalar], at start: Int) -> (value: String, next: Int, complete: Bool)? {
        var value = "", i = start + 1
        while i < s.count {
            if s[i] == "\"" { return (value, i + 1, true) }
            if s[i] == "\\" {
                i += 1
                guard i < s.count else { break }
                switch s[i] {
                case "\"", "\\", "/": value.unicodeScalars.append(s[i]); i += 1
                case "n": value += "\n"; i += 1
                case "r": value += "\r"; i += 1
                case "t": value += "\t"; i += 1
                case "b": value += "\u{08}"; i += 1
                case "f": value += "\u{0C}"; i += 1
                case "u":
                    guard i + 4 < s.count else { return (value, s.count, false) }
                    guard let first = UInt32(String(String.UnicodeScalarView(s[(i + 1)...(i + 4)])), radix: 16) else { return nil }
                    i += 5
                    var code = first
                    if (0xD800...0xDBFF).contains(first) {
                        guard i + 5 < s.count else { return (value, s.count, false) }
                        guard s[i] == "\\", s[i + 1] == "u", let second = UInt32(String(String.UnicodeScalarView(s[(i + 2)...(i + 5)])), radix: 16), (0xDC00...0xDFFF).contains(second) else { return nil }
                        code = 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00; i += 6
                    }
                    guard let decoded = Unicode.Scalar(code) else { return nil }
                    value.unicodeScalars.append(decoded)
                default: return nil
                }
            } else {
                guard s[i].value >= 32 else { return nil }
                value.unicodeScalars.append(s[i]); i += 1
            }
        }
        return (value, i, false)
    }
}

import Foundation
import Testing
@testable import WriteBench

@Test func sseFramesUTF8AcrossBytesCommentsAndMultilineEvents() throws {
    let source = ": keep-alive\r\nid: 1\r\ndata: {\"text\":\r\ndata: \"中文\"}\r\n\r\ndata: [DONE]\n\n"
    var parser = ServerSentEvents(), events: [String] = []
    for byte in source.utf8 { if let event = try parser.append(byte) { events.append(event) } }
    #expect(events == ["{\"text\":\n\"中文\"}", "[DONE]"])
}
@Test func streamedSummaryTokenizerHandlesPartialEscapesAndIgnoresNestedKeys() {
    #expect(JSONSummaryPreview.extract(from: #"{"summary":"任务已完成"#) == "任务已完成")
    #expect(JSONSummaryPreview.extract(from: #"{"summary":"Good\n\"work\" \u4e2d\u6587"#) == "Good\n\"work\" 中文")
    #expect(JSONSummaryPreview.extract(from: #"{"summary":"Keep \uD83D"#) == "Keep ")
    #expect(JSONSummaryPreview.extract(from: #"{"summary":"Keep \uD83D\uDC4D"#) == "Keep 👍")
    #expect(JSONSummaryPreview.extract(from: #"{"summary":"Keep \u4e"#) == "Keep ")
    #expect(JSONSummaryPreview.extract(from: #"{"corrections":[{"summary":"ignored"}],"summary":"Actual verdict"}"#) == "Actual verdict")
    #expect(JSONSummaryPreview.extract(from: #"{"corrections":[{"summary":"ignored"}]}"#).isEmpty)
}
private actor PreviewRecorder {
    var values: [String] = []
    func append(_ value: String) { values.append(value) }
}
private func chunk(_ content: String? = nil, reasoning: String? = nil, finish: String? = nil) throws -> String {
    var delta: [String: String] = [:]
    if let content { delta["content"] = content }
    if let reasoning { delta["reasoning_content"] = reasoning }
    let json: [String: Any] = ["model": "stream-fixture", "choices": [["index": 0, "delta": delta, "finish_reason": finish as Any? ?? NSNull()]]]
    return String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
}
private actor StreamFixture: StreamingHTTPTransport {
    let events: [String]
    var requests: [URLRequest] = []
    init(events: [String]) { self.events = events }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.unsupportedURL) }
    func stream(for request: URLRequest, onEvent: @escaping @Sendable (String) async throws -> Bool) async throws {
        requests.append(request)
        for event in events {
            try Task.checkCancellation()
            if try await !onEvent(event) { return }
        }
    }
}
private let streamedInput = GradingInput(task: .kaoyanSmall, question: "Invite Alex.", essay: "Dear Alex, please come. Yours, Li Ming.", rubric: "Test")
private let responseTail = #", but check tense.","score":8,"taskCompletion":8,"language":8,"coherence":8,"register":8,"majorErrors":[],"minorErrors":[],"corrections":[],"improvedVersion":"Dear Alex, please come. Yours, Li Ming.","strengths":["Clear invitation."],"weaknesses":["Check tense."],"improvements":["Review each verb."]}"#

@Test func deepSeekStreamsARealPreviewBeforeDecodingCompleteStructuredFeedback() async throws {
    let prefix = #"{"summary":"Task completed"#
    let transport = try StreamFixture(events: [chunk(reasoning: "PRIVATE_REASONING_SHOULD_NOT_APPEAR"), chunk(prefix), chunk(responseTail, finish: "stop"), "[DONE]"])
    let previews = PreviewRecorder()
    let result = try await DeepSeekClient(apiKey: "fixture-key", model: "fixture", transport: transport).grade(streamedInput, judge: .b) { await previews.append($0) }
    #expect(await previews.values.first == "Task completed")
    #expect(await previews.values.last == "Task completed, but check tense.")
    #expect(await previews.values.allSatisfy { !$0.contains("PRIVATE_REASONING") })
    #expect(result.response.score == 8 && result.response.strengths == ["Clear invitation."])
    #expect(result.response.improvements == ["Review each verb."])
    let request = try #require(await transport.requests.first)
    let data = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["stream"] as? Bool == true)
    #expect(body["reasoning_effort"] as? String == "max")
}
@Test func interruptedTruncatedOrMalformedStreamsNeverProduceAScore() async throws {
    let content = #"{"summary":"Task completed"# + responseTail
    let cases = try [[chunk(content, finish: "stop")], [chunk(content, finish: "length"), "[DONE]"], [chunk("{", finish: "stop"), "[DONE]"], ["not JSON", "[DONE]"]]
    for events in cases {
        let client = DeepSeekClient(apiKey: "fixture-key", model: "fixture", transport: StreamFixture(events: events))
        await #expect(throws: (any Error).self) { try await client.grade(streamedInput, judge: .a) }
    }
}
@Test func historicalFeedbackDecodesButNewProviderOutputRequiresAllFeedbackSections() throws {
    let complete = #"{"summary":"Task completed"# + responseTail
    var json = try #require(JSONSerialization.jsonObject(with: Data(complete.utf8)) as? [String: Any])
    for field in ["strengths", "weaknesses", "improvements"] { json.removeValue(forKey: field) }
    let legacy = try JSONSerialization.data(withJSONObject: json)
    #expect(try JSONDecoder().decode(JudgeResponse.self, from: legacy).strengths.isEmpty)
    #expect(throws: (any Error).self) { try JudgeResponse.decodeProviderOutput(legacy) }
}

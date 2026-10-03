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

@Test func providerAcceptsNumericStringsAndEmptyOptionalErrorLists() throws {
    let complete = #"{"summary":"Task completed"# + responseTail
    var json = try #require(JSONSerialization.jsonObject(with: Data(complete.utf8)) as? [String: Any])
    for field in ["score", "taskCompletion", "language", "coherence", "register"] { json[field] = "8.5" }
    json["majorErrors"] = NSNull(); json.removeValue(forKey: "minorErrors"); json["corrections"] = NSNull()
    let decoded = try JudgeResponse.decodeProviderOutput(JSONSerialization.data(withJSONObject: json))
    #expect(decoded.score == 8.5 && decoded.language == 8.5)
    #expect(decoded.majorErrors.isEmpty && decoded.minorErrors.isEmpty && decoded.corrections.isEmpty)
    json.removeValue(forKey: "score")
    do { _ = try JudgeResponse.decodeProviderOutput(JSONSerialization.data(withJSONObject: json)); Issue.record("Missing score must fail") }
    catch { #expect(error.localizedDescription.contains("score")) }
}
private actor ReviewSequenceTransport: HTTPTransport {
    let contents: [String]
    var requests: [URLRequest] = []
    init(_ contents: [String]) { self.contents = contents }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let content = contents[min(requests.count, contents.count - 1)]
        requests.append(request)
        let json: [String: Any] = ["model": "fixture", "choices": [["finish_reason": "stop", "message": ["content": content]]], "usage": ["prompt_tokens": 10, "completion_tokens": 20]]
        return (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
@Test func malformedCompletedReviewRetriesOnceAndCountsBothRequests() async throws {
    let complete = #"{"summary":"Task completed"# + responseTail
    let transport = ReviewSequenceTransport([#"{"summary":"Preview alone is not a score"}"#, complete])
    let result = try await DeepSeekClient(apiKey: "fixture", model: "fixture", transport: transport).grade(streamedInput, judge: .a)
    #expect(result.response.score == 8)
    #expect(result.usage?.input == 20 && result.usage?.output == 40)
    let requests = await transport.requests
    #expect(requests.count == 2)
    let body = try #require(requests.last?.httpBody)
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(payload["messages"] as? [[String: String]])
    #expect(messages[0]["content"]?.contains("previous completed response") == true)
}
@Test func malformedReviewRetryIsBoundedAndStillRequiresAScore() async throws {
    let transport = ReviewSequenceTransport([#"{"summary":"Looks like 18.5 but has no structured score"}"#])
    let client = DeepSeekClient(apiKey: "fixture", model: "fixture", transport: transport)
    await #expect(throws: (any Error).self) { try await client.grade(streamedInput, judge: .a) }
    #expect(await transport.requests.count == 2)
}

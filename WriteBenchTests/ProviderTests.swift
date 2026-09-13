import Foundation
import Testing
@testable import WriteBench

private func fixtureInput() -> GradingInput {
    GradingInput(task: .kaoyanSmall, question: "Invite Alex to a lecture.", essay: "Dear Alex, Please join the lecture. Yours, Li Ming.", rubric: "Test rubric")
}
private func fixtureResponse() -> JudgeResponse {
    JudgeResponse(score: 8, taskCompletion: 8, language: 8, coherence: 8, register: 8, majorErrors: [], minorErrors: [], summary: "A valid fixture", corrections: [], improvedVersion: fixtureInput().essay)
}
private actor ProviderRecorder: EssayGradingService {
    var judges: [Judge] = []
    var evidence: [String] = []
    let shouldFail: Bool
    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }
    func grade(_ input: GradingInput, judge: Judge) async throws -> ReviewerResult {
        judges.append(judge); evidence.append(input.essay)
        if shouldFail { throw CodexError.quota }
        return ReviewerResult(judge: judge, response: fixtureResponse(), model: "fixture", timestamp: Date())
    }
}
@Test func heterogeneousJudgesRouteIndependentlyAndPreserveProvider() async throws {
    let deepSeek = ProviderRecorder(), codex = ProviderRecorder()
    let router = ProviderRouter(configuration: .init(), deepSeek: deepSeek, codex: codex)
    let report = try await GradingCoordinator(service: router).grade(fixtureInput(), isDemo: false)
    #expect(Set(await deepSeek.judges) == Set([.a, .b]))
    #expect(await codex.judges == [.c])
    #expect(await codex.evidence == [fixtureInput().essay])
    #expect(report.reviewers.map(\.provider) == [.deepSeek, .deepSeek, .codex])
    let stored = try JSONDecoder().decode(GradingReport.self, from: JSONEncoder().encode(report))
    #expect(stored.reviewers.last?.provider == .codex)
}
@Test func providerFailureNamesJudgeAndNeverFallsBack() async throws {
    let deepSeek = ProviderRecorder(), codex = ProviderRecorder(shouldFail: true)
    let router = ProviderRouter(configuration: .init(), deepSeek: deepSeek, codex: codex)
    do { _ = try await router.grade(fixtureInput(), judge: .c); Issue.record("Expected quota failure") }
    catch { #expect(error.localizedDescription.contains("Judge C")); #expect(error.localizedDescription.contains("额度")) }
    #expect(await deepSeek.judges.isEmpty)
}
private actor CodexFixtureRunner: ProcessRunning {
    var requests: [ProcessRequest] = []
    let malformed: Bool
    init(malformed: Bool = false) { self.malformed = malformed }
    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        requests.append(request)
        if request.arguments == ["--version"] { return ProcessResult(status: 0, stdout: Data("codex-cli 0.154.0".utf8), stderr: Data()) }
        if request.arguments == ["exec", "--help"] { return ProcessResult(status: 0, stdout: Data("--ephemeral --output-schema --ignore-user-config".utf8), stderr: Data()) }
        if request.arguments == ["login", "status"] { return ProcessResult(status: 0, stdout: Data(), stderr: Data("Logged in using ChatGPT".utf8)) }
        let data = malformed ? Data("not JSON".utf8) : try JSONEncoder().encode(fixtureResponse())
        try data.write(to: request.directory.appendingPathComponent("response.json"))
        return ProcessResult(status: 0, stdout: Data(), stderr: Data())
    }
}
@Test func codexUsesSchemaStdinEphemeralAndMaxWithoutAuthenticationFiles() async throws {
    let runner = CodexFixtureRunner()
    let client = CodexJudgeService(executable: URL(fileURLWithPath: "/usr/bin/true"), runner: runner)
    let result = try await client.grade(fixtureInput(), judge: .c)
    let request = try #require(await runner.requests.first)
    #expect(request.arguments.contains("--ephemeral"))
    #expect(request.arguments.contains("--ignore-user-config"))
    #expect(request.arguments.contains("--output-schema"))
    #expect(request.arguments.contains("model_reasoning_effort=\"max\""))
    #expect(request.arguments.contains("forced_login_method=\"chatgpt\""))
    #expect(request.arguments.contains("gpt-6-astra"))
    #expect(!request.arguments.joined().contains(fixtureInput().essay)) // Essay is stdin, never process arguments.
    #expect(String(decoding: request.input, as: UTF8.self).contains("Judge C"))
    #expect(!FileManager.default.fileExists(atPath: request.directory.path))
    #expect(result.provider == .codex && result.reasoningEffort == "max")
    _ = try await client.grade(fixtureInput(), judge: .a)
    let paths = await runner.requests.map(\.directory)
    #expect(Set(paths).count == 2)
}
@Test func codexRejectsMalformedJSONAndRecognizesQuota() async throws {
    let client = CodexJudgeService(executable: URL(fileURLWithPath: "/usr/bin/true"), runner: CodexFixtureRunner(malformed: true))
    await #expect(throws: CodexError.self) { try await client.grade(fixtureInput(), judge: .a) }
    let error = CodexError.from(ProcessResult(status: 1, stdout: Data(), stderr: Data("You've hit your usage limit".utf8)))
    #expect(error.localizedDescription.contains("额度"))
}
@Test func codexConnectionChecksOfficialStatusWithoutReadingCredentials() async throws {
    let runner = CodexFixtureRunner()
    let connection = try await CodexJudgeService.checkConnection(customPath: "/usr/bin/true", runner: runner)
    #expect(connection.version == "codex-cli 0.154.0")
    #expect(await runner.requests.map(\.arguments) == [["--version"], ["exec", "--help"], ["login", "status"]])
}
@Test func processTimeoutAndCancellationTerminateTheSubprocess() async throws {
    let request = ProcessRequest(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], directory: FileManager.default.temporaryDirectory, timeout: 0.1)
    let start = Date()
    await #expect(throws: CodexError.self) { try await LocalProcessRunner().run(request) }
    #expect(Date().timeIntervalSince(start) < 3)
    var longRequest = request; longRequest.timeout = 30
    let task = Task { try await LocalProcessRunner().run(longRequest) }
    try await Task.sleep(for: .milliseconds(150)); task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}
@Test func schemaAndLegacyReviewerDecodingStayCompatible() throws {
    let schema = try #require(JSONSerialization.jsonObject(with: JudgeResponseSchema.data()) as? [String: Any])
    let responseJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixtureResponse())) as? [String: Any])
    #expect(Set(schema["required"] as? [String] ?? []) == Set(responseJSON.keys))
    let reviewer = ReviewerResult(judge: .a, response: fixtureResponse(), model: "legacy", timestamp: Date())
    let decoded = try JSONDecoder().decode(ReviewerResult.self, from: JSONEncoder().encode(reviewer))
    #expect(decoded.provider == nil)
}

@Test @MainActor func pastedKeyWorksWithoutKeychainOrPersistentPreferences() throws {
    defer { DeepSeekCredentials.clearSession() }
    try DeepSeekCredentials.use("  local-test-only-placeholder  ", remember: false)
    #expect(DeepSeekCredentials.hasSessionKey)
    #expect(try DeepSeekCredentials.load() == "local-test-only-placeholder")
    #expect(UserDefaults.standard.string(forKey: "deepSeekAPIKey") == nil)
    DeepSeekCredentials.clearSession()
    #expect(!DeepSeekCredentials.hasSessionKey)
}

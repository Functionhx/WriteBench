import Foundation

enum GradingProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepSeek, codex
    var id: String { rawValue }
    var title: String { self == .deepSeek ? "DeepSeek" : "ChatGPT · via Codex" }
}
struct JudgeProviderError: LocalizedError {
    let judge: Judge
    let provider: GradingProvider
    let detail: String
    var errorDescription: String? { "\(judge.title) · \(provider.title)\n\(detail)\n本次未生成总分，作文草稿已保留。" }
}
struct GradingConfiguration: Sendable {
    var a: GradingProvider = .deepSeek
    var b: GradingProvider = .deepSeek
    var c: GradingProvider = .codex
    var deepSeekModel = DeepSeekClient.defaultModel
    var codexModel = CodexJudgeService.defaultModel
    var codexReasoning = "max"
    var codexPath = ""
    func provider(for judge: Judge) -> GradingProvider { switch judge { case .a: a; case .b: b; case .c: c } }
    var requiresDeepSeek: Bool { Judge.allCases.contains { provider(for: $0) == .deepSeek } }
    var requiresCodex: Bool { Judge.allCases.contains { provider(for: $0) == .codex } }
    @MainActor static func load(_ defaults: UserDefaults = .standard) -> Self {
        Self(a: GradingProvider(rawValue: defaults.string(forKey: "judgeProviderA") ?? "") ?? .deepSeek,
             b: GradingProvider(rawValue: defaults.string(forKey: "judgeProviderB") ?? "") ?? .deepSeek,
             c: GradingProvider(rawValue: defaults.string(forKey: "judgeProviderC") ?? "") ?? .codex,
             deepSeekModel: defaults.string(forKey: "deepSeekModel") ?? DeepSeekClient.defaultModel,
             codexModel: defaults.string(forKey: "codexModel") ?? CodexJudgeService.defaultModel,
             codexReasoning: defaults.string(forKey: "codexReasoning") ?? "max",
             codexPath: defaults.string(forKey: "codexExecutablePath") ?? "")
    }
}
struct ProviderRouter: StreamingEssayGradingService {
    let configuration: GradingConfiguration
    let deepSeek: (any EssayGradingService)?
    let codex: (any EssayGradingService)?
    func grade(_ input: GradingInput, judge: Judge, onPreview: @escaping @Sendable (String) async -> Void) async throws -> ReviewerResult {
        let provider = configuration.provider(for: judge)
        do {
            guard let service = provider == .deepSeek ? deepSeek : codex else { throw GradingError.incomplete }
            var result: ReviewerResult
            if let streaming = service as? any StreamingEssayGradingService {
                result = try await streaming.grade(input, judge: judge, onPreview: onPreview)
            } else { result = try await service.grade(input, judge: judge) }
            result.provider = provider
            return result
        } catch is CancellationError { throw CancellationError() }
        catch { throw JudgeProviderError(judge: judge, provider: provider, detail: error.localizedDescription) }
    }
}

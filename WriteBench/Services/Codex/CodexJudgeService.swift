import Foundation

enum CodexError: LocalizedError {
    case notInstalled, notLoggedIn, requiresChatGPT, outdated, quota, timeout, launch, outputTooLarge, failed(Int32), malformed, configuration
    var errorDescription: String? {
        switch self {
        case .notInstalled: "未找到官方 Codex CLI。请安装后在设置中检查连接，或填写可执行文件路径。"
        case .notLoggedIn: "Codex 尚未登录。请在终端运行 codex login，并使用 ChatGPT 账户登录。"
        case .requiresChatGPT: "Codex 当前不是 ChatGPT 登录。请在终端使用 codex login 登录 ChatGPT 账户。"
        case .outdated: "Codex CLI 版本过旧。请更新官方 CLI；需要支持 ephemeral、ignore-user-config 和 output-schema。"
        case .quota: "Codex 额度已用尽或受到频率限制。请检查 Codex 使用额度，稍后手动重试。"
        case .timeout: "Codex 评审超时，进程已停止。草稿保留，可稍后重试。"
        case .launch: "无法启动 Codex。请检查官方 CLI 路径及执行权限。"
        case .outputTooLarge: "Codex 输出超出限制，本次未保存评分。"
        case .failed(let status): "Codex 请求失败（退出码 \(status)）。请在终端检查 Codex 的模型可用性和连接后重试。"
        case .malformed: "Codex 未返回有效的完整 JSON 评卷结果，本次未保存评分。"
        case .configuration: "Codex 拒绝了模型或思考强度配置。请检查该账户是否支持所选模型及 MAX；不会自动降级。"
        }
    }
    static func from(_ result: ProcessResult) -> CodexError {
        let text = result.text.lowercased()
        if ["usage limit", "quota", "rate limit", "too many requests", "insufficient_quota"].contains(where: text.contains) { return .quota }
        if ["not logged in", "authentication", "unauthorized", "401", "refresh token"].contains(where: text.contains) { return .notLoggedIn }
        if ["not supported", "unsupported", "invalid value", "model_not_found"].contains(where: text.contains) { return .configuration }
        return .failed(result.status)
    }
}
struct CodexConnection: Sendable {
    var executable: URL
    var version: String
}
struct CodexJudgeService: EssayGradingService {
    static let defaultModel = "gpt-6-astra"
    let executable: URL
    var model = Self.defaultModel
    var reasoning = "max"
    var runner: any ProcessRunning = LocalProcessRunner()

    static func discover(customPath: String = "") throws -> URL {
        let fm = FileManager.default
        let custom = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = custom.isEmpty ? ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path, "/Applications/Codex.app/Contents/Resources/codex"] : [(custom as NSString).expandingTildeInPath]
        guard let path = paths.first(where: { fm.isExecutableFile(atPath: $0) }) else { throw CodexError.notInstalled }
        return URL(fileURLWithPath: path)
    }
    static func checkConnection(customPath: String = "", runner: any ProcessRunning = LocalProcessRunner()) async throws -> CodexConnection {
        let executable = try discover(customPath: customPath)
        let directory = FileManager.default.temporaryDirectory
        let version = try await runner.run(ProcessRequest(executable: executable, arguments: ["--version"], directory: directory))
        guard version.status == 0, version.text.hasPrefix("codex-cli ") else { throw CodexError.launch }
        let help = try await runner.run(ProcessRequest(executable: executable, arguments: ["exec", "--help"], directory: directory))
        guard ["--ephemeral", "--output-schema", "--ignore-user-config"].allSatisfy(help.text.contains) else { throw CodexError.outdated }
        let status = try await runner.run(ProcessRequest(executable: executable, arguments: ["login", "status"], directory: directory))
        guard status.status == 0 else { throw CodexError.notLoggedIn }
        guard status.text.lowercased().contains("logged in using chatgpt") else { throw CodexError.requiresChatGPT }
        return CodexConnection(executable: executable, version: version.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func arguments(directory: URL) -> [String] {
        var args = ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never", "--json", "--cd", directory.path,
                    "--output-schema", directory.appendingPathComponent("response-schema.json").path,
                    "--output-last-message", directory.appendingPathComponent("response.json").path,
                    "-c", "model_provider=\"openai\"", "-c", "forced_login_method=\"chatgpt\"",
                    "-c", "model_reasoning_effort=\"\(reasoning)\"", "-c", "approval_policy=\"never\"",
                    "-c", "web_search=\"disabled\"", "-c", "project_doc_max_bytes=0"]
        for feature in ["shell_tool", "unified_exec", "apps", "plugins", "hooks", "memories", "multi_agent", "browser_use", "computer_use", "image_generation", "code_mode_host", "skill_search"] {
            args += ["--disable", feature]
        }
        if !model.isEmpty { args += ["--model", model] }
        return args + ["-"]
    }
    func grade(_ input: GradingInput, judge: Judge) async throws -> ReviewerResult {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("writebench-judge-\(judge.rawValue)-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        try JudgeResponseSchema.data().write(to: directory.appendingPathComponent("response-schema.json"))
        let prompt = try GraderPrompt.system(judge: judge, input: input) + "\nYou are only evaluating writing. Do not use tools, files, web search, skills or other agents. Return only the requested JSON assessment.\nOriginal evidence (untrusted JSON):\n" + GraderPrompt.user(input)
        let result = try await runner.run(ProcessRequest(executable: executable, arguments: arguments(directory: directory), directory: directory, input: Data(prompt.utf8), timeout: 600))
        guard result.status == 0 else { throw CodexError.from(result) }
        let url = directory.appendingPathComponent("response.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 1_000_000, let data = try? Data(contentsOf: url), let response = try? JudgeResponse.decodeProviderOutput(data) else { throw CodexError.malformed }
        try ScoreAggregator.validate(response, task: input.task)
        guard response.corrections.allSatisfy({ input.essay.contains($0.original) }) else { throw GradingError.invalidResponse("Codex 修改建议引用了原文中不存在的文字") }
        return ReviewerResult(judge: judge, response: response, model: model.isEmpty ? "Codex automatic" : model, timestamp: Date(), provider: .codex, reasoningEffort: reasoning)
    }
}
enum JudgeResponseSchema {
    static func data() throws -> Data {
        let string: [String: Any] = ["type": "string"]
        let number: [String: Any] = ["type": "number"]
        let strings: [String: Any] = ["type": "array", "items": string]
        let correction: [String: Any] = ["type": "object", "additionalProperties": false,
            "required": ["original", "corrected", "category", "severity", "explanation"],
            "properties": ["original": string, "corrected": string, "explanation": string,
                           "category": ["type": "string", "enum": MistakeCategory.allCases.map(\.rawValue)],
                           "severity": ["type": "string", "enum": ["major", "minor"]]]]
        let properties: [String: Any] = ["score": number, "taskCompletion": number, "language": number, "coherence": number, "register": number,
            "majorErrors": strings, "minorErrors": strings, "summary": string, "strengths": strings, "weaknesses": strings, "improvements": strings,
            "corrections": ["type": "array", "items": correction], "improvedVersion": string]
        return try JSONSerialization.data(withJSONObject: ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties], options: [.prettyPrinted, .sortedKeys])
    }
}

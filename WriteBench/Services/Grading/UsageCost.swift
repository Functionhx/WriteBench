import Foundation

/// Estimated DeepSeek spend from user-entered prices. Codex runs on the ChatGPT plan, so it reports tokens only.
enum UsageCost {
    static let inputKey = "deepSeekPriceInput", cachedKey = "deepSeekPriceCachedInput", outputKey = "deepSeekPriceOutput"

    struct Prices: Sendable {
        var input: Double
        var cached: Double
        var output: Double
        var isSet: Bool { input > 0 || cached > 0 || output > 0 }
        static func load(_ defaults: UserDefaults = .standard) -> Self {
            Self(input: defaults.double(forKey: inputKey), cached: defaults.double(forKey: cachedKey), output: defaults.double(forKey: outputKey))
        }
    }
    /// Yuan for one DeepSeek usage record, or nil when prices are not set.
    static func cost(_ usage: TokenUsage, prices: Prices = .load()) -> Double? {
        guard prices.isSet else { return nil }
        let cached = min(usage.cachedInput, usage.input)
        let input: Double = Double(usage.input - cached) * prices.input
        let hits: Double = Double(cached) * prices.cached
        let output: Double = Double(usage.output) * prices.output
        return (input + hits + output) / 1_000_000
    }
    static func cost(_ report: GradingReport, prices: Prices = .load()) -> Double? {
        let deepSeek = report.reviewers.filter { $0.provider == .deepSeek }.compactMap(\.usage)
        guard prices.isSet, !deepSeek.isEmpty else { return nil }
        return deepSeek.compactMap { cost($0, prices: prices) }.reduce(0, +)
    }
    static func tokens(_ count: Int) -> String {
        count >= 1_000_000 ? String(format: "%.2fM", Double(count) / 1_000_000) : count >= 1_000 ? String(format: "%.1fk", Double(count) / 1_000) : "\(count)"
    }
    static func yuan(_ value: Double) -> String { value < 0.01 ? "< ¥0.01" : String(format: "¥%.2f", value) }
    static func summary(_ usage: TokenUsage) -> String {
        var parts = ["输入 \(tokens(usage.input))"]
        if usage.cachedInput > 0 { parts[0] += "（缓存 \(tokens(usage.cachedInput))）" }
        parts.append("输出 \(tokens(usage.output))")
        if let reasoning = usage.reasoning, reasoning > 0 { parts.append("其中思考 \(tokens(reasoning))") }
        return parts.joined(separator: " · ")
    }
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60) 分 \(total % 60) 秒" : "\(total) 秒"
    }
}

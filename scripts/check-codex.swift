import Foundation

// Explicit, opt-in live smoke check. Uses only a synthetic essay and the official CLI.
@main struct CheckCodex {
    static func main() async throws {
        let connection = try await CodexJudgeService.checkConnection()
        let rubric = try String(contentsOfFile: "WriteBench/Rubrics/kaoyan_english1_small.md", encoding: .utf8)
        let input = GradingInput(task: .kaoyanSmall, question: WritingTask.kaoyanSmall.sampleQuestion,
            essay: "Dear Alex, I am writing to invite you to a lecture on Chinese culture at our university. It will begin at 3 p.m. this Friday in the main library. Professor Wang will discuss the history of Chinese tea and demonstrate a traditional tea ceremony. Since you enjoy learning about local traditions, I believe you will find it interesting. There will also be a tea tasting after the talk. Please let me know if you can attend. I look forward to hear from you. Yours, Li Ming.", rubric: rubric)
        let result = try await CodexJudgeService(executable: connection.executable).grade(input, judge: .c)
        print("Official CLI: \(connection.version); model: \(result.model); reasoning: \(result.reasoningEffort ?? "unknown"); score: \(result.response.score); corrections: \(result.response.corrections.count)")
        let output = URL(fileURLWithPath: "Documentation/codex-live-check.json")
        try JSONEncoder().encode(result).write(to: output)
    }
}

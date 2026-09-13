import Foundation

enum Exam: String, CaseIterable, Identifiable, Codable, Sendable {
    case kaoyan, cet6, ielts
    var id: String { rawValue }
    var title: String { switch self { case .kaoyan: "考研英语"; case .cet6: "CET-6"; case .ielts: "IELTS" } }
    var symbol: String { switch self { case .kaoyan: "graduationcap"; case .cet6: "book"; case .ielts: "globe" } }
    var detail: String { switch self { case .kaoyan: "英语一 · 小作文 / 大作文"; case .cet6: "Writing"; case .ielts: "Academic · Task 1 / Task 2" } }
    var tasks: [WritingTask] { WritingTask.allCases.filter { $0.exam == self } }
}

enum WritingTask: String, CaseIterable, Identifiable, Codable, Sendable {
    case kaoyanSmall, kaoyanLarge, cet6Writing, ieltsTask1, ieltsTask2
    var id: String { rawValue }
    var exam: Exam {
        switch self { case .kaoyanSmall, .kaoyanLarge: .kaoyan; case .cet6Writing: .cet6; case .ieltsTask1, .ieltsTask2: .ielts }
    }
    var title: String {
        switch self { case .kaoyanSmall: "小作文"; case .kaoyanLarge: "大作文"; case .cet6Writing: "Writing"; case .ieltsTask1: "Task 1"; case .ieltsTask2: "Task 2" }
    }
    var fullTitle: String { "\(exam.title) · \(title)" }
    var maxScore: Double { switch self { case .kaoyanSmall: 10; case .kaoyanLarge: 20; case .cet6Writing: 15; case .ieltsTask1, .ieltsTask2: 9 } }
    var targetWords: Int { switch self { case .kaoyanSmall: 100; case .kaoyanLarge: 200; case .cet6Writing: 180; case .ieltsTask1: 150; case .ieltsTask2: 250 } }
    var wordGuidance: String { switch self { case .kaoyanSmall: "About 100 words"; case .kaoyanLarge: "160–200 words"; case .cet6Writing: "150–200 words"; case .ieltsTask1: "At least 150 words"; case .ieltsTask2: "At least 250 words" } }
    var suggestedMinutes: Int { switch self { case .kaoyanSmall: 15; case .kaoyanLarge, .cet6Writing: 30; case .ieltsTask1: 20; case .ieltsTask2: 40 } }
    var rubricFile: String {
        switch self { case .kaoyanSmall: "kaoyan_english1_small"; case .kaoyanLarge: "kaoyan_english1_large"; case .cet6Writing: "cet6_writing"; case .ieltsTask1: "ielts_task1"; case .ieltsTask2: "ielts_task2" }
    }
    var sampleQuestion: String {
        switch self {
        case .kaoyanSmall:
            "You are organising a lecture on Chinese culture at your university. Write a letter to your foreign friend Alex, inviting them to attend. Include the following details:\n1. The time and place\n2. The topic of the lecture\n3. Why you think they would enjoy it\nWrite about 100 words. Use “Li Ming” instead of your own name."
        case .kaoyanLarge:
            "A drawing shows two students approaching the same mountain. One looks only at its height; the other starts climbing one step at a time. Write an essay in which you describe the drawing, interpret its message, and give your comments. Write 160–200 words."
        case .cet6Writing:
            "For this part, you are allowed 30 minutes to write an essay on the importance of developing independent thinking at university. Support your view with reasons and examples. Write at least 150 words but no more than 200 words."
        case .ieltsTask1:
            "The table below shows the percentage of commuters using three forms of transport in a city. Summarise the information by selecting and reporting the main features, and make comparisons where relevant.\n\nTransport — 2000 → 2020\nCar: 60% → 45%\nPublic transport: 30% → 40%\nBicycle: 10% → 15%\n\nWrite at least 150 words."
        case .ieltsTask2:
            "Some people believe that universities should focus on preparing students for employment. Others believe that universities should provide knowledge for its own sake. Discuss both views and give your own opinion. Write at least 250 words."
        }
    }
}

enum InputMode: String, Codable, Sendable { case typed, handwritten }

enum WordCounter {
    static func count(_ text: String) -> Int {
        let pattern = #"[A-Za-z0-9]+(?:[’'\-][A-Za-z0-9]+)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

extension Double {
    var scoreText: String { formatted(.number.precision(.fractionLength(1))) }
}

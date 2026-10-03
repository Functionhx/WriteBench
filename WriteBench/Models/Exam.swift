import Foundation

enum Exam: String, CaseIterable, Identifiable, Codable, Sendable {
    case kaoyan, cet6, ielts
    var id: String { rawValue }
    var title: String { switch self { case .kaoyan: "考研英语"; case .cet6: "CET-6 六级"; case .ielts: "IELTS 雅思" } }
    var symbol: String { switch self { case .kaoyan: "graduationcap"; case .cet6: "book"; case .ielts: "globe" } }
    var detail: String { switch self { case .kaoyan: "英语一 / 二 · 大小作文与翻译"; case .cet6: "写作 / 翻译"; case .ielts: "Academic · Task 1 / Task 2" } }
    var tasks: [WritingTask] { WritingTask.allCases.filter { $0.exam == self } }
}

enum WritingTask: String, CaseIterable, Identifiable, Codable, Sendable {
    case kaoyanSmall, kaoyanLarge, kaoyan2Small, kaoyan2Large, kaoyanTranslation, kaoyan2Translation, cet6Writing, cet6Translation, ieltsTask1, ieltsTask2
    var id: String { rawValue }
    var exam: Exam {
        switch self { case .kaoyanSmall, .kaoyanLarge, .kaoyan2Small, .kaoyan2Large, .kaoyanTranslation, .kaoyan2Translation: .kaoyan; case .cet6Writing, .cet6Translation: .cet6; case .ieltsTask1, .ieltsTask2: .ielts }
    }
    var title: String {
        switch self { case .kaoyanSmall: "英一小作文"; case .kaoyanLarge: "英一大作文"; case .kaoyan2Small: "英二小作文"; case .kaoyan2Large: "英二大作文"; case .cet6Writing: "Writing"; case .ieltsTask1: "Task 1"; case .ieltsTask2: "Task 2"; case .kaoyanTranslation: "英一翻译"; case .kaoyan2Translation: "英二翻译"; case .cet6Translation: "翻译" }
    }
    /// How the 考研 answer sheet 2 labels this task: section heading, printed question number and sheet title.
    var answerSheet: (section: String, number: String, sheet: String)? {
        switch self {
        case .kaoyanTranslation: ("第二部分：阅读理解 C 节", "46–50", "英语（一）答题卡 2")
        case .kaoyanSmall: ("第三部分：写作 A 节", "51.", "英语（一）答题卡 2")
        case .kaoyanLarge: ("第三部分：写作 B 节", "52.", "英语（一）答题卡 2")
        case .kaoyan2Translation: ("第三部分：英译汉", "46.", "英语（二）答题卡 2")
        case .kaoyan2Small: ("第四部分：写作 A 节", "47.", "英语（二）答题卡 2")
        case .kaoyan2Large: ("第四部分：写作 B 节", "48.", "英语（二）答题卡 2")
        default: nil
        }
    }
    var isTranslation: Bool { self == .kaoyanTranslation || self == .kaoyan2Translation || self == .cet6Translation }
    var targetLanguage: String { (self == .kaoyanTranslation || self == .kaoyan2Translation) ? "Simplified Chinese" : "English" }
    var fullTitle: String { "\(exam.title) · \(title)" }
    var maxScore: Double { switch self { case .kaoyanSmall, .kaoyan2Small, .kaoyanTranslation: 10; case .kaoyanLarge: 20; case .kaoyan2Large, .cet6Writing, .cet6Translation, .kaoyan2Translation: 15; case .ieltsTask1, .ieltsTask2: 9 } }
    var targetWords: Int { switch self { case .kaoyanSmall, .kaoyan2Small: 100; case .kaoyanLarge: 200; case .kaoyan2Large: 150; case .cet6Writing: 180; case .ieltsTask1: 150; case .ieltsTask2: 250; case .kaoyanTranslation, .kaoyan2Translation, .cet6Translation: 0 } }
    var wordGuidance: String { switch self { case .kaoyanSmall, .kaoyan2Small: "About 100 words"; case .kaoyanLarge: "160–200 words"; case .kaoyan2Large: "About 150 words"; case .cet6Writing: "150–200 words"; case .ieltsTask1: "At least 150 words"; case .ieltsTask2: "At least 250 words"; case .kaoyanTranslation: "英语一 · 英译汉 · 完整翻译指定句子"; case .kaoyan2Translation: "英语二 · 英译汉 · 完整翻译段落"; case .cet6Translation: "汉译英 · 完整翻译原文" } }
    var suggestedMinutes: Int { switch self { case .kaoyanSmall, .kaoyan2Small: 15; case .kaoyan2Large: 30; case .kaoyanTranslation, .kaoyan2Translation: 20; case .kaoyanLarge, .cet6Writing, .cet6Translation: 30; case .ieltsTask1: 20; case .ieltsTask2: 40 } }
    var rubricFile: String {
        switch self { case .kaoyanSmall: "kaoyan_english1_small"; case .kaoyanLarge: "kaoyan_english1_large"; case .kaoyan2Small: "kaoyan_english2_small"; case .kaoyan2Large: "kaoyan_english2_large"; case .cet6Writing: "cet6_writing"; case .ieltsTask1: "ielts_task1"; case .ieltsTask2: "ielts_task2"; case .kaoyanTranslation: "kaoyan_english1_translation"; case .kaoyan2Translation: "kaoyan_english2_translation"; case .cet6Translation: "cet6_translation" }
    }
    var sampleQuestion: String {
        switch self {
        case .kaoyanSmall:
            "You are organising a lecture on Chinese culture at your university. Write a letter to your foreign friend Alex, inviting them to attend. Include the following details:\n1. The time and place\n2. The topic of the lecture\n3. Why you think they would enjoy it\nWrite about 100 words. Use “Li Ming” instead of your own name."
        case .kaoyanLarge:
            "A drawing shows two students approaching the same mountain. One looks only at its height; the other starts climbing one step at a time. Write an essay in which you describe the drawing, interpret its message, and give your comments. Write 160–200 words."
        case .kaoyan2Small:
            "Suppose your university is organising a weekend volunteer trip to a rural primary school. Write an email to Jack, an international student, to\n1) invite him to join the trip, and\n2) tell him about the arrangements.\nWrite your answer in about 100 words.\nDo not use your own name in your email. Use “Li Ming” instead."
        case .kaoyan2Large:
            "Write an essay based on the chart below. In your essay, you should\n1) describe and interpret the chart, and\n2) give your comments.\nWrite your answer in about 150 words.\n\n【图表数据】某高校学生每周课外阅读时长调查（2020 年与 2024 年，占受访学生比例）\n少于 1 小时：2020 年 42%，2024 年 28%\n1–3 小时：2020 年 38%，2024 年 41%\n3 小时以上：2020 年 20%，2024 年 31%"
        case .cet6Writing:
            "For this part, you are allowed 30 minutes to write an essay on the importance of developing independent thinking at university. Support your view with reasons and examples. Write at least 150 words but no more than 200 words."
        case .ieltsTask1:
            "The table below shows the percentage of commuters using three forms of transport in a city. Summarise the information by selecting and reporting the main features, and make comparisons where relevant.\n\nTransport — 2000 → 2020\nCar: 60% → 45%\nPublic transport: 30% → 40%\nBicycle: 10% → 15%\n\nWrite at least 150 words."
        case .kaoyanTranslation:
            "将下列五个英语句子译成通顺、准确的汉语。请保留编号。原创练习，每句按 2 分练习尺度评阅。\n\n1. The value of education lies not only in the knowledge we acquire, but also in the questions we learn to ask.\n2. A community becomes stronger when its members are willing to listen to views different from their own.\n3. Although technology has made information easier to obtain, deciding which sources to trust still requires careful judgment.\n4. What appears to be a small improvement today may have a lasting influence on the way people live.\n5. It is through repeated attempts and thoughtful reflection that individuals turn experience into understanding."
        case .kaoyan2Translation:
            "请将下列英语段落完整译成准确、通顺的汉语。原创英语二翻译练习，采用 15 分练习尺度。\n\nLearning a new skill often begins with an uncomfortable feeling: we know what we want to achieve, but we cannot yet do it well. This gap can be frustrating, especially when we compare ourselves with people who have years of experience. Yet progress rarely follows a straight line. Some days bring obvious improvements, while others seem to produce no change at all. The important thing is to pay attention to what each attempt teaches us. A small mistake can reveal a habit that needs to change, and a useful question can lead us to a better approach. Instead of treating difficulty as evidence that we lack ability, we can see it as part of the learning process. With regular practice, helpful feedback and enough patience, activities that once demanded all our attention gradually become more natural. Confidence then grows from experience rather than from the expectation of immediate success."
        case .cet6Translation:
            "请将下面的汉语段落译成英语。原创翻译练习。\n\n近年来，越来越多的中国城市开始重视公共图书馆的建设。图书馆不仅为读者提供丰富的书籍，还组织讲座、展览和面向不同年龄群体的阅读活动。一些图书馆延长了开放时间，让工作繁忙的人也有机会在晚上享受阅读。数字技术的应用使读者可以在线查找资料和借阅电子书。不过，安静舒适的阅读空间仍然具有不可替代的价值。通过这些努力，图书馆正逐渐成为连接社区、分享知识的重要场所，也让阅读成为更多人日常生活的一部分。"
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

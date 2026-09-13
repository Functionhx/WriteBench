using System.Text.Json;
using System.Text.Json.Serialization;
namespace WriteBench;

public record ExamTask(string Id, string Exam, string Title, int Maximum, string Rubric, string Prompt, bool Translation = false, bool Chinese = false)
{
    public string FullTitle => $"{Exam} · {Title}";
    public bool ShowCount => Exam.StartsWith("IELTS");
    public static readonly ExamTask[] All = [
    new("kaoyanSmall","考研英语","小作文",10,"kaoyan_english1_small","Write a letter to Alex inviting them to a lecture on Chinese culture. Include time, place, topic and why they would enjoy it. Write about 100 words. Use Li Ming instead of your name."),
 new("kaoyanLarge","考研英语","大作文",20,"kaoyan_english1_large","Write an essay of 160–200 words about the importance of persistence. Describe an example, interpret its significance and give your comments."),
 new("kaoyanTranslation","考研英语","英语一翻译",10,"kaoyan_english1_translation","请将下列五个句子译为准确通顺的汉语。原创练习。\n1. The value of education lies in the questions we learn to ask.\n2. A community grows stronger when people listen to different views.\n3. Although information is easy to obtain, judging it requires care.\n4. Small improvements can have a lasting influence on daily life.\n5. It is through reflection that experience becomes understanding.",true,true),
 new("kaoyan2Translation","考研英语","英语二翻译",15,"kaoyan_english2_translation","请将以下段落完整译为汉语。原创练习。\nLearning a new skill often begins with uncertainty. We know what we want to achieve, but we cannot yet do it well. Progress rarely follows a straight line. Some days bring obvious improvements, while others seem to produce no change at all. Instead of treating difficulty as evidence that we lack ability, we can see it as part of the learning process. With regular practice, helpful feedback and enough patience, activities that once demanded all our attention gradually become more natural.",true,true),
 new("cet6Writing","CET-6 六级","写作",15,"cet6_writing","Write an essay on the importance of independent thinking at university. Write at least 150 words but no more than 200 words."),
 new("cet6Translation","CET-6 六级","翻译",15,"cet6_translation","请将下列中文完整译为英语。原创练习。\n近年来，越来越多的中国城市开始重视公共图书馆的建设。图书馆不仅提供书籍，还组织讲座和阅读活动。一些图书馆延长了开放时间，让工作繁忙的人也能享受阅读。数字技术使读者可以在线查找资料和借阅电子书。不过，安静舒适的阅读空间仍具有不可替代的价值。",true),
 new("ieltsTask1","IELTS 雅思","Task 1",9,"ielts_task1","The percentage of commuters using cars fell from 60% in 2000 to 45% in 2020. Public transport rose from 30% to 40%; cycling rose from 10% to 15%. Summarise the main features and make comparisons. Write at least 150 words."),
 new("ieltsTask2","IELTS 雅思","Task 2",9,"ielts_task2","Some people believe universities should prepare students for employment. Others think they should provide knowledge for its own sake. Discuss both views and give your opinion. Write at least 250 words.")];
}
public record Correction([property: JsonRequired] string Original, [property: JsonRequired] string Corrected, [property: JsonRequired] string Category, [property: JsonRequired] string Severity, [property: JsonRequired] string Explanation);
public record JudgeResponse([property: JsonRequired] double Score, [property: JsonRequired] double TaskCompletion, [property: JsonRequired] double Language, [property: JsonRequired] double Coherence, [property: JsonRequired] double Register, [property: JsonRequired] string[] MajorErrors, [property: JsonRequired] string[] MinorErrors, [property: JsonRequired] string Summary, [property: JsonRequired] Correction[] Corrections, [property: JsonRequired] string ImprovedVersion);
public record Reviewer(string Judge, string Provider, string Model, string ReasoningEffort, JudgeResponse Response);
public record Report(Reviewer[] Reviewers, double FinalScore, double Spread, string Confidence, string RubricVersion = "2026.09-v1", string PromptVersion = "windows-1.0");
public record Session(Guid Id, DateTime Date, string TaskId, string Question, string OriginalEssay, Report Report, double WritingDuration, string InputMode, string FinalRewrite = "")
{
    public int WordCount => System.Text.RegularExpressions.Regex.Matches(OriginalEssay, @"[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)*").Count;
    public string CorrectedEssay => Report.Reviewers.First(r => r.Judge == "B").Response.ImprovedVersion;
}
public record Draft(string Question, string Essay, double Elapsed, string InputMode = "typed");
public record Settings(string A = "DeepSeek", string B = "DeepSeek", string C = "Codex", string CodexPath = "", string CodexModel = "gpt-6-astra");
public static class JSON
{
    public static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true, WriteIndented = true, UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip };
}
public static class Aggregator
{
    public static Report Aggregate(Reviewer[] reviewers, ExamTask task, string essay)
    {
        if (reviewers.Length != 3 || !reviewers.Select(r => r.Judge).ToHashSet().SetEquals(new[] { "A", "B", "C" }))
            throw new Exception("三位评审未全部完成");
        foreach (var r in reviewers)
            Validate(r.Response, task, essay);
        var scores = reviewers.Select(r => r.Response.Score).Order().ToArray();
        double spread = scores[2] - scores[0];
        return new(reviewers, scores[1], spread, spread <= 1 ? "High" : spread <= 2 ? "Medium" : "Low");
    }
    public static void Validate(JudgeResponse r, ExamTask task, string essay)
    {
        if (!double.IsFinite(r.Score) || r.Score < 0 || r.Score > task.Maximum)
            throw new Exception("分数超出题型范围");
        if (new[] { r.TaskCompletion, r.Language, r.Coherence, r.Register }.Any(v => !double.IsFinite(v) || v < 0 || v > 10) || string.IsNullOrWhiteSpace(r.Summary) || string.IsNullOrWhiteSpace(r.ImprovedVersion) || r.Corrections == null || r.MajorErrors == null || r.MinorErrors == null)
            throw new Exception("评阅字段缺失或无效");
        foreach (var c in r.Corrections)
        if (string.IsNullOrWhiteSpace(c.Original) || !essay.Contains(c.Original) || string.IsNullOrWhiteSpace(c.Corrected) || string.IsNullOrWhiteSpace(c.Explanation) || !new[] { "major", "minor" }.Contains(c.Severity) || !new[] { "Grammar", "Articles", "Collocation", "Word choice", "Chinglish", "Register", "Coherence", "Spelling", "Task omission", "Mistranslation", "Omission", "Addition" }.Contains(c.Category))
            throw new Exception("修改建议没有有效原文引用");
    }
}

using System.IO;
using System.Text.Json;
namespace WriteBench;

static class SelfTest
{
    public static void Run()
    {
        var task = ExamTask.All.First(t => t.Id == "kaoyanSmall");
        var response = new JudgeResponse(8, 8, 8, 8, 8, [], [], "Valid test", [], "Improved test");
        var reviewers = new[] { new Reviewer("A", "test", "test", "max", response), new Reviewer("B", "test", "test", "max", response with { Score = 7.5 }), new Reviewer("C", "test", "test", "max", response) };
        var report = Aggregator.Aggregate(reviewers, task, "test");
        if (report.FinalScore != 8 || report.Confidence != "High")
            throw new Exception("Median failed");
        bool rejected = false;
        try
        {
            Aggregator.Aggregate(reviewers[..2], task, "test");
        }
        catch { rejected = true; }
        if (!rejected)
            throw new Exception("Incomplete results accepted");
        bool duplicateRejected = false;
        try { Aggregator.Aggregate([reviewers[0], reviewers[1], reviewers[0]], task, "test"); }
        catch { duplicateRejected = true; }
        if (!duplicateRejected) throw new Exception("Duplicate judges accepted");
        if (ExamTask.All.Count(t => t.Translation) != 3 || ExamTask.All.First(t => t.Id == "kaoyan2Translation").Maximum != 15)
            throw new Exception("Translation setup invalid");
        foreach (var t in ExamTask.All)
        if (!File.Exists(Path.Combine(AppContext.BaseDirectory, "Rubrics", t.Rubric + ".md")))
            throw new Exception("Missing rubric");
        var roundtrip = JsonSerializer.Deserialize<Report>(JsonSerializer.Serialize(report, JSON.Options), JSON.Options);
        if (roundtrip?.Reviewers.Length != 3)
            throw new Exception("Persistence failed");
        bool missingRejected = false;
        try
        {
            JsonSerializer.Deserialize<JudgeResponse>("{\"score\":8}", JSON.Options);
        }
        catch (JsonException) { missingRejected = true; }
        if (!missingRejected)
            throw new Exception("Missing fields accepted");
        var fixture = Path.Combine(AppContext.BaseDirectory, "ocr-fixture.png");
        if (File.Exists(fixture))
        {
            using var engine = new Tesseract.TesseractEngine(Path.Combine(AppContext.BaseDirectory, "tessdata"), "eng+chi_sim", Tesseract.EngineMode.Default);
            using var pix = Tesseract.Pix.LoadFromFile(fixture);
            using var page = engine.Process(pix);
            if (!page.GetText().Contains("Alex", StringComparison.OrdinalIgnoreCase))
                throw new Exception("OCR fixture recognition failed");
        }
        File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "self-test-passed.txt"), "Domain, scales, aggregation, rejection and JSON round-trip passed.");
    }
}

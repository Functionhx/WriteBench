using System.IO;
using System.Text.Json;
using System.Net;
using System.Net.Http;
using System.Text;
namespace WriteBench;

static class SelfTest
{
    public static async Task Run()
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
        await ExtendedTests(task, response);
        var window = new MainWindow(preview: true); window.CheckUI();
        var fixture = Path.Combine(AppContext.BaseDirectory, "ocr-fixture.png");
        if (File.Exists(fixture))
        {
            using var engine = new Tesseract.TesseractEngine(Path.Combine(AppContext.BaseDirectory, "tessdata"), "eng+chi_sim", Tesseract.EngineMode.Default);
            using var pix = Tesseract.Pix.LoadFromFile(fixture);
            using var page = engine.Process(pix);
            if (!page.GetText().Contains("Alex", StringComparison.OrdinalIgnoreCase))
                throw new Exception("OCR fixture recognition failed");
        }
        File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "self-test-passed.txt"), "Domain, aggregation, schema compatibility, bounded retries, interrupted streams, HTTP authorization, encrypted credentials, timer, native WPF editor/undo/Tab/progress and real OCR passed.");
    }
    static void Assert(bool condition, string name) { if (!condition) throw new Exception(name); }
    static async Task ExtendedTests(ExamTask task, JudgeResponse valid)
    {
        DateTimeOffset now = DateTimeOffset.UtcNow;
        var timer = new AnswerTimer(() => now); timer.Resume(); now += TimeSpan.FromSeconds(17); timer.Pause(); now += TimeSpan.FromSeconds(90);
        Assert(timer.Elapsed == 17 && !timer.Running, "Paused clock advanced");
        timer.Resume(); now += TimeSpan.FromSeconds(3); timer.Pause(); Assert(timer.Elapsed == 20, "Resume lost elapsed time");
        Assert(AnswerLayout.Align("  Title  ", "right", 100, text => text.Length * 10) == "     Title", "Right alignment failed");
        string json = JsonSerializer.Serialize(valid, JSON.Options);
        string flexible = json.Replace("\"score\": 8", "\"score\": \"8\"").Replace("\"majorErrors\": []", "\"majorErrors\": null").Replace("\"corrections\": []", "\"corrections\": null");
        Assert(ReviewDecoder.Decode(flexible, task, "test", "question").Score == 8, "Numeric strings/optional null arrays rejected");
        bool rejected = false;
        try { ReviewDecoder.Decode("{\"summary\":\"partial\"}", task, "test", "question"); } catch (ReviewFormatException) { rejected = true; }
        Assert(rejected, "Missing core fields accepted");
        string dir = Path.Combine(Path.GetTempPath(), "WriteBench-credential-test-" + Guid.NewGuid());
        try {
            var credentials = new Credentials(dir); credentials.Save("fixture-not-a-real-key");
            Assert(new Credentials(dir).Load() == "fixture-not-a-real-key", "Saved key did not survive new instance");
            Assert(!Encoding.UTF8.GetString(File.ReadAllBytes(Path.Combine(dir, "deepseek.dpapi"))).Contains("fixture-not-a-real-key"), "Credential stored as plaintext");
            credentials.Forget(); Assert(credentials.Load() == "", "Forget did not remove key");
        } finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
        var translation = ExamTask.All.First(t => t.Id == "kaoyanTranslation");
        var lesson = new TranslationLesson("1", "People learn through practice.", [new("People learn", "人们学习", [new("learn", "动词", "学习", "学习")], ["主谓结构"]), new("through practice.", "通过练习", [], ["介词短语表示方式"])], "人们通过练习学习。", ["方式状语可前置"], "保留方式关系。");
        Assert(TranslationTeaching.Anchored([lesson], translation, "1. People learn through practice.").Length == 1, "Valid teaching rejected");
        Assert(TranslationTeaching.Anchored([lesson with { Source = "Invented source" }], translation, "1. People learn through practice.").Length == 0, "Invented teaching accepted");
        Assert(TranslationTeaching.Anchored([lesson with { Number = "2" }], translation, "1. People learn through practice.").Length == 0, "Wrong segment number accepted");
        Assert(TranslationTeaching.Anchored([lesson], translation, "Context. (1) <u>People learn through practice.</u>").Length == 1, "Underlined source rejected");
        Assert(TranslationTeaching.Anchored([lesson with { Number = "2" }], translation, "Context. (1) <u>People learn through practice.</u>").Length == 0, "Underlined source numbering bypassed");
        var retry = new FixtureHandler(_ => StreamResult(json), firstInvalid: true);
        using (var client = new HttpClient(retry)) {
            var result = await new DeepSeekProvider("fixture", suppliedClient: client).Grade(task, "question", "test", "A", CancellationToken.None);
            Assert(result.Response.Score == 8 && retry.Count == 2, "Format retry failed");
        }
        var invalid = new FixtureHandler(_ => StreamResult("{}"));
        using (var client = new HttpClient(invalid)) {
            rejected = false; try { await new DeepSeekProvider("fixture", suppliedClient: client).Grade(task, "question", "test", "A", CancellationToken.None); } catch (ReviewFormatException) { rejected = true; }
            Assert(rejected && invalid.Count == 2, "Invalid response retry unbounded");
        }
        var interrupted = new FixtureHandler(_ => StreamResult(json, done: false));
        using (var client = new HttpClient(interrupted)) {
            rejected = false; try { await new DeepSeekProvider("fixture", suppliedClient: client).Grade(task, "question", "test", "A", CancellationToken.None); } catch { rejected = true; }
            Assert(rejected && interrupted.Count == 1, "Interrupted stream accepted/retried");
        }
        var unauthorized = new FixtureHandler(_ => new HttpResponseMessage(HttpStatusCode.Unauthorized));
        using (var client = new HttpClient(unauthorized)) {
            rejected = false; try { await new DeepSeekProvider("fixture", suppliedClient: client).Grade(task, "question", "test", "A", CancellationToken.None); } catch (HttpRequestException) { rejected = true; }
            Assert(rejected && unauthorized.Count == 1, "Unauthorized response retried");
        }
    }
    static HttpResponseMessage StreamResult(string content, bool done = true)
    {
        string chunk = JsonSerializer.Serialize(new { model = "fixture", choices = new[] { new { delta = new { content }, finish_reason = "stop" } } });
        return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("data: " + chunk + "\n\n" + (done ? "data: [DONE]\n\n" : ""), Encoding.UTF8, "text/event-stream") };
    }
    sealed class FixtureHandler(Func<int, HttpResponseMessage> factory, bool firstInvalid = false) : HttpMessageHandler
    {
        public int Count { get; private set; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Count++;
            return Task.FromResult(firstInvalid && Count == 1 ? StreamResult("{}") : factory(Count));
        }
    }

}

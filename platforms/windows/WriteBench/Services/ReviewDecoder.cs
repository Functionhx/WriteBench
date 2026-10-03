using System.Text.Json;
using System.Text.Json.Nodes;
namespace WriteBench;

public sealed class ReviewFormatException(string message) : Exception(message);
public static class ReviewDecoder
{
    public static JudgeResponse Decode(string text, ExamTask task, string essay, string question)
    {
        try
        {
            var obj = JsonNode.Parse(text) as JsonObject ?? throw new JsonException("结果必须为 JSON 对象");
            foreach (string field in new[] { "majorErrors", "minorErrors", "corrections", "translationLessons" })
                if (obj[field] == null) obj[field] = new JsonArray();
            var response = obj.Deserialize<JudgeResponse>(JSON.Options) ?? throw new JsonException("空结果");
            Aggregator.Validate(response, task, essay);
            return response with { TranslationLessons = TranslationTeaching.Anchored(response.TranslationLessons, task, question) };
        }
        catch (Exception error) when (error is not ReviewFormatException)
        { throw new ReviewFormatException($"评分结果格式无效：{(error is JsonException j ? j.Path ?? "JSON" : "字段校验")}。{error.Message}"); }
    }
}

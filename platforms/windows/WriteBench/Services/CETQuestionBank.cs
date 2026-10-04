using System.IO;
using System.Text.Json;
namespace WriteBench;

public record CETBankEntry(string Id, string Task, int Year, int Month, int Set, string Title, string Prompt, string SourceUrl, string Verification)
{
    public bool HasPrompt => !string.IsNullOrWhiteSpace(Prompt);
}
public record CETBankDocument(int SchemaVersion, CETBankEntry[] Questions);
public sealed class CETQuestionBank(string? directory = null)
{
    readonly string folder = directory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WriteBench", "QuestionBank");
    string FileName => Path.Combine(folder, "cet6-custom.json");
    public static CETBankEntry[] Decode(byte[] data, bool requirePrompts, DateTime? now = null)
    {
        if (data.Length > 10 * 1024 * 1024) throw new Exception("题库文件超过 10 MB");
        var document = JsonSerializer.Deserialize<CETBankDocument>(data, JSON.Options) ?? throw new Exception("题库为空");
        if (document.SchemaVersion != 1 || document.Questions is not { Length: > 0 and <= 1000 }) throw new Exception("题库版本或数量无效");
        var ids = new HashSet<string>();
        foreach (var item in document.Questions)
        {
            if (item == null || string.IsNullOrWhiteSpace(item.Id) || !ids.Add(item.Id) || !new[] { "cet6Writing", "cet6Translation" }.Contains(item.Task)
                || item.Year < 2022 || item.Year > 2026 || !new[] { 3, 6, 9, 12 }.Contains(item.Month) || item.Set < 1 || item.Set > 3
                || new DateTime(item.Year, item.Month, 1) > (now ?? DateTime.Now) || string.IsNullOrWhiteSpace(item.Title) || item.Prompt == null || item.Prompt.Length > 100_000
                || !Uri.TryCreate(item.SourceUrl, UriKind.Absolute, out var uri) || !new[] { "http", "https" }.Contains(uri.Scheme) || string.IsNullOrEmpty(uri.Host)
                || !new[] { "sourceIndex", "userImported", "providedDocument" }.Contains(item.Verification)) throw new Exception("题目年份、题型、套次、来源或标识无效");
            if (requirePrompts && !item.HasPrompt) throw new Exception($"题目 {item.Title} 只有来源索引，没有正文，不能作为练习题导入");
        }
        return document.Questions;
    }
    public CETBankEntry[] Entries()
    {
        var bundled = Decode(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "QuestionBank", "cet6-2022-2026.json")), false);
        var custom = File.Exists(FileName) ? Decode(File.ReadAllBytes(FileName), true) : [];
        return bundled.Concat(custom).GroupBy(item => item.Id).Select(group => group.Last()).OrderByDescending(item => item.Year).ThenByDescending(item => item.Month).ThenBy(item => item.Set).ToArray();
    }
    public int Import(byte[] data)
    {
        var imported = Decode(data, true).Select(item => item with { Verification = "userImported" }).ToArray();
        var old = File.Exists(FileName) ? Decode(File.ReadAllBytes(FileName), true) : [];
        var merged = old.Concat(imported).GroupBy(item => item.Id).Select(group => group.Last()).ToArray();
        Directory.CreateDirectory(folder);
        File.WriteAllText(FileName + ".tmp", JsonSerializer.Serialize(new CETBankDocument(1, merged), JSON.Options));
        File.Move(FileName + ".tmp", FileName, true);
        return imported.Length;
    }
}

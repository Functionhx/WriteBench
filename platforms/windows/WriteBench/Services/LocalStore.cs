using System.IO;
using System.Text.Json;
namespace WriteBench;

public sealed class LocalStore
{
    readonly string folder;
    public LocalStore(string? directory = null)
    {
        folder = directory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WriteBench");
        Directory.CreateDirectory(folder);
    }
    public T? Read<T>(string name)
    {
        string path = Path.Combine(folder, name);
        return File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), JSON.Options) : default;
    }
    public void Write<T>(string name, T value)
    {
        string path = Path.Combine(folder, name), temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(value, JSON.Options));
        File.Move(temp, path, true);
    }
    public List<Session> History() => Read<List<Session>>("history.json") ?? [];
    public void Add(Session session)
    {
        var list = History();
        list.Insert(0, session);
        Write("history.json", list);
    }
    public void Rewrite(Guid id, string essay)
    {
        var list = History();
        int i = list.FindIndex(s => s.Id == id);
        if (i >= 0)
        {
            list[i] = list[i] with
            {
                FinalRewrite = essay
            };
            Write("history.json", list);
        }
    }
}

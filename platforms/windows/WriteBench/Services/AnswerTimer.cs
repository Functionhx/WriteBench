namespace WriteBench;

// The same clock drives the UI, drafts and submitted writing duration.
public sealed class AnswerTimer(Func<DateTimeOffset>? now = null)
{
    readonly Func<DateTimeOffset> now = now ?? (() => DateTimeOffset.UtcNow);
    double saved;
    DateTimeOffset started;
    public bool Running { get; private set; }
    public double Elapsed => Math.Max(0, saved + (Running ? (now() - started).TotalSeconds : 0));
    public void Reset(double seconds = 0) { saved = Math.Max(0, seconds); Running = false; }
    public void Resume() { if (!Running) { started = now(); Running = true; } }
    public void Pause() { saved = Elapsed; Running = false; }
}

public static class AnswerLayout
{
    public static string Align(string line, string alignment, double width, Func<string, double> measure)
    {
        string text = line.Trim(' ', '\t');
        if (text.Length == 0 || alignment == "left") return text;
        double remaining = Math.Max(0, width - measure(text));
        double space = Math.Max(1, measure(" "));
        int count = Math.Clamp((int)Math.Floor(remaining / space * (alignment == "center" ? .5 : 1)), 0, 1000);
        return new string(' ', count) + text;
    }
}

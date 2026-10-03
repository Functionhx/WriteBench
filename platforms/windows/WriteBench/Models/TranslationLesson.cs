using System.Text.RegularExpressions;
namespace WriteBench;

public record TranslationVocabulary(string Word, string PartOfSpeech, string CommonMeaning, string ContextualMeaning);
public record TranslationMeaningGroup(string Source, string Translation, TranslationVocabulary[] Vocabulary, string[] Techniques);
public record TranslationLesson(string Number, string Source, TranslationMeaningGroup[] Groups, string ReferenceTranslation, string[] AssemblyNotes, string StudentAdvice);
public static class TranslationTeaching
{
    public static string Instructions(ExamTask task) => !task.Id.StartsWith("kaoyan") || !task.Translation
        ? "translationLessons must be an empty array."
        : "translationLessons is required. Act as an experienced translation teacher. For English I teach only the numbered translation segments, preserving their exact numbers; other text is context. For English II teach each source sentence in order, numbered from 1; do not apply English I's 2-point rule. Copy source verbatim without markup. Split naturally into 3–4 ordered complete meaning groups, fewer for short sentences. Each group has an exact contiguous source, Chinese translation, vocabulary (1–3 useful words/phrases occurring in the group, with word, partOfSpeech, commonMeaning, contextualMeaning) and techniques (Chinese explanations of specific grammar and translation choices). Do not invent official vocabulary-list membership. Each lesson has number, source, groups, referenceTranslation, assemblyNotes (Chinese string array explaining word order, logic and cohesion), studentAdvice (Chinese advice grounded in the student's actual translation). Teaching never changes marks.";
    static string Normalize(string value) => Regex.Replace(value ?? "", @"\s+", " ").Trim();
    public static TranslationLesson[] Anchored(TranslationLesson[]? lessons, ExamTask task, string question)
    {
        if (!task.Translation || !task.Id.StartsWith("kaoyan")) return [];
        string evidence = Normalize(Regex.Replace(question, "<[^>]*>", ""));
        var seen = new HashSet<string>();
        return (lessons ?? []).Where(lesson =>
        {
            string source = Normalize(lesson.Source);
            if (source.Length == 0 || !evidence.Contains(source) || string.IsNullOrWhiteSpace(lesson.ReferenceTranslation) || lesson.Groups is not { Length: > 0 }) return false;
            // Numbered English I segments must match their complete source, not context.
            if (task.Id == "kaoyanTranslation")
            {
                var segments = Regex.Matches(question, @"(?m)^\s*(\d+)[.、)）]\s*(.+)$");
                if (segments.Count > 0 && !segments.Any(m => m.Groups[1].Value == lesson.Number && Normalize(m.Groups[2].Value) == source)) return false;
            }
            int offset = 0;
            foreach (var group in lesson.Groups)
            {
                string span = Normalize(group.Source);
                if (span.Length == 0 || string.IsNullOrWhiteSpace(group.Translation)) return false;
                int index = source.IndexOf(span, offset, StringComparison.Ordinal);
                if (index < 0 || source[offset..index].Any(c => !char.IsWhiteSpace(c) && !char.IsPunctuation(c))) return false;
                offset = index + span.Length;
            }
            return source[offset..].All(c => char.IsWhiteSpace(c) || char.IsPunctuation(c)) && seen.Add(lesson.Number);
        }).Select(lesson => lesson with { Groups = lesson.Groups.Select(group => group with {
            Vocabulary = (group.Vocabulary ?? []).Where(v => !string.IsNullOrWhiteSpace(v.Word) && Normalize(group.Source).Contains(Normalize(v.Word), StringComparison.OrdinalIgnoreCase)).ToArray(),
            Techniques = group.Techniques ?? []
        }).ToArray(), AssemblyNotes = lesson.AssemblyNotes ?? [], StudentAdvice = lesson.StudentAdvice ?? "" }).ToArray();
    }
}

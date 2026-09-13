using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
namespace WriteBench;

public sealed partial class MainWindow : Window
{
    readonly LocalStore store; Settings settings; ExamTask task = ExamTask.All[0]; string question = "", essay = "", key = "", inputMode = "typed", page = "Write"; double elapsed; DateTime started; bool answering, grading; Guid? rewriteID; Session? review; CancellationTokenSource? gradingCancellation; TextBlock? clock; TextBox? editor; StackPanel content = new(); readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    static readonly Brush Blue = new SolidColorBrush(Color.FromRgb(50, 102, 245)), Ink = new SolidColorBrush(Color.FromRgb(23, 35, 60)), Muted = new SolidColorBrush(Color.FromRgb(115, 129, 155)), Line = new SolidColorBrush(Color.FromRgb(227, 234, 245));
    public MainWindow(bool preview = false)
    {
        store = new LocalStore(preview ? Path.Combine(Path.GetTempPath(), "WriteBench-preview-" + Guid.NewGuid()) : null);
        Title = "WriteBench";
        Width = 1320;
        Height = 870;
        MinWidth = 960;
        MinHeight = 650;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Icon = new BitmapImage(new Uri("pack://application:,,,/Assets/Icon.png"));
        settings = store.Read<Settings>("settings.json") ?? new();
        LoadDraft();
        Render();
        timer.Tick += (_, _) => { if (answering && !grading) { if (clock != null) clock.Text = TimeText(); SaveDraft(); } };
        timer.Start();
        Closing += (_, _) => { SaveDraft(); gradingCancellation?.Cancel(); key = ""; timer.Stop(); };
    }
    TextBlock Text(string value, double size = 15, Brush? color = null)
    {
        return new()
        {
            Text = value,
            FontSize = size,
            Foreground = color ?? Ink,
            TextWrapping = TextWrapping.Wrap,
            LineHeight = size * 1.5,
            Margin = new Thickness(0, 0, 0, 10)
        };
    }
    Button Button(string title, Action action, bool primary = false)
    {
        var b = new Button { Content = title, HorizontalAlignment = HorizontalAlignment.Left };
        if (primary)
        {
            b.Background = Blue;
            b.Foreground = Brushes.White;
            b.BorderBrush = Blue;
        }
        b.Click += (_, _) => { try { action(); } catch (Exception e) { Message(e.Message); } };
        return b;
    }
    StackPanel Card(Panel parent)
    {
        var panel = new StackPanel();
        var border = new Border { Background = Brushes.White, CornerRadius = new CornerRadius(16), BorderBrush = Line, BorderThickness = new Thickness(1), Padding = new Thickness(24), Margin = new Thickness(0, 0, 0, 18), Child = panel };
        parent.Children.Add(border);
        return panel;
    }
    void Heading(string title, string subtitle)
    {
        var t = Text(title, 30);
        t.FontWeight = FontWeights.SemiBold;
        content.Children.Add(t);
        content.Children.Add(Text(subtitle, 13, Muted));
        content.Children.Add(new Border { Height = 15 });
    }
    TextBox Input(string text, double minHeight = 140)
    {
        return new()
        {
            Text = text,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = minHeight,
            Margin = new Thickness(0, 8, 0, 16)
        };
    }
    void Render()
    {
        if (answering)
        {
            RenderAnswer();
            return;
        }
        WindowStyle = WindowStyle.SingleBorderWindow;
        var grid = new Grid { Background = new SolidColorBrush(Color.FromRgb(244, 247, 252)) };
        grid.ColumnDefinitions.Add(new()
        {
            Width = new GridLength(200)
        });
        grid.ColumnDefinitions.Add(new());
        var sidebar = new StackPanel { Background = Brushes.White, Margin = new Thickness(0), VerticalAlignment = VerticalAlignment.Stretch };
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(20, 32, 12, 28) };
        brand.Children.Add(new Image { Source = Icon, Width = 34, Height = 34, Margin = new Thickness(0, 0, 10, 0) });
        brand.Children.Add(Text("WriteBench", 18));
        sidebar.Children.Add(brand);
        foreach (string dest in new[] { "Write", "History", "Statistics", "Mistakes", "Settings" })
        {
            var b = Button(dest, () => { page = dest; Render(); });
            b.HorizontalAlignment = HorizontalAlignment.Stretch;
            b.Margin = new Thickness(14, 4, 14, 4);
            b.BorderThickness = new Thickness(0);
            b.Background = page == dest ? new SolidColorBrush(Color.FromRgb(234, 241, 255)) : Brushes.White;
            b.HorizontalContentAlignment = HorizontalAlignment.Left;
            sidebar.Children.Add(b);
        }
        grid.Children.Add(sidebar);
        var right = new DockPanel();
        Grid.SetColumn(right, 1);
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(30, 22, 0, 18) };
        foreach (string exam in new[] { "考研英语", "CET-6 六级", "IELTS 雅思" })
        {
            var b = Button(exam, () => SelectTask(ExamTask.All.First(t => t.Exam == exam)), task.Exam == exam);
            b.Content = ExamLabel(exam, task.Exam == exam);
            tabs.Children.Add(b);
        }
        DockPanel.SetDock(tabs, Dock.Top);
        right.Children.Add(tabs);
        content = new StackPanel { Margin = new Thickness(34, 8, 34, 28), MaxWidth = 1000, HorizontalAlignment = HorizontalAlignment.Stretch };
        right.Children.Add(new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        grid.Children.Add(right);
        Content = grid;
        switch (page)
        {
            case "History":
                History();
                break;
            case "Statistics":
                Statistics();
                break;
            case "Mistakes":
                Mistakes();
                break;
            case "Settings":
                SettingsUI();
                break;
            case "Review":
                Review();
                break;
            default:
                Preparation();
                break;
        }
    }
    void Preparation()
    {
        Heading(task.Translation ? "准备翻译" : "准备写作", task.Translation ? (task.Chinese ? "英译汉 · 译义准确，表达自然。" : "汉译英 · 忠实完整地传达原文。") : "选好题目，开始一段安静的写作。");
        var sub = new WrapPanel { Margin = new Thickness(0, 0, 0, 20) };
        foreach (var t in ExamTask.All.Where(t => t.Exam == task.Exam))
            sub.Children.Add(Button(t.Title, () => SelectTask(t), t == task));
        content.Children.Add(sub);
        var c = Card(content);
        c.Children.Add(Text("题目 · 原创练习 / 自行导入", 13, Muted));
        var q = Input(question, 210);
        q.TextChanged += (_, _) => { question = q.Text; SaveDraft(); };
        c.Children.Add(q);
        c.Children.Add(Button("从图片识别题目", () => _ = ImportImages(false)));
        var start = Button(essay.Length == 0 ? "开始答题 →" : "继续答题 →", () => { if (string.IsNullOrWhiteSpace(question)) { Message("请先填写题目"); return; } SaveDraft(); answering = true; started = DateTime.UtcNow; Render(); }, true);
        content.Children.Add(start);
        content.Children.Add(Text("开始后进入唯一的沉浸式答题界面 · 草稿保存在本机", 12, Muted));
    }
    void RenderAnswer()
    {
        WindowStyle = WindowStyle.None;
        WindowState = WindowState.Maximized;
        var root = new DockPanel { Background = Brushes.White, Margin = new Thickness(28) };
        var top = new DockPanel { Margin = new Thickness(0, 0, 0, 24) };
        top.Children.Add(Button("保存并离开", Leave));
        var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        clock = Text(TimeText(), 15);
        clock.VerticalAlignment = VerticalAlignment.Center;
        clock.Margin = new Thickness(0, 0, 24, 0);
        right.Children.Add(clock);
        var submit = Button(grading ? "正在评阅…" : "交卷", () => _ = Submit(), true);
        submit.IsEnabled = !grading;
        right.Children.Add(submit);
        DockPanel.SetDock(right, Dock.Right);
        top.Children.Add(right);
        top.Children.Add(Text(task.FullTitle, 15, Muted));
        DockPanel.SetDock(top, Dock.Top);
        root.Children.Add(top);
        var bottom = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 14, 0, 0) };
        bottom.Children.Add(Text(grading ? "三位独立评审正在阅读同一份原稿 · MAX 思考" : "草稿自动保存", 12, Muted));
        bottom.Children.Add(Button(grading ? "取消评卷" : "导入手写稿", () => { if (grading) gradingCancellation?.Cancel(); else _ = ImportImages(true); }));
        DockPanel.SetDock(bottom, Dock.Bottom);
        root.Children.Add(bottom);
        var split = new Grid();
        split.ColumnDefinitions.Add(new()
        {
            Width = new GridLength(0.36, GridUnitType.Star)
        });
        split.ColumnDefinitions.Add(new()
        {
            Width = new GridLength(1, GridUnitType.Auto)
        });
        split.ColumnDefinitions.Add(new()
        {
            Width = new GridLength(0.64, GridUnitType.Star)
        });
        var q = new StackPanel { Margin = new Thickness(0, 0, 24, 0) };
        q.Children.Add(Text("试题", 13, Muted));
        q.Children.Add(Text(question, 17));
        split.Children.Add(new ScrollViewer { Content = q, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        var divider = new GridSplitter { Width = 1, Background = Line, HorizontalAlignment = HorizontalAlignment.Center };
        Grid.SetColumn(divider, 1);
        split.Children.Add(divider);
        var answer = new DockPanel { Margin = new Thickness(28, 0, 0, 0) };
        Grid.SetColumn(answer, 2);
        var label = Text(task.Chinese ? "译文答题区" : "答题区", 13, Muted);
        DockPanel.SetDock(label, Dock.Top);
        answer.Children.Add(label);
        editor = Input(essay, 200);
        editor.IsReadOnly = grading;
        editor.FontSize = 20;
        editor.VerticalAlignment = VerticalAlignment.Stretch;
        editor.Margin = new Thickness(0);
        editor.Background = task.ShowCount ? Brushes.White : RuledPaper();
        editor.TextChanged += (_, _) => { essay = editor.Text; SaveDraft(); };
        if (task.ShowCount)
        {
            var count = Text($"Words: {Words(essay)}", 12, Muted);
            editor.TextChanged += (_, _) => count.Text = $"Words: {Words(essay)}";
            DockPanel.SetDock(count, Dock.Bottom);
            answer.Children.Add(count);
        }
        answer.Children.Add(editor);
        split.Children.Add(answer);
        root.Children.Add(split);
        Content = root;
        if (!grading)
            editor.Focus();
    }
    Brush RuledPaper()
    {
        var geometry = new GeometryDrawing(null, new Pen(Line, 0.7), new LineGeometry(new Point(0, 31), new Point(100, 31)));
        return new DrawingBrush(geometry) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 100, 32), ViewportUnits = BrushMappingMode.Absolute, Stretch = Stretch.None };
    }
    void SelectTask(ExamTask next)
    {
        SaveDraft();
        task = next;
        rewriteID = null;
        LoadDraft();
        page = "Write";
        Render();
    }
    double Duration() => elapsed + (answering && !grading ? (DateTime.UtcNow - started).TotalSeconds : 0);
    string TimeText()
    {
        var seconds = (long)Math.Max(0, Duration());
        return $"{seconds / 60:00}:{seconds % 60:00}";
    }
    static int Words(string value) => value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
    void LoadDraft()
    {
        var draft = store.Read<Draft>("draft-" + task.Id + ".json");
        question = draft?.Question ?? task.Prompt;
        essay = draft?.Essay ?? "";
        elapsed = draft?.Elapsed ?? 0;
        inputMode = draft?.InputMode ?? "typed";
    }
    void SaveDraft()
    {
        store.Write("draft-" + task.Id + ".json", new Draft(question, essay, Duration(), inputMode));
        if (rewriteID is Guid id)
            store.Rewrite(id, essay);
    }
    void Leave()
    {
        if (grading)
            return;
        elapsed = Duration();
        answering = false;
        SaveDraft();
        WindowState = WindowState.Normal;
        Render();
    }
    async Task Submit()
    {
        if (grading || !answering)
            return;
        SaveDraft();
        if (string.IsNullOrWhiteSpace(essay))
        {
            Message("请先填写作答内容。");
            return;
        }
        if (new[] { settings.A, settings.B, settings.C }.Contains("DeepSeek") && string.IsNullOrWhiteSpace(key))
        {
            if (MessageBox.Show(this, "未配置 DeepSeek API Key。草稿已保存，本次未生成评分。是否前往设置填写？", "WriteBench", MessageBoxButton.YesNo, MessageBoxImage.Information) == MessageBoxResult.Yes)
            {
                Leave();
                page = "Settings";
                Render();
            }
            return;
        }
        elapsed = Duration();
        grading = true;
        gradingCancellation = new();
        Render();
        try
        {
            var result = await Grading.Run(task, question, essay, key, settings, gradingCancellation.Token);
            var session = new Session(Guid.NewGuid(), DateTime.Now, task.Id, question, essay, result, elapsed, inputMode);
            store.Add(session);
            review = session;
            answering = false;
            page = "Review";
            WindowState = WindowState.Normal;
        }
        catch (OperationCanceledException) { Message("评卷已取消，原稿保留。"); }
        catch (Exception e) { Message(e.Message); }
        finally { grading = false; started = DateTime.UtcNow; gradingCancellation?.Dispose(); gradingCancellation = null; Render(); }
    }
    void SettingsUI()
    {
        Heading("AI Judges", "每位评审独立配置 · 不自动切换服务");
        var c = Card(content);
        string[] selected = [settings.A, settings.B, settings.C];
        for (int i = 0; i < 3; i++)
        {
            int index = i;
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 16) };
            row.Children.Add(new TextBlock { Text = $"Judge {(char)('A' + i)}", Width = 170, FontSize = 16, VerticalAlignment = VerticalAlignment.Center });
            var picker = new ComboBox { ItemsSource = new[] { "DeepSeek", "Codex" }, SelectedItem = selected[i], Width = 240 };
            picker.SelectionChanged += (_, _) => { selected[index] = (string)picker.SelectedItem; settings = settings with { A = selected[0], B = selected[1], C = selected[2] }; store.Write("settings.json", settings); };
            row.Children.Add(picker);
            c.Children.Add(row);
        }
        c.Children.Add(Text("DeepSeek V4 Pro / MAX · ChatGPT via Codex / GPT-6 Astra / MAX", 12, Muted));
        var api = Card(content);
        api.Children.Add(Text("DeepSeek API Key", 20));
        var input = new PasswordBox { Padding = new Thickness(12), Margin = new Thickness(0, 10, 0, 15), FontSize = 16 };
        api.Children.Add(input);
        api.Children.Add(Button("使用此 Key", () => { if (string.IsNullOrWhiteSpace(input.Password)) { Message("请填入 API Key"); return; } key = input.Password.Trim(); input.Clear(); Message("Key 已启用，仅保留在本次运行内存中。无需 Windows 密码。"); }, true));
        api.Children.Add(Text("由用户自行填写。不会写入文件、日志或注册表。", 12, Muted));
        var codex = Card(content);
        codex.Children.Add(Text("ChatGPT · via Codex", 20));
        codex.Children.Add(Text("Uses your signed-in Codex account · 使用 Codex 额度", 12, Muted));
        var path = Input(settings.CodexPath, 40);
        path.AcceptsReturn = false;
        path.TextChanged += (_, _) => { settings = settings with { CodexPath = path.Text }; store.Write("settings.json", settings); };
        codex.Children.Add(Text("官方 codex.exe 路径（可留空自动检测）", 12, Muted));
        codex.Children.Add(path);
        var status = Text("首次使用请在终端运行 codex login。应用不读取 Codex 认证文件。", 12, Muted);
        codex.Children.Add(Button("检查连接", async () => { try { status.Text = await CodexProvider.Check(CodexProvider.Discover(settings.CodexPath), CancellationToken.None); } catch (Exception e) { status.Text = e.Message; } }));
        codex.Children.Add(status);
    }
    void History()
    {
        Heading("写过的每一篇", "日期、题型、分数与完整评阅");
        var sessions = store.History();
        if (sessions.Count == 0)
            content.Children.Add(Text("完成首次真实评卷后，原稿和修改建议会保存在这里。", 15, Muted));
        foreach (var s in sessions)
        {
            var t = ExamTask.All.First(t => t.Id == s.TaskId);
            var c = Card(content);
            c.Children.Add(Text($"{s.Date:yyyy.MM.dd HH:mm}   {t.FullTitle}", 15));
            c.Children.Add(Text($"{s.Report.FinalScore:0.0} / {t.Maximum}    {s.Report.Confidence} confidence", 24, Blue));
            c.Children.Add(Button("打开评阅", () => { review = s; page = "Review"; Render(); }));
        }
    }
    void Statistics()
    {
        Heading("练习中的变化", "只统计真实完成的评卷，分数按题型满分归一化。");
        var list = store.History();
        var c = Card(content);
        c.Children.Add(Text($"{list.Count} 篇练习", 36));
        if (list.Count == 0)
            return;
        c.Children.Add(Text($"平均得分比例 {list.Average(s => s.Report.FinalScore / ExamTask.All.First(t => t.Id == s.TaskId).Maximum) * 100:0.0}%", 22, Blue));
        c.Children.Add(Text($"平均作答时间 {list.Average(s => s.WritingDuration) / 60:0.0} 分钟", 15, Muted));
        foreach (var s in list.Take(15).Reverse())
        {
            c.Children.Add(Text($"{s.Date:MM.dd} · {ExamTask.All.First(t => t.Id == s.TaskId).Title}", 12, Muted));
            c.Children.Add(new ProgressBar { Minimum = 0, Maximum = 1, Value = s.Report.FinalScore / ExamTask.All.First(t => t.Id == s.TaskId).Maximum, Height = 7, Foreground = Blue, Margin = new Thickness(0, 0, 0, 14) });
        }
    }
    void Mistakes()
    {
        Heading("把错误变成经验", "按类别回看重要的修改建议");
        var categories = store.History().SelectMany(s => s.Report.Reviewers.SelectMany(r => r.Response.Corrections).DistinctBy(c => c.Category + c.Original)).GroupBy(c => c.Category);
        foreach (var group in categories)
        {
            var c = Card(content);
            c.Children.Add(Text($"{group.Key}  {group.Count()}", 22));
            foreach (var item in group.Take(5))
            {
                c.Children.Add(Text(item.Original, 14, Muted));
                c.Children.Add(Text("→ " + item.Corrected, 16));
                c.Children.Add(Text(item.Explanation, 12, Muted));
            }
        }
        if (!categories.Any())
            content.Children.Add(Text("完成评卷后，重要修改会出现在这里。", 15, Muted));
    }
    void Review()
    {
        if (review == null)
        {
            History();
            return;
        }
        var s = review;
        var t = ExamTask.All.First(t => t.Id == s.TaskId);
        Heading(t.Translation ? "翻译评阅" : "作文评阅", t.FullTitle);
        var c = Card(content);
        c.Children.Add(Text($"{s.Report.FinalScore:0.0} / {t.Maximum}", 52, Blue));
        c.Children.Add(Text($"{s.Report.Confidence} confidence · 三评中位数 · 分歧 {s.Report.Spread:0.0}", 14, Muted));
        foreach (var r in s.Report.Reviewers)
        {
            var judge = Card(content);
            judge.Children.Add(Text($"Judge {r.Judge}    {r.Response.Score:0.0}", 25));
            judge.Children.Add(Text($"{r.Provider} · {r.Model} · MAX", 12, Muted));
            judge.Children.Add(Text(r.Response.Summary));
            foreach (var error in r.Response.MajorErrors)
                judge.Children.Add(Text("• " + error, 14, Muted));
        }
        var dimensions = Card(content);
        foreach (var item in new[] { (t.Translation ? "译义与完整性" : "任务完成", s.Report.Reviewers.Average(r => r.Response.TaskCompletion)), ("语言表达", s.Report.Reviewers.Average(r => r.Response.Language)), ("连贯性", s.Report.Reviewers.Average(r => r.Response.Coherence)), ("语域", s.Report.Reviewers.Average(r => r.Response.Register)) })
        {
            dimensions.Children.Add(Text($"{item.Item1}   {item.Item2:0.0} / 10", 13, Muted));
            dimensions.Children.Add(new ProgressBar { Minimum = 0, Maximum = 10, Value = item.Item2, Height = 6, Foreground = Blue, Margin = new Thickness(0, 0, 0, 16) });
        }
        var corrections = Card(content);
        corrections.Children.Add(Text("值得改好的表达", 22));
        foreach (var fix in s.Report.Reviewers.SelectMany(r => r.Response.Corrections).DistinctBy(c => c.Original + c.Category))
        {
            corrections.Children.Add(Text(fix.Category, 12, Blue));
            corrections.Children.Add(Text(fix.Original, 14, Muted));
            corrections.Children.Add(Text("→ " + fix.Corrected, 16));
            corrections.Children.Add(Text(fix.Explanation, 13, Muted));
        }
        var improved = Card(content);
        improved.Children.Add(Text(t.Translation ? "参考改译" : "改进版本", 22));
        improved.Children.Add(Text(s.Report.Reviewers[1].Response.ImprovedVersion, 17));
        var original = Card(content);
        original.Children.Add(new Expander { Header = "查看原题与原稿", Content = Text(s.Question + "\n\n" + s.OriginalEssay) });
        content.Children.Add(Button("开始重写 →", () => { task = t; question = s.Question; essay = string.IsNullOrEmpty(s.FinalRewrite) ? s.OriginalEssay : s.FinalRewrite; rewriteID = s.Id; elapsed = 0; inputMode = "typed"; answering = true; started = DateTime.UtcNow; Render(); }, true));
    }
    FrameworkElement ExamLabel(string exam, bool selected)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        string path = exam.StartsWith("考研") ? "M1,9 L12,3 23,9 12,15 Z M5,12 L5,18 Q12,23 19,18 L19,12 M23,9 L23,18" : exam.StartsWith("CET") ? "M12,5 Q6,1 2,4 L2,20 Q7,17 12,21 Q17,17 22,20 L22,4 Q18,1 12,5 L12,21" : "M22,12 A10,10 0 1 1 2,12 A10,10 0 1 1 22,12 M2,12 L22,12 M12,2 C5,8 5,16 12,22 C19,16 19,8 12,2 M4,6 L20,6 M4,18 L20,18";
        row.Children.Add(new System.Windows.Shapes.Path { Data = Geometry.Parse(path), Stroke = selected ? Brushes.White : Blue, StrokeThickness = 1.6, Width = 22, Height = 22, Stretch = Stretch.Uniform, Margin = new Thickness(0, 0, 10, 0) });
        row.Children.Add(new TextBlock { Text = exam, VerticalAlignment = VerticalAlignment.Center });
        return row;
    }
    void Message(string value) => MessageBox.Show(this, value, "WriteBench", MessageBoxButton.OK, MessageBoxImage.Information);
}

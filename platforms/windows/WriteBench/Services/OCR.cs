using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using Tesseract;
namespace WriteBench;

public sealed partial class MainWindow
{
    async Task ImportImages(bool answer)
    {
        if (grading)
            return;
        var dialog = new OpenFileDialog { Title = answer ? "导入手写稿" : "导入题目", Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff", Multiselect = true };
        if (dialog.ShowDialog(this) != true)
            return;
        if (dialog.FileNames.Length > 12)
        {
            Message("每次最多导入 12 页。");
            return;
        }
        try
        {
            foreach (var p in dialog.FileNames)
            if (new FileInfo(p).Length > 25_000_000)
                throw new Exception("每张图片不得超过 25 MB");
            var recognized = await Task.Run(() => { using var engine = new TesseractEngine(Path.Combine(AppContext.BaseDirectory, "tessdata"), "eng+chi_sim", EngineMode.Default); return dialog.FileNames.Select(path => { using var image = Pix.LoadFromFile(path); using var page = engine.Process(image); return page.GetText(); }).ToArray(); });
            ConfirmOCR(dialog.FileNames, recognized, answer);
        }
        catch (Exception e) { Message("本机图片识别未完成。请检查图像清晰度与 OCR 运行库。\n" + e.Message); }
    }
    void ConfirmOCR(string[] files, string[] texts, bool answer)
    {
        var window = new Window { Owner = this, Title = "校对识别结果", Width = 1050, Height = 760, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var root = new DockPanel { Margin = new Thickness(24) };
        var footer = new StackPanel { Orientation = System.Windows.Controls.Orientation.Horizontal, Margin = new Thickness(0, 20, 0, 0) };
        var checkedAll = new CheckBox { Content = "我已对照原图核对所有页面", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 20, 0) };
        footer.Children.Add(checkedAll);
        var confirm = Button(answer ? "确认并评卷" : "确认填入题目", () => { if (answer) { essay = string.Join("\n\n", texts); inputMode = "handwritten"; } else question = string.Join("\n\n", texts); SaveDraft(); window.Close(); Render(); if (answer) _ = Submit(); }, true);
        confirm.IsEnabled = false;
        checkedAll.Checked += (_, _) => confirm.IsEnabled = true;
        checkedAll.Unchecked += (_, _) => confirm.IsEnabled = false;
        footer.Children.Add(confirm);
        DockPanel.SetDock(footer, Dock.Bottom);
        root.Children.Add(footer);
        var tabs = new TabControl();
        for (int i = 0; i < files.Length; i++)
        {
            int index = i;
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new());
            grid.ColumnDefinitions.Add(new());
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.UriSource = new Uri(files[i]);
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.EndInit();
            var image = new Image { Source = bitmap, Stretch = Stretch.Uniform, Margin = new Thickness(12) };
            grid.Children.Add(new ScrollViewer { Content = image });
            var editor = Input(texts[i]);
            editor.AcceptsReturn = true;
            editor.TextChanged += (_, _) => texts[index] = editor.Text;
            Grid.SetColumn(editor, 1);
            grid.Children.Add(editor);
            tabs.Items.Add(new TabItem { Header = $"第 {i + 1} 页", Content = grid });
        }
        root.Children.Add(tabs);
        window.Content = root;
        window.ShowDialog();
    }
}

using System.Windows;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace WriteBench;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Contains("--self-test"))
        {
            try
            {
                SelfTest.Run();
                Shutdown(0);
            }
            catch (Exception error) { File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "self-test-error.txt"), error.ToString()); Shutdown(1); }
            return;
        }
        if (e.Args.Contains("--render-preview"))
        {
            try
            {
                var window = new MainWindow(preview: true);
                var view = (FrameworkElement)window.Content;
                view.Measure(new Size(1320, 840));
                view.Arrange(new Rect(0, 0, 1320, 840));
                view.UpdateLayout();
                var bitmap = new RenderTargetBitmap(1320, 840, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(view);
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var file = File.Create(Path.Combine(AppContext.BaseDirectory, "windows-preview.png"));
                encoder.Save(file);
                Shutdown(0);
            }
            catch (Exception error) { File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "preview-error.txt"), error.ToString()); Shutdown(1); }
            return;
        }
        new MainWindow().Show();
    }
}

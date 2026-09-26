using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace AppleLabs
{
    /// <summary>
    /// "--cli selftest [folder]": opens every page, tab and a few themes, saves a
    /// screenshot of each, and fails if anything throws or draws nothing. Used by
    /// the Windows tests on GitHub, where nobody is looking at the screen.
    /// </summary>
    static class SelfTest
    {
        public static readonly List<string> Failures = new List<string>();

        public static async Task<int> Run(string folder)
        {
            Directory.CreateDirectory(folder);
            var savedSettings = Paths.ReadText(Paths.Settings);
            var settings = Settings.Load();
            settings.Page = "play";
            var model = new LauncherModel(settings);
            model.RefreshStatus();
            var window = new MainWindow(model)
            {
                WindowStartupLocation = WindowStartupLocation.Manual,
                Left = 0,
                Top = 0,
                Width = 1140,
                Height = 780,
            };
            Application.Current.MainWindow = window;
            window.Show();
            var count = 0;

            async Task Shot(string name, Window target = null)
            {
                target = target ?? window;
                await Idle();
                // Let the appear-in animations finish.
                await Task.Delay(900);
                await Idle();
                target.UpdateLayout();
                try
                {
                    var visual = (FrameworkElement)target.Content;
                    int w = (int)Math.Max(1, visual.ActualWidth), h = (int)Math.Max(1, visual.ActualHeight);
                    var bitmap = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
                    bitmap.Render(visual);
                    if (IsBlank(bitmap)) Failures.Add(name + ": drew nothing");
                    var encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using (var file = File.Create(Path.Combine(folder, $"{++count:00}-{name}.png"))) encoder.Save(file);
                    // A small copy for quick previews.
                    var small = new TransformedBitmap(bitmap, new ScaleTransform(460.0 / w, 460.0 / w));
                    var jpeg = new JpegBitmapEncoder { QualityLevel = 45 };
                    jpeg.Frames.Add(BitmapFrame.Create(small));
                    Directory.CreateDirectory(Path.Combine(folder, "small"));
                    using (var file = File.Create(Path.Combine(folder, "small", $"{count:00}-{name}.jpg"))) jpeg.Save(file);
                    Console.WriteLine($"ok   {name}");
                }
                catch (Exception e)
                {
                    Failures.Add($"{name}: {e.Message}");
                    Console.WriteLine($"FAIL {name}: {e}");
                }
            }

            var pages = new (string page, string tab)[]
            {
                ("play", null),
                ("graphics", "presets"), ("graphics", "engine"), ("graphics", "flags"),
                ("style", "cursor"), ("style", "font"), ("style", "sound"), ("style", "files"),
                ("launcher", "look"), ("launcher", "accounts"), ("launcher", "general"), ("launcher", "help"),
            };
            foreach (var (page, tab) in pages)
            {
                model.Go(page, tab);
                await Shot(tab == null ? page : $"{page}-{tab}");
            }

            // A FastFlag, a preset and a mod round-trip through the interface.
            model.Go("graphics", "flags");
            model.SetFlag("FIntSelfTestFlag", 42L);
            model.ApplyPreset(FastFlags.Presets[2]);
            await Shot("graphics-flags-edited");
            if (model.ActivePreset?.Id != "performance") Failures.Add("preset did not apply");
            model.SetFlag("FIntSelfTestFlag", null);

            model.Go("launcher", "look");
            foreach (var theme in new[] { ThemeId.Neon, ThemeId.Glass, ThemeId.Custom })
            {
                model.ThemeId = theme;
                await Shot("theme-" + theme.ToString().ToLowerInvariant());
            }
            var picture = Path.Combine(Path.GetTempPath(), "applelabs-selftest.png");
            WriteTestPicture(picture);
            model.SetBackgroundImage(picture);
            await Task.Delay(1500);
            await Shot("theme-custom-picture");
            model.SetBackgroundImage(null);

            model.UiScale = 1.3;
            model.Go("play");
            await Shot("play-zoomed");
            model.UiScale = 1;

            var link = new LinkWindow(model) { WindowStartupLocation = WindowStartupLocation.Manual, Left = 40, Top = 40 };
            link.Show();
            await Shot("link-window", link);
            link.Close();

            window.Close();
            if (savedSettings != null) Paths.WriteAtomic(Paths.Settings, savedSettings);
            foreach (var f in Failures) Console.WriteLine("FAIL " + f);
            Console.WriteLine(Failures.Count == 0 ? $"All {count} screens drew correctly." : $"{Failures.Count} problem(s).");
            return Failures.Count == 0 ? 0 : 1;
        }

        static Task Idle() => Application.Current.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle).Task;

        static bool IsBlank(BitmapSource bitmap)
        {
            int w = bitmap.PixelWidth, h = bitmap.PixelHeight, stride = w * 4;
            var pixels = new byte[h * stride];
            bitmap.CopyPixels(pixels, stride, 0);
            var first = BitConverter.ToInt32(pixels, 0);
            for (var i = 0; i < pixels.Length; i += 4 * 97)
                if (BitConverter.ToInt32(pixels, i) != first) return false;
            return true;
        }

        static void WriteTestPicture(string path)
        {
            var visual = new DrawingVisual();
            using (var dc = visual.RenderOpen())
            {
                dc.DrawRectangle(new LinearGradientBrush(Colors.OrangeRed, Colors.MediumPurple, 45), null, new Rect(0, 0, 800, 500));
                dc.DrawEllipse(Brushes.Gold, null, new Point(560, 180), 90, 90);
            }
            var bitmap = new RenderTargetBitmap(800, 500, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(visual);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var file = File.Create(path)) encoder.Save(file);
        }
    }
}

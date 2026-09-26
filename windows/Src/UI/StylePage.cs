using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;

namespace AppleLabs
{
    sealed class StylePage : Stack
    {
        static readonly string[] Order = { "cursor", "font", "sound", "files" };

        public StylePage(LauncherModel m)
        {
            Spacing = 24;
            var tabs = K.Tabs(new[]
            {
                ("Cursor", "\uE962", "cursor"),
                ("Font", "\uE8D2", "font"),
                ("Sound", "\uE767", "sound"),
                ("Files", "\uE8B7", "files"),
            }, m.Settings.StyleTab, t => m.SetTab("style", t));
            K.FollowTab(tabs, m, () => m.Settings.StyleTab);
            Children.Add(K.PageHeader("Style", "Make Roblox look and sound your way. Mods come back after every update.", tabs));
            Children.Add(Tile.RestartHint(m));
            Children.Add(new Live(m, new[] { nameof(LauncherModel.ErrorMessage) },
                () => m.ErrorMessage == null ? null : K.ErrorBanner(m.ErrorMessage, () => m.ErrorMessage = null)));
            Children.Add(new TabHost(m, Order, () => m.Settings.StyleTab, tab =>
            {
                switch (tab)
                {
                    case "font": return new FontTab(m);
                    case "sound": return Sound(m);
                    case "files": return FilesTab(m);
                    default: return CursorTab(m);
                }
            }));
        }

        static readonly string[] ModsProps = { nameof(LauncherModel.ModsRevision), nameof(LauncherModel.Installed) };

        static UIElement NeedsRoblox(LauncherModel m) => m.Installed != null ? null :
            K.Card(K.H(12, K.Icon("\uE946", 16, K.Res("AccentBrush")),
                K.T("Roblox isn't installed yet. Press Play once; the classic cursor and sound come from its files.", 13, null, 0.75, wrap: true)), 16, new Thickness(14));

        // ------------------------------------------------------------------
        // Cursor

        static UIElement CursorTab(LauncherModel m) => new Live(m, ModsProps, () =>
        {
            var style = m.Mods.Cursor;
            void PickCustom()
            {
                var file = Files.Open("Choose a cursor image (square images look best)", "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff");
                if (file != null) m.SetCursor(CursorStyle.Custom, file);
            }
            UIElement TileFor(CursorStyle s, string title, string detail, int index, string image) =>
                Tile.Choice(K.V(12, CursorPreview(image), K.T(title, 17, FontWeights.Black), Two(K.T(detail, 12.5, null, 0.65, wrap: true))),
                    style == s, () => { if (s == CursorStyle.Custom) PickCustom(); else m.SetCursor(s); }, index);
            var grid = new Tiles { Columns = 3, Spacing = 16 };
            grid.Children.Add(TileFor(CursorStyle.Standard, "Default", "Roblox's current pointer", 1, Roblox.OriginalResource(Roblox.CursorPaths[0])));
            grid.Children.Add(TileFor(CursorStyle.Classic, "Classic arrow", "The black arrow from classic Roblox", 2, Roblox.Resource(Roblox.ClassicCursorSources[0])));
            grid.Children.Add(TileFor(CursorStyle.Custom, "Custom image", "Any PNG or JPEG, scaled to 64×64", 3, style == CursorStyle.Custom ? Roblox.ModFile(Roblox.CursorPaths[0]) : null));
            var stack = K.V(16, NeedsRoblox(m), grid);
            if (style == CursorStyle.Custom)
            {
                var again = K.Button(K.Label("\uE91B", "Choose a different image"), PickCustom, K.Size.Small, glass: true);
                again.HorizontalAlignment = HorizontalAlignment.Left;
                stack.Children.Add(K.AppearIn(again, 4));
            }
            return stack;
        });

        static TextBlock Two(TextBlock t)
        {
            t.Height = 34;
            return t;
        }

        /// <summary>A little "screen" with the cursor over a stud grid; it follows the pointer while you hover.</summary>
        static UIElement CursorPreview(string imagePath)
        {
            var grid = new Grid { Height = 124, ClipToBounds = true };
            grid.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(16),
                Background = new LinearGradientBrush(Color.FromRgb(92, 158, 242), Color.FromRgb(140, 204, 115), 90),
                Opacity = 0.55,
            });
            grid.Children.Add(new Rectangle { Fill = StudPattern(14), Opacity = 0.6 });
            var image = Images.File(imagePath);
            if (image != null)
            {
                var cursor = new Image { Source = image, Width = 64, Height = 64, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top };
                RenderOptions.SetBitmapScalingMode(cursor, BitmapScalingMode.HighQuality);
                var move = new TranslateTransform();
                cursor.RenderTransform = move;
                var canvas = new Grid { Children = { cursor } };
                grid.Children.Add(canvas);
                void Place(double fx, double fy, bool animate)
                {
                    var x = grid.ActualWidth * fx - 32;
                    var y = grid.ActualHeight * fy - 32;
                    if (!animate || !Motion.Enabled) { move.BeginAnimation(TranslateTransform.XProperty, null); move.BeginAnimation(TranslateTransform.YProperty, null); move.X = x; move.Y = y; return; }
                    var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
                    move.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(x, TimeSpan.FromMilliseconds(200)) { EasingFunction = ease });
                    move.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(y, TimeSpan.FromMilliseconds(200)) { EasingFunction = ease });
                }
                grid.SizeChanged += (s, e) => Place(0.5, 0.5, false);
                grid.MouseMove += (s, e) =>
                {
                    var p = e.GetPosition(grid);
                    Place(Math.Min(Math.Max(p.X / grid.ActualWidth, 0.15), 0.85), Math.Min(Math.Max(p.Y / grid.ActualHeight, 0.2), 0.8), true);
                };
                grid.MouseLeave += (s, e) => Place(0.5, 0.5, true);
            }
            else
            {
                grid.Children.Add(K.Icon("\uE710", 26, K.White(0.75)));
            }
            grid.Children.Add(new Border { CornerRadius = new CornerRadius(16), BorderBrush = K.White(0.15), BorderThickness = new Thickness(1) });
            grid.SizeChanged += (s, e) => grid.Clip = new RectangleGeometry(new Rect(grid.RenderSize), 16, 16);
            return grid;
        }

        public static Brush StudPattern(double spacing)
        {
            var group = new DrawingGroup();
            group.Children.Add(new GeometryDrawing(Brushes.Transparent, null, new RectangleGeometry(new Rect(0, 0, spacing, spacing))));
            var c = spacing / 2;
            group.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromArgb(38, 0, 0, 0)), null, new EllipseGeometry(new Point(c, c + 1), 4, 4)));
            group.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromArgb(46, 255, 255, 255)), null, new EllipseGeometry(new Point(c, c), 4, 4)));
            var brush = new DrawingBrush(group) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, spacing, spacing), ViewportUnits = BrushMappingMode.Absolute, Stretch = Stretch.None };
            brush.Freeze();
            return brush;
        }

        // ------------------------------------------------------------------
        // Sound

        static readonly MediaPlayer Player = new MediaPlayer();
        static string playing;

        static UIElement Sound(LauncherModel m) => new Live(m, ModsProps, () =>
        {
            var choice = m.Mods.Sound;
            UIElement TileFor(DeathSound s, string title, string detail, string glyph, int index, string file)
            {
                UIElement play = null;
                if (file != null && File.Exists(file))
                {
                    var icon = K.Icon(playing == file ? "\uE769" : "\uE768", 13, K.Res("OnAccentBrush"));
                    var circle = new Border
                    {
                        Width = 36, Height = 36, CornerRadius = new CornerRadius(18),
                        Background = K.Res("AccentBrush"), BorderBrush = K.White(0.35), BorderThickness = new Thickness(1), Child = icon,
                    };
                    var button = K.Plain(circle, () =>
                    {
                        var wasPlaying = playing == file;
                        Player.Stop();
                        playing = null;
                        icon.Text = "\uE768";
                        if (wasPlaying) return;
                        try
                        {
                            Player.Open(new Uri(file));
                            Player.Play();
                            playing = file;
                            icon.Text = "\uE769";
                            EventHandler ended = null;
                            ended = (s2, e2) => { Player.MediaEnded -= ended; playing = null; icon.Text = "\uE768"; };
                            Player.MediaEnded += ended;
                            Player.MediaFailed += (s2, e2) => { playing = null; icon.Text = "\uE768"; };
                        }
                        catch (Exception e) { Log.Warn("preview: " + e.Message); }
                    }, "Preview");
                    button.Margin = new Thickness(0, 0, 30, 0);
                    play = button;
                }
                var top = K.Row(0, K.IconBadge(glyph), play);
                return Tile.Choice(K.V(12, top, K.T(title, 17, FontWeights.Black), K.T(detail, 12.5, null, 0.65)),
                    choice == s, () =>
                    {
                        if (s == DeathSound.Custom)
                        {
                            var picked = Files.Open("Choose a sound to play when your character dies", "Sounds|*.ogg;*.mp3;*.wav");
                            if (picked != null) m.SetDeathSound(DeathSound.Custom, picked);
                        }
                        else m.SetDeathSound(s);
                    }, index);
            }
            var grid = new Tiles { Columns = 3, Spacing = 16 };
            grid.Children.Add(TileFor(DeathSound.Standard, "Default", "Roblox's current sound", "\uE767", 2, Roblox.OriginalResource(Roblox.DeathSoundPath)));
            grid.Children.Add(TileFor(DeathSound.Classic, "Classic “oof”", "The one everyone remembers", "\uE76E", 3, Roblox.Resource(Roblox.OofPath)));
            grid.Children.Add(TileFor(DeathSound.Custom, "Custom sound", "Any .ogg, .mp3 or .wav", "\uE8D6", 4, choice == DeathSound.Custom ? Roblox.ModFile(Roblox.DeathSoundPath) : null));
            return K.V(16, K.AppearIn(K.T("What you hear when your character resets.", 13, null, 0.65), 1), NeedsRoblox(m), grid);
        });

        // ------------------------------------------------------------------
        // Files

        static UIElement FilesTab(LauncherModel m) => new Live(m, ModsProps, () =>
        {
            var count = m.Mods.FileCount;
            var open = K.Button(K.Label("\uE8B7", "Open Folder"), () => { Directory.CreateDirectory(Paths.Mods); K.Open(Paths.Mods); });
            var reapply = K.Button(K.Label("\uE895", "Re-apply"), m.ApplyMods, glass: true);
            var clear = K.Button(K.Label("\uE74D", "Remove All"), () =>
            {
                if (Ask.Confirm(Window.GetWindow(open), "Remove all mods?",
                    "This deletes everything in the mods folder and restores Roblox's original files, including your cursor, font and death sound.",
                    "Remove All Mods", destructive: true))
                    m.ClearMods();
            }, glass: true);
            clear.IsEnabled = count > 0;
            var card = K.Card(K.V(16,
                K.H(14, K.IconBadge("\uE8B7", 52), K.V(3, K.T("Modifications folder", 17, FontWeights.Black),
                    K.T($"{count} file{(count == 1 ? "" : "s")} · mirrors Roblox's own folder", 12.5, null, 0.6))),
                K.T("Drop files in with the same path they have inside Roblox. For example, content\\sounds\\ouch.ogg replaces the death sound and content\\textures\\… replaces textures. Removing a file puts Roblox's original back.", 13, null, 0.65, wrap: true),
                K.Row(12, K.H(12, open, reapply), clear)), 22, new Thickness(22));
            return K.AppearIn(card, 1);
        });
    }

    /// <summary>The game's font: any .ttf/.otf installed on this PC, each shown in its own typeface.</summary>
    sealed class FontTab : Stack
    {
        static List<(string family, string file)> fonts;
        readonly LauncherModel m;
        readonly TextBox search;
        readonly ContentControl grid = new ContentControl { Focusable = false };

        public FontTab(LauncherModel model)
        {
            m = model;
            Spacing = 18;
            Children.Add(K.AppearIn(new Live(m, new[] { nameof(LauncherModel.ModsRevision) }, Preview), 1));
            search = new TextBox { Style = (Style)FindResource("Field"), Padding = new Thickness(14, 10, 14, 10), Tag = "Search fonts on this PC" };
            Chrome.SetCorner(search, new CornerRadius(999));
            search.TextChanged += (s, e) => Fill();
            Children.Add(K.AppearIn(search, 2));
            Children.Add(K.AppearIn(grid, 3));
            if (fonts == null)
            {
                grid.Content = K.T("Finding fonts…", 13, null, 0.6);
                Task.Run(() => FindFonts()).ContinueWith(t =>
                {
                    fonts = t.Result;
                    Dispatcher.BeginInvoke(new Action(Fill));
                });
            }
            else Fill();
        }

        UIElement Preview()
        {
            var name = m.Mods.FontName;
            FontFamily family = null;
            if (m.Mods.FontFile != null)
            {
                try
                {
                    // WPF can show a font straight from its file.
                    var folder = System.IO.Path.GetDirectoryName(m.Mods.FontFile) + "\\";
                    var families = Fonts.GetFontFamilies(new Uri(folder));
                    family = families.FirstOrDefault();
                }
                catch (Exception) { }
            }
            var choose = K.Button(K.Label("\uE8E5", "Font File…"), () =>
            {
                var file = Files.Open("Choose a .ttf or .otf font", "Fonts|*.ttf;*.otf");
                if (file != null) m.SetFont(file);
            }, K.Size.Small, glass: true);
            var reset = name == null ? null : K.Button(K.Label("\uE7A7", "Reset"), () => m.SetFont(null), K.Size.Small, glass: true);
            var sample = K.T("The quick brown fox jumps over the lazy dog", 34, FontWeights.Black);
            var chars = K.T("ABCDEFGHIJKLM  0123456789  !?&", 18, null, 0.75);
            if (family != null) { sample.FontFamily = chars.FontFamily = family; sample.FontWeight = FontWeights.Normal; }
            var viewbox = new Viewbox { Child = sample, Stretch = Stretch.Uniform, StretchDirection = StretchDirection.DownOnly, HorizontalAlignment = HorizontalAlignment.Left };
            return K.Card(K.V(10, K.Row(10, K.T((name ?? "Roblox default").ToUpperInvariant(), 11, FontWeights.Black, 0.6), choose, reset), viewbox, chars), 22, new Thickness(22));
        }

        void Fill()
        {
            if (fonts == null) return;
            var query = search.Text.Trim();
            search.Tag = $"Search {fonts.Count} fonts on this PC";
            var tiles = new Tiles { MinColumnWidth = 200, Spacing = 12 };
            foreach (var (family, file) in fonts.Where(f => query.Length == 0 || f.family.IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0).Take(150))
            {
                var selected = m.Mods.FontName == family;
                var sample = K.T("Aa", 30);
                sample.FontFamily = new FontFamily(family);
                sample.Height = 42;
                var content = K.V(6, sample, K.T(family, 12, FontWeights.SemiBold, 0.7));
                var f = file;
                var fam = family;
                tiles.Children.Add(Tile.Choice(content, selected, () => { m.SetFont(f, fam); Fill(); }, 0, 16, new Thickness(14)));
            }
            grid.Content = tiles;
        }

        /// <summary>TrueType and OpenType fonts installed for everyone or just this user.</summary>
        static List<(string, string)> FindFonts()
        {
            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var folders = new[]
            {
                Environment.GetFolderPath(Environment.SpecialFolder.Fonts),
                System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Windows", "Fonts"),
            };
            foreach (var folder in folders.Where(Directory.Exists))
            {
                foreach (var file in Directory.EnumerateFiles(folder).Where(f => f.EndsWith(".ttf", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".otf", StringComparison.OrdinalIgnoreCase)))
                {
                    try
                    {
                        using (var collection = new System.Drawing.Text.PrivateFontCollection())
                        {
                            collection.AddFontFile(file);
                            var family = collection.Families.FirstOrDefault()?.Name;
                            if (string.IsNullOrEmpty(family) || family.StartsWith("@")) continue;
                            // Prefer the regular face: the shortest file name for a family is usually it.
                            if (!result.TryGetValue(family, out var existing) || System.IO.Path.GetFileName(file).Length < System.IO.Path.GetFileName(existing).Length)
                                result[family] = file;
                        }
                    }
                    catch (Exception) { }
                }
            }
            return result.OrderBy(p => p.Key, StringComparer.OrdinalIgnoreCase).Select(p => (p.Key, p.Value)).ToList();
        }
    }
}

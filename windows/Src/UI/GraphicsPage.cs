using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace AppleLabs
{
    sealed class GraphicsPage : Stack
    {
        static readonly string[] Order = { "presets", "engine", "flags" };

        public GraphicsPage(LauncherModel m)
        {
            Spacing = 24;
            m.LoadFlags();
            var tabs = K.Tabs(new[]
            {
                ("Presets", "\uE8FD", "presets"),
                ("Engine", "\uE9E9", "engine"),
                ("FastFlags", "\uE7C1", "flags"),
            }, m.Settings.GraphicsTab, t => m.SetTab("graphics", t));
            K.FollowTab(tabs, m, () => m.Settings.GraphicsTab);
            Children.Add(K.PageHeader("Graphics", "Tune how Roblox runs and looks. Applied every time you play.", tabs));
            Children.Add(Tile.RestartHint(m));
            Children.Add(new Live(m, new[] { nameof(LauncherModel.FlagsError) }, () => m.FlagsError == null ? null : K.ErrorBanner(m.FlagsError)));
            Children.Add(new TabHost(m, Order, () => m.Settings.GraphicsTab, tab =>
            {
                switch (tab)
                {
                    case "engine": return Engine(m);
                    case "flags": return new FlagsEditor(m);
                    default: return Presets(m);
                }
            }));
        }

        // ------------------------------------------------------------------
        // Presets

        static UIElement Presets(LauncherModel m) => new Live(m, new[] { nameof(LauncherModel.Flags) }, () =>
        {
            var active = m.ActivePreset;
            var grid = new Tiles { Columns = 3, Spacing = 16 };
            var i = 0;
            foreach (var preset in FastFlags.Presets)
            {
                var p = preset;
                var content = K.V(11,
                    K.IconBadge(p.Glyph),
                    K.T(p.Name, 19, FontWeights.Black),
                    Blurb(p.Blurb),
                    K.V(6, Meter("Speed", p.Speed), Meter("Looks", p.Looks)),
                    K.Chips(p.Highlights));
                grid.Children.Add(Tile.Choice(content, active?.Id == p.Id, () => m.ApplyPreset(p), ++i));
            }
            var info = K.Card(K.Row(12,
                K.H(12, K.Icon(active == null ? "\uE945" : "\uE946", 14, K.Res("AccentBrush")),
                    K.T(active == null
                        ? "You're running a custom mix. Pick a preset to reset the engine settings, or keep fine-tuning."
                        : "Presets only change the engine settings. Fine-tune them any time.", 12.5, null, 0.7, wrap: true)),
                K.Button("Fine-tune", () => m.SetTab("graphics", "engine"), K.Size.Small, glass: true)), 16, new Thickness(14));
            return K.V(18, grid, K.AppearIn(info, 7));
        });

        static TextBlock Blurb(string text)
        {
            var t = K.T(text, 12.5, null, 0.7, wrap: true);
            // Two lines' worth, so cards line up.
            t.Height = 34;
            return t;
        }

        /// <summary>Five little blocks that fill up.</summary>
        static UIElement Meter(string label, int value)
        {
            var name = K.T(label, 11, FontWeights.Bold, 0.6);
            name.Width = 42;
            var blocks = new UniformGrid5();
            for (var i = 0; i < 5; i++)
            {
                var block = new Border
                {
                    Height = 7,
                    CornerRadius = new CornerRadius(3),
                    Background = i < value ? K.Res("AccentBrush") : K.White(0.12),
                    Margin = new Thickness(i == 0 ? 0 : 2, 0, i == 4 ? 0 : 2, 0),
                };
                if (i < value && Motion.Enabled)
                {
                    var grow = new ScaleTransform(1, 0.1);
                    block.RenderTransformOrigin = new Point(0.5, 1);
                    block.RenderTransform = grow;
                    grow.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(400))
                    {
                        BeginTime = TimeSpan.FromMilliseconds(80 + i * 50),
                        EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.6 },
                    });
                }
                blocks.Children.Add(block);
            }
            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(name);
            Grid.SetColumn(blocks, 1);
            blocks.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(blocks);
            return row;
        }

        sealed class UniformGrid5 : System.Windows.Controls.Primitives.UniformGrid
        {
            public UniformGrid5() { Columns = 5; Rows = 1; }
        }

        // ------------------------------------------------------------------
        // Engine

        static readonly string[] GrassKeys = { "FIntFRMMinGrassDistance", "FIntFRMMaxGrassDistance" };

        static long IntFlag(LauncherModel m, string key) => m.Flags.TryGetValue(key, out var v) && v is long n ? n : -1;
        static bool BoolFlag(LauncherModel m, string key) => m.Flags.TryGetValue(key, out var v) && v is bool b && b;

        static UIElement Engine(LauncherModel m) => new Live(m, new[] { nameof(LauncherModel.Flags) }, () =>
        {
            var textures = m.Flags.TryGetValue("DFFlagTextureQualityOverrideEnabled", out var on) && on is bool b && b
                ? IntFlag(m, "DFIntTextureQualityOverride") : -1;
            var grassOff = GrassKeys.All(k => m.Flags.TryGetValue(k, out var v) && v is long n && n == 0);

            var group1 = K.Group(
                K.SettingRow("Anti-aliasing", "Smooths jagged edges; higher costs more",
                    K.Chips(new[] { ("Default", -1L), ("Off", 1L), ("2×", 2L), ("4×", 4L), ("8×", 8L) }, IntFlag(m, "FIntDebugForceMSAASamples"),
                        v => m.SetFlag("FIntDebugForceMSAASamples", v == -1 ? null : (object)v))),
                K.SettingRow("Texture quality", "Overrides Roblox's automatic choice",
                    K.Chips(new[] { ("Default", -1L), ("Lowest", 0L), ("Low", 1L), ("Medium", 2L), ("High", 3L) }, textures,
                        v => m.SetFlags(new Dictionary<string, object>
                        {
                            ["DFFlagTextureQualityOverrideEnabled"] = v == -1 ? null : (object)true,
                            ["DFIntTextureQualityOverride"] = v == -1 ? null : (object)v,
                        }))));
            var group2 = K.Group(
                K.SettingRow("Remove grass", "Hides terrain grass for a cleaner, faster view",
                    K.Switch(grassOff, v => m.SetFlags(GrassKeys.ToDictionary(k => k, k => v ? (object)0L : null)))),
                K.SettingRow("Plain gray sky", "Replaces the skybox with flat gray",
                    K.Switch(BoolFlag(m, "FFlagDebugSkyGray"), v => m.SetFlag("FFlagDebugSkyGray", v ? (object)true : null))));
            var frameRate = K.Card(K.H(12, K.Icon("\uEC4A", 16, K.Res("AccentBrush")), K.V(4,
                K.T("Frame rate", 14, FontWeights.Bold),
                K.T("Roblox no longer lets launchers set the frame rate. Set it in Roblox itself: open the menu in any game, then Settings › Maximum Frame Rate.", 12.5, null, 0.7, wrap: true))),
                16, new Thickness(14));
            return K.V(18, K.AppearIn(group1, 1), K.AppearIn(group2, 2), K.AppearIn(frameRate, 3),
                K.AppearIn(K.T("Roblox only reads the FastFlags on its allowlist and ignores the rest. Changes load the next time Roblox starts; if it's open, the launcher restarts it when you press Play.", 12, null, 0.5, wrap: true), 4));
        });
    }

    /// <summary>The FastFlags editor: search, add, edit, import and export.</summary>
    sealed class FlagsEditor : Stack
    {
        readonly LauncherModel m;
        readonly TextBox search;
        readonly Live list;

        public FlagsEditor(LauncherModel model)
        {
            m = model;
            Spacing = 16;
            search = new TextBox { Style = (Style)FindResource("Field"), Padding = new Thickness(12, 9, 12, 9) };
            Chrome.SetCorner(search, new CornerRadius(999));
            UpdateSearchHint();
            var import = K.Button(K.Label("\uE896", "Import"), () => Ask.ImportFlags(Window.GetWindow(this), m.ImportFlags), K.Size.Small, glass: true);
            var copy = K.Button(K.Label("\uE8C8", "Copy JSON"), () => { try { Clipboard.SetText(FastFlags.ExportJson(m.Flags)); } catch (Exception) { } }, K.Size.Small, glass: true);
            var clear = K.Button(K.Label("\uE74D", "Clear"), () =>
            {
                if (Ask.Confirm(Window.GetWindow(this), "Remove all FastFlags?", "Every flag you've set is removed, including the ones presets and the Engine tab set.", "Remove All", destructive: true))
                    m.ReplaceFlags(new Dictionary<string, object>());
            }, K.Size.Small, glass: true);
            Children.Add(K.AppearIn(K.Row(10, search, import, copy, clear), 1));

            var name = new TextBox { Style = (Style)FindResource("Field"), FontFamily = new FontFamily("Cascadia Mono, Consolas"), Tag = "FlagName" };
            var value = new TextBox { Style = (Style)FindResource("Field"), FontFamily = new FontFamily("Cascadia Mono, Consolas"), Tag = "value", Width = 150 };
            var add = K.Button(K.Label("\uE710", "Add"), null, K.Size.Small);
            void Add()
            {
                var n = name.Text.Trim();
                if (n.Length == 0) return;
                m.SetFlag(n, FastFlags.Parse(value.Text));
                name.Text = value.Text = "";
                name.Focus();
            }
            add.Click += (s, e) => Add();
            add.IsEnabled = false;
            name.TextChanged += (s, e) => add.IsEnabled = name.Text.Trim().Length > 0;
            value.KeyDown += (s, e) => { if (e.Key == Key.Enter) Add(); };
            name.KeyDown += (s, e) => { if (e.Key == Key.Enter) value.Focus(); };
            var addRow = K.Row(10, name, value, add);
            addRow.Margin = new Thickness(14);

            list = new Live(m, new[] { nameof(LauncherModel.Flags) }, BuildList);
            search.TextChanged += (s, e) => list.Rebuild();
            var card = K.Card(K.V(0, list, addRow), 20, new Thickness(0));
            Children.Add(K.AppearIn(card, 2));
            Children.Add(K.T("true/false and whole numbers are saved as booleans and integers; anything else is saved as text. Works with flags exported from Bloxstrap and Fishstrap.", 12, null, 0.5, wrap: true));
        }

        void UpdateSearchHint() => search.Tag = $"Search {m.Flags.Count} flags";

        UIElement BuildList()
        {
            UpdateSearchHint();
            var query = search.Text.Trim();
            var names = m.Flags.Keys.OrderBy(k => k, StringComparer.OrdinalIgnoreCase)
                .Where(k => query.Length == 0 || k.IndexOf(query, StringComparison.OrdinalIgnoreCase) >= 0).ToList();
            var stack = K.V(0);
            if (names.Count == 0)
            {
                var empty = K.T(m.Flags.Count == 0 ? "No FastFlags yet. Add one below or import a JSON file." : $"No flags match \"{query}\".", 13, null, 0.55);
                empty.Margin = new Thickness(18);
                stack.Children.Add(empty);
                stack.Children.Add(Divider());
            }
            foreach (var n in names)
            {
                stack.Children.Add(FlagRow(n, m.Flags[n]));
                stack.Children.Add(Divider());
            }
            return stack;
        }

        static UIElement Divider() => new Border { Height = 1, Background = K.Res("DividerBrush"), Margin = new Thickness(18, 0, 0, 0) };

        UIElement FlagRow(string name, object value)
        {
            var label = K.T(name, 13);
            label.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            label.VerticalAlignment = VerticalAlignment.Center;
            label.ToolTip = name;
            UIElement editor;
            if (value is bool b)
            {
                editor = K.Switch(b, v => m.SetFlag(name, v));
            }
            else
            {
                var box = new TextBox
                {
                    Style = (Style)FindResource("Field"),
                    FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                    Text = FastFlags.Text(value),
                    Width = 150,
                    TextAlignment = TextAlignment.Right,
                    Padding = new Thickness(7),
                };
                void Commit()
                {
                    var parsed = FastFlags.Parse(box.Text);
                    if (!FastFlags.Same(parsed, value)) m.SetFlag(name, parsed);
                }
                box.KeyDown += (s, e) => { if (e.Key == Key.Enter) Commit(); };
                box.LostKeyboardFocus += (s, e) => Commit();
                editor = box;
            }
            var remove = K.Plain(K.Icon("\uE738", 14, K.White(0.45)), () => m.SetFlag(name, null), "Remove " + name);
            remove.VerticalAlignment = VerticalAlignment.Center;
            UIElement nameCell = label;
            if (!FastFlags.Allowed.Contains(name))
            {
                var orange = Color.FromRgb(255, 159, 10);
                var ignored = K.T("Ignored by Roblox", 10.5, FontWeights.Bold);
                ignored.Foreground = new SolidColorBrush(orange);
                var badge = new Border
                {
                    Child = ignored, Padding = new Thickness(7, 3, 7, 3), CornerRadius = new CornerRadius(999),
                    Background = new SolidColorBrush(Color.FromArgb(38, orange.R, orange.G, orange.B)),
                    VerticalAlignment = VerticalAlignment.Center,
                    ToolTip = "Not on Roblox's FastFlag allowlist, so Roblox skips it",
                };
                nameCell = K.H(8, label, badge);
            }
            var row = K.Row(12, nameCell, editor, remove);
            row.Margin = new Thickness(18, 10, 18, 10);
            return row;
        }
    }
}

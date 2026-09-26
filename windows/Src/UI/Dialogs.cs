using System;
using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shell;

namespace AppleLabs
{
    /// <summary>Small dark dialogs in the launcher's style.</summary>
    static class Ask
    {
        static Window Shell(Window owner, double width)
        {
            var w = new Window
            {
                Owner = owner,
                Width = width,
                SizeToContent = SizeToContent.Height,
                WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
                ResizeMode = ResizeMode.NoResize,
                ShowInTaskbar = owner == null,
                Background = new SolidColorBrush(Color.FromRgb(22, 22, 30)),
                Foreground = Brushes.White,
                FontFamily = owner?.FontFamily ?? LauncherFonts.Family("segoe"),
                Title = "Apple Labs",
                UseLayoutRounding = true,
            };
            WindowChrome.SetWindowChrome(w, new WindowChrome { CaptionHeight = 0, GlassFrameThickness = new Thickness(0), ResizeBorderThickness = new Thickness(0), UseAeroCaptionButtons = false });
            w.SourceInitialized += (s, e) => Dwm.DarkTitleBar(w);
            w.KeyDown += (s, e) => { if (e.Key == Key.Escape) w.Close(); };
            return w;
        }

        static Border Frame(UIElement content) => new Border
        {
            Padding = new Thickness(22),
            BorderBrush = K.White(0.12),
            BorderThickness = new Thickness(1),
            Background = new LinearGradientBrush(Color.FromRgb(30, 30, 42), Color.FromRgb(18, 18, 26), 90),
            Child = content,
        };

        /// <summary>Asks a yes/no question. Returns true when the user confirms.</summary>
        public static bool Confirm(Window owner, string title, string message, string confirm, bool destructive = false)
        {
            var w = Shell(owner, 420);
            var result = false;
            var yes = K.Button(confirm, () => { result = true; w.Close(); }, K.Size.Small);
            yes.IsDefault = true;
            if (destructive)
            {
                Chrome.SetFace(yes, new LinearGradientBrush(Color.FromRgb(255, 99, 89), Color.FromRgb(230, 57, 48), 90));
                Chrome.SetLipBrush(yes, new SolidColorBrush(Color.FromRgb(128, 30, 25)));
                Chrome.SetInk(yes, Brushes.White);
            }
            var no = K.Button("Cancel", w.Close, K.Size.Small, glass: true);
            no.IsCancel = true;
            var buttons = K.H(10, no, yes);
            buttons.HorizontalAlignment = HorizontalAlignment.Right;
            w.Content = Frame(K.V(16, K.T(title, 17, FontWeights.Black, 1, wrap: true), K.T(message, 13, null, 0.72, wrap: true), buttons));
            w.ShowDialog();
            return result;
        }

        public static void Tell(Window owner, string title, string message)
        {
            var w = Shell(owner, 420);
            var ok = K.Button("OK", w.Close, K.Size.Small);
            ok.IsDefault = true;
            ok.HorizontalAlignment = HorizontalAlignment.Right;
            w.Content = Frame(K.V(16, K.T(title, 17, FontWeights.Black, 1, wrap: true), K.T(message, 13, null, 0.72, wrap: true), ok));
            w.ShowDialog();
        }

        /// <summary>Asks for pasted FastFlags JSON. <paramref name="import"/> returns an error, or null when it worked.</summary>
        public static void ImportFlags(Window owner, Func<string, string> import)
        {
            var w = Shell(owner, 560);
            var text = new TextBox
            {
                Style = (Style)Application.Current.FindResource("Field"),
                AcceptsReturn = true,
                AcceptsTab = true,
                TextWrapping = TextWrapping.NoWrap,
                FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                Height = 240,
                VerticalContentAlignment = VerticalAlignment.Top,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                Tag = "{ \"FIntDebugForceMSAASamples\": 4 }",
            };
            var error = K.T("", 12.5, null, 1, wrap: true);
            error.Foreground = new SolidColorBrush(Color.FromRgb(255, 120, 110));
            error.Visibility = Visibility.Collapsed;
            var choose = K.Button(K.Label("\uE8E5", "Choose File…"), () =>
            {
                var file = Files.Open("Choose a FastFlags JSON file", "JSON files|*.json|All files|*.*");
                if (file != null)
                {
                    try { text.Text = File.ReadAllText(file); }
                    catch (Exception e) { error.Text = e.Message; error.Visibility = Visibility.Visible; }
                }
            }, K.Size.Small, glass: true);
            var cancel = K.Button("Cancel", w.Close, K.Size.Small, glass: true);
            cancel.IsCancel = true;
            var ok = K.Button("Import", () =>
            {
                var problem = import(text.Text);
                if (problem == null) w.Close();
                else { error.Text = problem; error.Visibility = Visibility.Visible; }
            }, K.Size.Small);
            w.Content = Frame(K.V(12,
                K.T("Import FastFlags", 17, FontWeights.Black),
                K.T("Paste a JSON object of flags, such as an export from Bloxstrap or Fishstrap. Flags with the same name are replaced.", 13, null, 0.7, wrap: true),
                text, error,
                K.Row(10, choose, cancel, ok)));
            w.Loaded += (s, e) => text.Focus();
            w.ShowDialog();
        }
    }

    /// <summary>Open-file pickers.</summary>
    static class Files
    {
        public static string Open(string title, string filter)
        {
            var dialog = new Microsoft.Win32.OpenFileDialog { Title = title, Filter = filter, CheckFileExists = true };
            return dialog.ShowDialog(Application.Current.MainWindow) == true ? dialog.FileName : null;
        }

        public static Color? PickColor(Color current)
        {
            using (var dialog = new System.Windows.Forms.ColorDialog { FullOpen = true, AnyColor = true, Color = System.Drawing.Color.FromArgb(current.R, current.G, current.B) })
            {
                if (dialog.ShowDialog() != System.Windows.Forms.DialogResult.OK) return null;
                return Color.FromRgb(dialog.Color.R, dialog.Color.G, dialog.Color.B);
            }
        }
    }

    /// <summary>A selectable card for presets, cursors, sounds and themes.</summary>
    static class Tile
    {
        public static Button Choice(UIElement content, bool selected, Action click, int index = 0, double corner = 22, Thickness? padding = null)
        {
            var card = K.Card(content, corner, padding ?? new Thickness(18), selected);
            var grid = new Grid { Children = { card } };
            if (selected)
            {
                var check = new Border
                {
                    Width = 26, Height = 26, CornerRadius = new CornerRadius(13),
                    Background = K.Res("AccentBrush"), BorderBrush = K.White(0.4), BorderThickness = new Thickness(1),
                    Child = K.Icon("\uE73E", 12, K.Res("OnAccentBrush")),
                    HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
                    Margin = new Thickness(12),
                };
                grid.Children.Add(check);
                if (Motion.Enabled)
                {
                    var pop = new ScaleTransform(0.1, 0.1);
                    check.RenderTransformOrigin = new Point(0.5, 0.5);
                    check.RenderTransform = pop;
                    var spring = new ElasticEase { EasingMode = EasingMode.EaseOut, Oscillations = 1, Springiness = 4 };
                    pop.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(500)) { EasingFunction = spring });
                    pop.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(500)) { EasingFunction = spring });
                }
            }
            var grow = new ScaleTransform(1, 1);
            var lift = new TranslateTransform();
            grid.RenderTransformOrigin = new Point(0.5, 0.5);
            grid.RenderTransform = new TransformGroup { Children = { grow, lift } };
            var b = K.Plain(grid, click);
            b.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            b.VerticalContentAlignment = VerticalAlignment.Stretch;
            void Hover(bool on)
            {
                if (!selected) card.BorderBrush = on ? K.White(0.3) : K.Res("GlassStrokeBrush");
                if (!selected) card.BorderThickness = new Thickness(on ? 2 : 1);
                if (!Motion.Enabled) return;
                var spring = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.5 };
                var time = TimeSpan.FromMilliseconds(300);
                grow.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(on ? 1.025 : 1, time) { EasingFunction = spring });
                grow.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(on ? 1.025 : 1, time) { EasingFunction = spring });
                lift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(on ? -3 : 0, time) { EasingFunction = spring });
            }
            b.MouseEnter += (s, e) => Hover(true);
            b.MouseLeave += (s, e) => Hover(false);
            return K.AppearIn(b, index);
        }

        /// <summary>Shown on settings pages when a change needs Roblox to restart.</summary>
        public static UIElement RestartHint(LauncherModel m) =>
            new Live(m, new[] { nameof(LauncherModel.NeedsRestart), nameof(LauncherModel.RobloxRunning), nameof(LauncherModel.Busy) }, () =>
            {
                if (!m.NeedsRestart || !m.RobloxRunning) return null;
                var button = K.Button("Restart Roblox", m.RestartRoblox, K.Size.Small);
                button.IsEnabled = !m.Busy;
                return K.Card(K.Row(12, K.H(12, K.Icon("\uE72C", 20, K.Res("AccentBrush")), K.T("Roblox is still running with your old settings. Restart it to use your changes.", 13.5, FontWeights.SemiBold, 1, wrap: true)), button),
                    18, new Thickness(14), highlighted: true);
            });
    }

    /// <summary>Hosts a page's sub-tab and slides the new one in from the side it's on.</summary>
    sealed class TabHost : ContentControl
    {
        readonly LauncherModel m;
        readonly string[] order;
        readonly Func<string> current;
        readonly Func<string, UIElement> build;
        string shown;

        public TabHost(LauncherModel model, string[] order, Func<string> current, Func<string, UIElement> build)
        {
            m = model;
            this.order = order;
            this.current = current;
            this.build = build;
            Focusable = false;
            Show(animated: false);
            PropertyChangedEventHandler handler = (s, e) => { if (e.PropertyName == "Tab") Show(animated: true); };
            Loaded += (s, e) => m.PropertyChanged += handler;
            Unloaded += (s, e) => m.PropertyChanged -= handler;
        }

        void Show(bool animated)
        {
            var tab = current();
            if (tab == shown) return;
            var forward = Array.IndexOf(order, tab) > Array.IndexOf(order, shown);
            shown = tab;
            Motion.PageShownAt = DateTime.UtcNow;
            var content = build(tab);
            Content = content;
            if (!animated || !Motion.Enabled || !(content is UIElement el)) return;
            var shift = new TranslateTransform(forward ? 44 : -44, 0);
            el.RenderTransform = shift;
            el.Opacity = 0;
            el.BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(180)));
            shift.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(320)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.3 } });
        }
    }
}

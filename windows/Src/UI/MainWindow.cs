using System;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Shell;

namespace AppleLabs
{
    sealed class MainWindow : Window
    {
        public static readonly Size MinimumSize = new Size(1040, 660);

        readonly LauncherModel m;
        readonly Grid root = new Grid();
        readonly Backdrop backdrop = new Backdrop();
        readonly Rectangle dimmer = new Rectangle { IsHitTestVisible = false };
        readonly ScaleTransform scale = new ScaleTransform(1, 1);
        readonly ContentControl pageHost = new ContentControl { Focusable = false };
        readonly ScrollViewer scroller = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Focusable = false };
        readonly Border panel = new Border();
        readonly Button maximize;
        bool glassOn;

        public MainWindow(LauncherModel model)
        {
            m = model;
            Title = "Apple Labs";
            Width = 1140;
            Height = 780;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = new SolidColorBrush(Color.FromRgb(8, 8, 12));
            Foreground = Brushes.White;
            FontFamily = LauncherFonts.Family(m.FontId);
            UseLayoutRounding = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Ideal);
            WindowChrome.SetWindowChrome(this, new WindowChrome
            {
                CaptionHeight = 44,
                ResizeBorderThickness = new Thickness(6),
                GlassFrameThickness = new Thickness(0),
                CornerRadius = new CornerRadius(0),
                UseAeroCaptionButtons = false,
            });

            root.Children.Add(backdrop);
            root.Children.Add(dimmer);

            // Everything but the window buttons is zoomed by the Interface size setting.
            var scaled = new Grid { LayoutTransform = scale };
            scaled.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(228) });
            scaled.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var sidebar = new Sidebar(m);
            scaled.Children.Add(sidebar);

            scroller.Content = pageHost;
            panel.Child = scroller;
            panel.CornerRadius = new CornerRadius(26);
            panel.BorderBrush = K.White(0.07);
            panel.BorderThickness = new Thickness(1);
            panel.Margin = new Thickness(0, 56, 20, 20);
            panel.SizeChanged += (s, e) =>
                scroller.Clip = new RectangleGeometry(new Rect(0, 0, Math.Max(0, panel.ActualWidth - 2), Math.Max(0, panel.ActualHeight - 2)), 25, 25);
            Grid.SetColumn(panel, 1);
            scaled.Children.Add(panel);

            var status = new StatusCapsule(m) { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 12, 160, 0) };
            Grid.SetColumn(status, 1);
            scaled.Children.Add(status);
            root.Children.Add(scaled);

            // Window buttons, drawn to match (the title bar is hidden).
            var minimize = CaptionButton("\uE921", "Minimize", () => WindowState = WindowState.Minimized);
            maximize = CaptionButton("\uE922", "Maximize", () => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized);
            var close = CaptionButton("\uE8BB", "Close", Close);
            close.Style = (Style)FindResource("Caption.Close");
            var captions = K.H(0, minimize, maximize, close);
            captions.HorizontalAlignment = HorizontalAlignment.Right;
            captions.VerticalAlignment = VerticalAlignment.Top;
            root.Children.Add(captions);

            Content = root;
            ShowPage(animated: false);

            StateChanged += (s, e) =>
            {
                // A maximised borderless window hangs over the screen edge by the resize border.
                root.Margin = WindowState == WindowState.Maximized ? new Thickness(7) : new Thickness(0);
                maximize.Content = WindowState == WindowState.Maximized ? "\uE923" : "\uE922";
            };
            SourceInitialized += (s, e) => ApplyLook();
            Activated += (s, e) => m.InvalidateMods();
            PreviewKeyDown += OnKey;
            m.PropertyChanged += OnModel;
            Closed += (s, e) => m.PropertyChanged -= OnModel;
            ApplyScale();
        }

        Button CaptionButton(string glyph, string tip, Action click)
        {
            var b = new Button { Content = glyph, Style = (Style)FindResource("Caption"), ToolTip = tip };
            b.Click += (s, e) => click();
            WindowChrome.SetIsHitTestVisibleInChrome(b, true);
            return b;
        }

        void OnModel(object sender, PropertyChangedEventArgs e)
        {
            switch (e.PropertyName)
            {
                case nameof(LauncherModel.Page): ShowPage(animated: true); break;
                case nameof(LauncherModel.Theme):
                case nameof(LauncherModel.AnimatedBackground):
                case nameof(LauncherModel.ShowStuds):
                case nameof(LauncherModel.BackgroundImage):
                case nameof(LauncherModel.BackgroundDim):
                    ApplyLook();
                    break;
                case nameof(LauncherModel.UiScale): ApplyScale(); break;
                case nameof(LauncherModel.FontId):
                    FontFamily = LauncherFonts.Family(m.FontId);
                    ShowPage(animated: false);
                    break;
            }
        }

        void ApplyLook()
        {
            var theme = m.Theme;
            ThemeManager.Apply(theme);
            glassOn = Dwm.SetGlass(this, theme.IsGlass && m.BackgroundImage == null);
            Background = glassOn ? Brushes.Transparent : new SolidColorBrush(Color.FromRgb(8, 8, 12));
            backdrop.Update(theme, m.AnimatedBackground, m.ShowStuds, glassOn, m.BackgroundImage, m.BackgroundDim);
            dimmer.Fill = K.Black(theme.IsGlass ? 0.04 : 0.1);
            panel.Background = K.Black(theme.IsGlass ? 0.16 : 0.26);
        }

        void ApplyScale()
        {
            var s = m.UiScale;
            scale.ScaleX = scale.ScaleY = s;
            MinWidth = MinimumSize.Width * s;
            MinHeight = MinimumSize.Height * s;
            // Keep the window at least as big as the interface needs.
            if (Width < MinWidth) Width = MinWidth;
            if (Height < MinHeight) Height = MinHeight;
        }

        void ShowPage(bool animated)
        {
            Motion.PageShownAt = DateTime.UtcNow;
            UIElement page;
            switch (m.Page)
            {
                case "graphics": page = new GraphicsPage(m); break;
                case "style": page = new StylePage(m); break;
                case "launcher": page = new LauncherPage(m); break;
                default: page = new PlayPage(m); break;
            }
            var wrapper = new Border { Padding = new Thickness(30), Child = page, MaxWidth = 1200, HorizontalAlignment = HorizontalAlignment.Left };
            pageHost.Content = wrapper;
            scroller.ScrollToTop();
            if (animated && Motion.Enabled)
            {
                var shift = new TranslateTransform(0, m.Forward ? 14 : -14);
                wrapper.RenderTransform = shift;
                wrapper.Opacity = 0;
                var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
                wrapper.BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(200)));
                shift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(280)) { EasingFunction = ease });
            }
            // Stop the first text field on a page from grabbing keyboard focus.
            Keyboard.ClearFocus();
        }

        void OnKey(object sender, KeyEventArgs e)
        {
            if ((Keyboard.Modifiers & ModifierKeys.Control) == 0) return;
            switch (e.Key)
            {
                case Key.D1: m.Go("play"); break;
                case Key.D2: m.Go("graphics"); break;
                case Key.D3: m.Go("style"); break;
                case Key.D4: m.Go("launcher"); break;
                case Key.OemPlus: case Key.Add: m.Zoom(0.05); break;
                case Key.OemMinus: case Key.Subtract: m.Zoom(-0.05); break;
                case Key.D0: case Key.NumPad0: m.UiScale = 1; break;
                default: return;
            }
            e.Handled = true;
        }
    }

    // ----------------------------------------------------------------------

    /// <summary>The sidebar: logo, pages with a sliding highlight, and the account switcher.</summary>
    sealed class Sidebar : Grid
    {
        static readonly (string id, string title, string glyph)[] Pages =
        {
            ("play", "Play", "\uE7FC"),
            ("graphics", "Graphics", "\uEC4A"),
            ("style", "Style", "\uE771"),
            ("launcher", "Launcher", "\uE713"),
        };
        const double ItemHeight = 42, Gap = 2;

        readonly LauncherModel m;
        readonly Border highlight;
        readonly TranslateTransform highlightMove = new TranslateTransform();
        readonly RadioButton[] items = new RadioButton[Pages.Length];
        readonly TextBlock[] icons = new TextBlock[Pages.Length];
        readonly Popup accountsPopup;
        readonly ContentControl accountButtonHost = new ContentControl { Focusable = false };

        public Sidebar(LauncherModel model)
        {
            m = model;
            Margin = new Thickness(14, 0, 14, 18);
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var logo = new Image { Source = Images.Logo, Width = 38, Height = 38 };
            RenderOptions.SetBitmapScalingMode(logo, BitmapScalingMode.HighQuality);
            var title = K.V(0, K.T("Apple Labs", 21, FontWeights.Black), K.T("for Roblox on Windows", 11, FontWeights.Medium, 0.55));
            title.VerticalAlignment = VerticalAlignment.Center;
            var brand = K.Plain(K.H(12, logo, title), () => m.Go("play"));
            brand.HorizontalAlignment = HorizontalAlignment.Left;
            brand.Margin = new Thickness(10, 58, 0, 22);
            Children.Add(brand);

            var list = new Grid();
            highlight = new Border
            {
                Height = ItemHeight,
                VerticalAlignment = VerticalAlignment.Top,
                CornerRadius = new CornerRadius(11),
                Background = K.White(0.16),
                BorderBrush = K.White(0.1),
                BorderThickness = new Thickness(1),
                RenderTransform = highlightMove,
            };
            list.Children.Add(highlight);
            var stack = K.V(Gap);
            for (var i = 0; i < Pages.Length; i++)
            {
                var (id, text, glyph) = Pages[i];
                icons[i] = K.Icon(glyph, 16);
                icons[i].Width = 24;
                var hint = K.T("Ctrl+" + (i + 1), 11, FontWeights.SemiBold, 0.35);
                hint.Opacity = 0;
                hint.VerticalAlignment = VerticalAlignment.Center;
                var label = K.T(text, 15, FontWeights.SemiBold);
                label.VerticalAlignment = VerticalAlignment.Center;
                var row = K.Row(8, K.H(12, icons[i], label), hint);
                var item = new RadioButton { Content = row, GroupName = "pages", Height = ItemHeight, Style = (Style)FindResource("SidebarItem") };
                item.MouseEnter += (s, e) => hint.Opacity = 1;
                item.MouseLeave += (s, e) => hint.Opacity = 0;
                var page = id;
                item.Checked += (s, e) => { if (item.IsLoaded) m.Go(page); };
                items[i] = item;
                stack.Children.Add(item);
            }
            list.Children.Add(stack);
            SetRow(list, 1);
            Children.Add(list);

            SetRow(accountButtonHost, 3);
            Children.Add(accountButtonHost);
            accountsPopup = new Popup
            {
                PlacementTarget = accountButtonHost,
                Placement = PlacementMode.Right,
                HorizontalOffset = 12,
                StaysOpen = false,
                AllowsTransparency = true,
                PopupAnimation = PopupAnimation.Fade,
            };
            accountsPopup.Opened += (s, e) => { accountsPopup.Child = new AccountSwitcher(m, () => accountsPopup.IsOpen = false); m.RefreshAccounts(); };
            BuildAccountButton();

            Select(animated: false);
            m.PropertyChanged += OnModel;
            Unloaded += (s, e) => m.PropertyChanged -= OnModel;
            Loaded += (s, e) => { m.PropertyChanged -= OnModel; m.PropertyChanged += OnModel; };
        }

        void OnModel(object sender, PropertyChangedEventArgs e)
        {
            switch (e.PropertyName)
            {
                case nameof(LauncherModel.Page): Select(animated: true); break;
                case nameof(LauncherModel.Theme): Select(animated: false); break;
                case nameof(LauncherModel.CurrentAvatar):
                case nameof(LauncherModel.CurrentName):
                case nameof(LauncherModel.Player):
                    BuildAccountButton();
                    break;
            }
        }

        void Select(bool animated)
        {
            var index = Math.Max(0, Array.FindIndex(Pages, p => p.id == m.Page));
            for (var i = 0; i < items.Length; i++)
            {
                if (i == index && items[i].IsChecked != true) items[i].IsChecked = true;
                icons[i].Foreground = i == index ? K.Res("AccentTextBrush") : null;
                if (i != index) icons[i].ClearValue(TextBlock.ForegroundProperty);
            }
            var y = index * (ItemHeight + Gap);
            if (animated && Motion.Enabled)
                highlightMove.BeginAnimation(TranslateTransform.YProperty,
                    new DoubleAnimation(y, TimeSpan.FromMilliseconds(380)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.35 } });
            else
            {
                highlightMove.BeginAnimation(TranslateTransform.YProperty, null);
                highlightMove.Y = y;
            }
        }

        void BuildAccountButton()
        {
            var name = m.CurrentName;
            var text = K.V(1, K.T(name ?? "Accounts", 13.5, FontWeights.Bold), K.T("Switch account", 11, null, 0.55));
            text.VerticalAlignment = VerticalAlignment.Center;
            var chevron = K.Icon("\uE70E", 10, K.White(0.5));
            var content = new Border
            {
                Padding = new Thickness(8),
                CornerRadius = new CornerRadius(13),
                Background = K.White(0.05),
                Child = K.Row(10, K.H(10, K.Avatar(m.CurrentAvatar, 34, K.White(0.3)), text), chevron),
            };
            var button = K.Plain(content, () => accountsPopup.IsOpen = !accountsPopup.IsOpen,
                m.CurrentAccount != null ? $"Signed in as {m.CurrentAccount.Name} · switch accounts" : "Accounts");
            button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            button.MouseEnter += (s, e) => content.Background = K.White(0.1);
            button.MouseLeave += (s, e) => content.Background = K.White(0.05);
            accountButtonHost.Content = button;
        }
    }

    /// <summary>The popup behind the sidebar's account button: switch accounts in one click.</summary>
    sealed class AccountSwitcher : Border
    {
        public AccountSwitcher(LauncherModel m, Action close)
        {
            Width = 300;
            Padding = new Thickness(16);
            CornerRadius = new CornerRadius(16);
            Background = new SolidColorBrush(Color.FromArgb(0xF5, 0x16, 0x16, 0x20));
            BorderBrush = K.White(0.14);
            BorderThickness = new Thickness(1);
            TextElement.SetForeground(this, Brushes.White);
            TextElement.SetFontFamily(this, Application.Current.MainWindow?.FontFamily ?? new FontFamily("Segoe UI"));
            Child = new Live(m, new[] { nameof(LauncherModel.AccountList), nameof(LauncherModel.CurrentAccount), nameof(LauncherModel.AccountsWorking), nameof(LauncherModel.AccountsError), nameof(LauncherModel.RobloxRunning) }, () =>
            {
                var stack = K.V(12, K.Row(8, K.T("Accounts", 16, FontWeights.Black), m.AccountsWorking || m.Busy ? K.T("Working…", 11, null, 0.6) : null));
                var rows = K.V(4);
                foreach (var account in m.AccountList)
                {
                    var a = account;
                    rows.Children.Add(Row(m, a.Name, "@" + a.Username, m.Avatar(a.UserId), a.Active, () =>
                    {
                        if (a.Active || m.AccountsWorking) return;
                        if (m.RobloxRunning && !Ask.Confirm(Window.GetWindow(this), $"Switch to {a.Name}?", $"Roblox is open. It will close and reopen signed in as {a.Name}.", "Close Roblox and Switch")) return;
                        m.SwitchAccount(a);
                    }));
                }
                if (m.CurrentAccount != null && !m.CurrentIsSaved)
                    rows.Children.Add(Row(m, m.CurrentAccount.Name, "Not saved yet", m.Avatar(m.CurrentAccount.UserId), true, null));
                if (m.AccountList.Count == 0 && m.CurrentAccount == null)
                    rows.Children.Add(K.T("Roblox is signed out on this PC.", 12.5, null, 0.6));
                stack.Children.Add(rows);
                if (m.AccountsError != null) stack.Children.Add(K.T(m.AccountsError, 12, null, 1, wrap: true));
                stack.Children.Add(new Border { Height = 1, Background = K.White(0.1) });
                var primary = m.CurrentAccount != null && !m.CurrentIsSaved
                    ? K.Button(K.Label("\uE74E", "Save " + m.CurrentAccount.Name), m.SaveCurrentAccount, K.Size.Small)
                    : K.Button(K.Label("\uE8FA", "Add Account"), () => { close(); m.Go("launcher", "accounts"); }, K.Size.Small);
                stack.Children.Add(K.Row(8, primary, K.Button("Manage", () => { close(); m.Go("launcher", "accounts"); }, K.Size.Small, glass: true)));
                return stack;
            });
        }

        static UIElement Row(LauncherModel m, string name, string detail, string avatar, bool active, Action click)
        {
            var text = K.V(1, K.T(name, 13.5, FontWeights.Bold), K.T(detail, 11.5, null, 0.55));
            text.VerticalAlignment = VerticalAlignment.Center;
            var check = active ? K.Icon("\uE73E", 13, K.Res("AccentTextBrush")) : null;
            var content = new Border
            {
                Padding = new Thickness(8),
                CornerRadius = new CornerRadius(12),
                Background = Brushes.Transparent,
                Child = K.Row(10, K.H(10, K.Avatar(avatar, 36, active ? K.Res("AccentBrush") : K.White(0.3)), text), check),
            };
            var b = K.Plain(content, click, active ? "Signed in now" : $"Switch to {name}");
            b.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            if (!active)
            {
                b.MouseEnter += (s, e) => content.Background = K.White(0.08);
                b.MouseLeave += (s, e) => content.Background = Brushes.Transparent;
            }
            return b;
        }
    }

    // ----------------------------------------------------------------------

    /// <summary>The top-right capsule: state, Roblox version and an update button.</summary>
    sealed class StatusCapsule : Border
    {
        readonly LauncherModel m;
        readonly PulseDot dot = new PulseDot();
        readonly TextBlock label = K.T("", 12.5, FontWeights.Bold);
        readonly TextBlock version = K.T("", 12.5, FontWeights.SemiBold, 0.6);
        readonly Ellipse separator = new Ellipse { Width = 3, Height = 3, Fill = K.White(0.3), VerticalAlignment = VerticalAlignment.Center };
        readonly Button update;
        readonly RotateTransform spin = new RotateTransform();

        public StatusCapsule(LauncherModel model)
        {
            m = model;
            CornerRadius = new CornerRadius(999);
            Background = K.Black(0.38);
            BorderBrush = K.White(0.12);
            BorderThickness = new Thickness(1);
            Padding = new Thickness(13, 5, 6, 5);
            var icon = K.Icon("\uE72C", 11);
            icon.RenderTransform = spin;
            icon.RenderTransformOrigin = new Point(0.5, 0.5);
            var circle = new Border { Width = 22, Height = 22, CornerRadius = new CornerRadius(11), Background = K.White(0.1), Child = icon };
            update = K.Plain(circle, () =>
            {
                if (Motion.Enabled)
                    spin.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromMilliseconds(600)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.4 } });
                m.CheckForUpdates();
            }, "Check for Roblox updates");
            WindowChrome.SetIsHitTestVisibleInChrome(update, true);
            label.VerticalAlignment = version.VerticalAlignment = VerticalAlignment.Center;
            dot.VerticalAlignment = VerticalAlignment.Center;
            Child = K.H(9, dot, label, separator, version, update);
            Refresh();
            m.PropertyChanged += OnModel;
            Unloaded += (s, e) => m.PropertyChanged -= OnModel;
        }

        void OnModel(object sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(LauncherModel.State) || e.PropertyName == nameof(LauncherModel.ShortVersion) ||
                e.PropertyName == nameof(LauncherModel.Busy) || e.PropertyName == nameof(LauncherModel.RobloxRunning))
                Refresh();
        }

        void Refresh()
        {
            var state = m.State;
            dot.Update(States.Color(state), States.Pulses(state));
            label.Text = States.Label(state);
            var v = m.ShortVersion;
            version.Text = v == null ? "" : "Roblox " + v;
            version.Visibility = separator.Visibility = v == null ? Visibility.Collapsed : Visibility.Visible;
            update.IsEnabled = !m.Busy;
        }
    }

    /// <summary>The status dot, with a ring that ripples outward while pulsing.</summary>
    sealed class PulseDot : Grid
    {
        readonly Ellipse dot = new Ellipse { Width = 8, Height = 8 };
        readonly Ellipse ring = new Ellipse { Width = 8, Height = 8, Opacity = 0, RenderTransformOrigin = new Point(0.5, 0.5) };
        readonly ScaleTransform ringScale = new ScaleTransform();
        bool? pulsing;

        public PulseDot()
        {
            Width = Height = 8;
            ring.RenderTransform = ringScale;
            Children.Add(ring);
            Children.Add(dot);
        }

        public void Update(Color color, bool pulse)
        {
            dot.Fill = new SolidColorBrush(color);
            ring.Fill = new SolidColorBrush(Theme.WithAlpha(color, 0.55));
            pulse &= Motion.Enabled;
            if (pulse == pulsing) return;
            pulsing = pulse;
            ring.BeginAnimation(OpacityProperty, null);
            ringScale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
            ringScale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
            ring.Opacity = 0;
            if (!pulse) return;
            var duration = TimeSpan.FromSeconds(1.3);
            var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };
            ring.BeginAnimation(OpacityProperty, new DoubleAnimation(1, 0, duration) { RepeatBehavior = RepeatBehavior.Forever, EasingFunction = ease });
            ringScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1, 2.6, duration) { RepeatBehavior = RepeatBehavior.Forever, EasingFunction = ease });
            ringScale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, 2.6, duration) { RepeatBehavior = RepeatBehavior.Forever, EasingFunction = ease });
        }
    }
}

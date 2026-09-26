using System;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;

namespace AppleLabs
{
    sealed class PlayPage : Stack
    {
        public PlayPage(LauncherModel m)
        {
            Spacing = 30;
            RecentGame Hero() => m.ShowRecentGames ? m.RecentGames.FirstOrDefault() : null;

            Children.Add(K.AppearIn(new Live(m, new[] { nameof(LauncherModel.State), nameof(LauncherModel.Stage), nameof(LauncherModel.CurrentName), nameof(LauncherModel.CurrentAvatar), nameof(LauncherModel.ShortVersion), nameof(LauncherModel.NeedsRestart) },
                () => Greeting(m)), 0));
            Children.Add(K.AppearIn(new StageCard(m, Hero), 1));
            Children.Add(new Live(m, new[] { nameof(LauncherModel.ErrorMessage) },
                () => m.ErrorMessage == null ? null : K.ErrorBanner(m.ErrorMessage, () => m.ErrorMessage = null)));
            Children.Add(K.AppearIn(new Live(m, new[] { nameof(LauncherModel.RecentGames), nameof(LauncherModel.GamesRefreshing), nameof(LauncherModel.ShowRecentGames), nameof(LauncherModel.Busy) },
                () => m.ShowRecentGames ? JumpBackIn(m) : null), 2));
            Children.Add(K.AppearIn(new Live(m, new[] { nameof(LauncherModel.Loadout) }, () => Loadout(m)), 3));
        }

        static UIElement Greeting(LauncherModel m)
        {
            var hour = DateTime.Now.Hour;
            var salutation = hour >= 5 && hour < 12 ? "Good morning" : hour >= 12 && hour < 17 ? "Good afternoon" : hour >= 17 && hour < 22 ? "Good evening" : "Up late";
            string line;
            switch (m.State)
            {
                case LauncherState.Working: line = string.IsNullOrEmpty(m.Stage) ? "Getting Roblox ready…" : m.Stage; break;
                case LauncherState.Playing:
                    line = m.NeedsRestart ? "Roblox is running with your old settings. Restart it to use your changes." : "Roblox is running. Have fun out there!";
                    break;
                case LauncherState.NotInstalled: line = "Roblox isn't installed yet. It downloads when you press Play."; break;
                case LauncherState.UpdateReady: line = "A Roblox update is ready and installs when you press Play."; break;
                case LauncherState.Failed: line = "Something went wrong. The details are below."; break;
                case LauncherState.Checking: line = "Checking for the latest Roblox…"; break;
                default: line = $"Roblox {m.ShortVersion} is ready. Your loadout applies when the game starts."; break;
            }
            var name = m.CurrentName;
            var text = K.V(4, K.T(salutation + (name != null ? ", " + name : ""), 32, FontWeights.Black), K.T(line, 14, null, 0.68));
            text.VerticalAlignment = VerticalAlignment.Center;
            return name == null ? (UIElement)text : K.H(16, K.Avatar(m.CurrentAvatar, 58), text);
        }

        static UIElement JumpBackIn(LauncherModel m)
        {
            var games = m.RecentGames.Skip(1).ToList();
            var refresh = K.Button(K.Label("\uE72C", "Refresh"), m.RefreshGames, K.Size.Small, glass: true);
            refresh.IsEnabled = !m.GamesRefreshing;
            var header = K.Row(10, K.H(10, K.T("Jump back in", 20, FontWeights.Black), Baseline(K.T("From your Roblox history on this PC", 12, null, 0.5))), refresh);
            UIElement body;
            if (games.Count == 0)
            {
                body = K.Card(K.H(14, K.Icon("\uE7B8", 24, K.White(0.6)),
                    K.T(m.GamesRefreshing ? "Looking through your recent games…" : "Games you play show up here, ready to rejoin in one click.", 13.5, null, 0.7)),
                    20, new Thickness(18));
            }
            else
            {
                var row = K.H(18);
                foreach (var g in games) row.Children.Add(GameTile(m, g));
                body = new ScrollViewer
                {
                    Content = row,
                    HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                    VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
                    Padding = new Thickness(6, 10, 6, 12),
                    Margin = new Thickness(-6, 0, -6, 0),
                    Focusable = false,
                };
            }
            return K.V(12, header, body);
        }

        static FrameworkElement Baseline(FrameworkElement e)
        {
            e.VerticalAlignment = VerticalAlignment.Bottom;
            e.Margin = new Thickness(0, 0, 0, 3);
            return e;
        }

        static UIElement GameTile(LauncherModel m, RecentGame game)
        {
            var placeholder = new Border { Background = K.White(0.08), Child = K.Icon("\uE7B8", 34, K.White(0.3)) };
            var icon = K.WebImage(game.IconUrl, placeholder);
            icon.Width = icon.Height = 150;
            icon.Clip = new RectangleGeometry(new Rect(0, 0, 150, 150), 26, 26);
            var frame = new Border { Width = 150, Height = 150, CornerRadius = new CornerRadius(26), BorderBrush = K.White(0.12), BorderThickness = new Thickness(1) };
            var badgeScale = new ScaleTransform(0.3, 0.3);
            var badge = new Border
            {
                Width = 42, Height = 42, CornerRadius = new CornerRadius(21),
                Background = K.Res("AccentBrush"), BorderBrush = K.White(0.45), BorderThickness = new Thickness(1),
                Child = K.Icon("\uE768", 15, K.Res("OnAccentBrush")),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(10), Opacity = 0, RenderTransform = badgeScale, RenderTransformOrigin = new Point(0.5, 0.5),
            };
            var picture = new Grid { Width = 150, Height = 150, Children = { icon, frame, badge } };
            var name = K.T(game.DisplayName, 13.5, FontWeights.Bold, 1, wrap: true);
            name.Height = 38;
            name.TextTrimming = TextTrimming.CharacterEllipsis;
            var content = K.V(9, picture, name, K.T(game.LastPlayedText, 11.5, null, 0.55));
            content.Width = 150;
            var lift = new TranslateTransform();
            var grow = new ScaleTransform(1, 1);
            content.RenderTransformOrigin = new Point(0.5, 0.5);
            content.RenderTransform = new TransformGroup { Children = { grow, lift } };

            var button = K.Plain(content, () => m.Launch(game.LaunchLink), "Join " + game.DisplayName);
            button.IsEnabled = !m.Busy;
            void Hover(bool on)
            {
                if (!Motion.Enabled) { badge.Opacity = on ? 1 : 0; badgeScale.ScaleX = badgeScale.ScaleY = on ? 1 : 0.3; return; }
                var spring = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.5 };
                var time = TimeSpan.FromMilliseconds(300);
                grow.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(on ? 1.05 : 1, time) { EasingFunction = spring });
                grow.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(on ? 1.05 : 1, time) { EasingFunction = spring });
                lift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(on ? -6 : 0, time) { EasingFunction = spring });
                badge.BeginAnimation(OpacityProperty, new DoubleAnimation(on ? 1 : 0, TimeSpan.FromMilliseconds(150)));
                badgeScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(on ? 1 : 0.3, time) { EasingFunction = spring });
                badgeScale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(on ? 1 : 0.3, time) { EasingFunction = spring });
                frame.BorderBrush = K.White(on ? 0.55 : 0.12);
                frame.BorderThickness = new Thickness(on ? 2 : 1);
            }
            button.MouseEnter += (s, e) => Hover(true);
            button.MouseLeave += (s, e) => Hover(false);

            var menu = new ContextMenu();
            void Item(string header, Action action)
            {
                var item = new MenuItem { Header = header };
                item.Click += (s, e) => action();
                menu.Items.Add(item);
            }
            Item("Play", () => m.Launch(game.LaunchLink));
            Item("Open on Roblox.com", () => K.Open(game.WebUrl));
            Item("Copy Link", () => { try { Clipboard.SetText(game.WebUrl); } catch (Exception) { } });
            button.ContextMenu = menu;
            return button;
        }

        static UIElement Loadout(LauncherModel m)
        {
            var header = K.H(10, K.T("Your loadout", 20, FontWeights.Black), Baseline(K.T("Applied every time you play", 12, null, 0.5)));
            var chips = new Flow { Spacing = 10 };
            foreach (var item in m.Loadout) chips.Children.Add(LoadoutChip(m, item));
            return K.V(14, header, chips);
        }

        static UIElement LoadoutChip(LauncherModel m, LoadoutItem item)
        {
            var circle = new Border
            {
                Width = 28, Height = 28, CornerRadius = new CornerRadius(14),
                Background = item.Active ? K.Res("AccentBrush") : K.White(0.14),
                BorderBrush = K.White(item.Active ? 0.35 : 0.1), BorderThickness = new Thickness(1),
                Child = K.Icon(item.Glyph, 12, item.Active ? K.Res("OnAccentBrush") : Brushes.White),
            };
            var chevron = K.Icon("\uE76C", 9, K.White(0.7));
            chevron.Opacity = 0;
            var label = K.T(item.Text, 13, FontWeights.Bold, item.Active ? 1 : 0.72);
            label.VerticalAlignment = VerticalAlignment.Center;
            var capsule = new Border
            {
                Padding = new Thickness(5, 5, 13, 5),
                CornerRadius = new CornerRadius(999),
                Background = K.White(0.08),
                BorderBrush = K.White(0.1),
                BorderThickness = new Thickness(1),
                Child = K.H(8, circle, label, chevron),
            };
            var b = K.Plain(capsule, () => m.Go(item.Page, item.Tab));
            b.MouseEnter += (s, e) => { capsule.Background = K.White(0.15); capsule.BorderBrush = K.White(0.25); chevron.Opacity = 1; };
            b.MouseLeave += (s, e) => { capsule.Background = K.White(0.08); capsule.BorderBrush = K.White(0.1); chevron.Opacity = 0; };
            return b;
        }
    }

    /// <summary>
    /// The big card at the top: your last game's artwork with a Play button, or
    /// the Roblox logo when there's no history yet.
    /// </summary>
    sealed class StageCard : Grid
    {
        readonly LauncherModel m;
        readonly Func<RecentGame> hero;
        readonly TranslateTransform parallax = new TranslateTransform();
        readonly ConfettiBurst confetti = new ConfettiBurst();

        public StageCard(LauncherModel model, Func<RecentGame> hero)
        {
            m = model;
            this.hero = hero;
            Height = 340;
            var watched = new[] { nameof(LauncherModel.RecentGames), nameof(LauncherModel.ShowRecentGames), nameof(LauncherModel.Theme), nameof(LauncherModel.Installed) };
            Children.Add(new Live(m, watched, Backdrop));
            Children.Add(new Rectangle
            {
                IsHitTestVisible = false,
                Fill = new LinearGradientBrush(new GradientStopCollection
                {
                    new GradientStop(Color.FromArgb(224, 0, 0, 0), 0),
                    new GradientStop(Color.FromArgb(128, 0, 0, 0), 0.5),
                    new GradientStop(Colors.Transparent, 1),
                }, 0),
            });
            Children.Add(new Rectangle
            {
                IsHitTestVisible = false,
                Fill = new LinearGradientBrush(new GradientStopCollection
                {
                    new GradientStop(Colors.Transparent, 0.5),
                    new GradientStop(Color.FromArgb(128, 0, 0, 0), 1),
                }, 90),
            });
            var content = new Live(m, watched.Concat(new[] { nameof(LauncherModel.State), nameof(LauncherModel.Busy), nameof(LauncherModel.RobloxRunning), nameof(LauncherModel.NeedsRestart) }), Content);
            content.Margin = new Thickness(34, 30, 34, 30);
            content.VerticalAlignment = VerticalAlignment.Bottom;
            Children.Add(content);
            Children.Add(confetti);
            Children.Add(new Border
            {
                CornerRadius = new CornerRadius(30),
                BorderThickness = new Thickness(1),
                BorderBrush = new LinearGradientBrush(Color.FromArgb(71, 255, 255, 255), Color.FromArgb(13, 255, 255, 255), 90),
                IsHitTestVisible = false,
            });
            SizeChanged += (s, e) => Clip = new RectangleGeometry(new Rect(RenderSize), 30, 30);

            // The artwork leans away from the pointer.
            MouseMove += (s, e) =>
            {
                if (!Motion.Enabled || ActualWidth <= 0) return;
                var p = e.GetPosition(this);
                var x = -(p.X / ActualWidth - 0.5) * 20;
                var y = -(p.Y / ActualHeight - 0.5) * 14;
                if (Math.Abs(x - parallax.X) < 0.4 && Math.Abs(y - parallax.Y) < 0.4) return;
                parallax.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(x, TimeSpan.FromMilliseconds(250)));
                parallax.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(y, TimeSpan.FromMilliseconds(250)));
            };
            MouseLeave += (s, e) =>
            {
                var spring = new ElasticEase { EasingMode = EasingMode.EaseOut, Oscillations = 1, Springiness = 4 };
                parallax.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(600)) { EasingFunction = spring });
                parallax.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(600)) { EasingFunction = spring });
            };

            var lastCelebration = m.Celebrations;
            PropertyChangedEventHandler celebrate = (s, e) =>
            {
                if (e.PropertyName != nameof(LauncherModel.Celebrations) || m.Celebrations == lastCelebration) return;
                lastCelebration = m.Celebrations;
                confetti.Burst(m.Theme.Confetti);
            };
            Loaded += (s, e) => m.PropertyChanged += celebrate;
            Unloaded += (s, e) => m.PropertyChanged -= celebrate;
        }

        UIElement Backdrop()
        {
            var theme = m.Theme;
            var grid = new Grid();
            grid.Children.Add(new Rectangle { Fill = new LinearGradientBrush(Colors.Black, theme.HeroGlow, 0) });
            var game = hero();
            if (game?.ArtUrl != null)
            {
                var art = K.WebImage(game.ArtUrl, null);
                art.Margin = new Thickness(-14);
                art.RenderTransform = parallax;
                grid.Children.Add(art);
            }
            else
            {
                grid.Children.Add(new Rectangle
                {
                    Fill = new RadialGradientBrush(Theme.WithAlpha(theme.Accent, 0.5), Colors.Transparent)
                    {
                        Center = new Point(0.8, 0.5), GradientOrigin = new Point(0.8, 0.5), RadiusX = 0.35, RadiusY = 0.9,
                    },
                });
                var exe = m.Installed == null ? null : System.IO.Path.Combine(Roblox.VersionDir(m.Installed.Guid), Roblox.PlayerExe);
                var source = Images.ExeIcon(exe) ?? Images.Logo;
                var bob = new TranslateTransform();
                var icon = new Image
                {
                    Source = source, Width = 184, Height = 184,
                    HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, 78, 0),
                    RenderTransform = new TransformGroup { Children = { bob, parallax } },
                    CacheMode = new BitmapCache(),
                };
                RenderOptions.SetBitmapScalingMode(icon, BitmapScalingMode.HighQuality);
                if (Motion.Enabled)
                {
                    var float_ = new DoubleAnimation(-9, 9, TimeSpan.FromSeconds(2.8)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut } };
                    Timeline.SetDesiredFrameRate(float_, 60);
                    bob.BeginAnimation(TranslateTransform.YProperty, float_);
                }
                grid.Children.Add(icon);
            }
            return grid;
        }

        string FallbackTitle
        {
            get
            {
                switch (m.State)
                {
                    case LauncherState.Playing: return "Roblox is running";
                    case LauncherState.NotInstalled: return "Let's install Roblox";
                    case LauncherState.UpdateReady: return "Update ready";
                    default: return "Ready to play";
                }
            }
        }

        string PlayLabel => m.State == LauncherState.NotInstalled ? "Install & Play" : m.State == LauncherState.UpdateReady ? "Update & Play" : "Play";

        UIElement Content()
        {
            var game = hero();
            var stack = K.V(12);
            if (game != null)
            {
                var pill = new Border
                {
                    CornerRadius = new CornerRadius(999), Padding = new Thickness(12, 6, 12, 6),
                    Background = K.Black(0.4), BorderBrush = K.White(0.15), BorderThickness = new Thickness(1),
                    HorizontalAlignment = HorizontalAlignment.Left,
                    Child = K.H(8, K.T("LAST PLAYED", 11, FontWeights.Black, 0.85), new Ellipse { Width = 3, Height = 3, Fill = K.White(0.5), VerticalAlignment = VerticalAlignment.Center },
                        K.T(game.LastPlayedText, 12, FontWeights.SemiBold, 0.85)),
                };
                stack.Children.Add(pill);
            }
            else stack.Children.Add(StatusPill(m.State));

            var title = K.T(game?.DisplayName ?? FallbackTitle, 44, FontWeights.Black, 1, wrap: true);
            title.MaxWidth = 580;
            title.HorizontalAlignment = HorizontalAlignment.Left;
            title.MaxHeight = 120;
            title.TextTrimming = TextTrimming.CharacterEllipsis;
            title.Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 10, ShadowDepth = 3, Direction = 270, Opacity = 0.45 };
            stack.Children.Add(title);

            var meta = K.H(16);
            if (game?.PlayingText is string playing) meta.Children.Add(MetaItem("\uE716", playing));
            if (m.State == LauncherState.UpdateReady) meta.Children.Add(MetaItem("\uE896", "Update ready"));
            if (m.RobloxRunning && game != null) meta.Children.Add(MetaItem("\uE7FC", "Roblox is open"));
            if (meta.Children.Count > 0) stack.Children.Add(meta);

            var actions = Actions(game);
            if (actions is FrameworkElement fe)
            {
                fe.Margin = new Thickness(0, 8, 0, 0);
                fe.HorizontalAlignment = HorizontalAlignment.Left;
            }
            stack.Children.Add(actions);
            return stack;
        }

        static UIElement MetaItem(string glyph, string text) =>
            K.H(7, K.Icon(glyph, 13, K.White(0.8)), K.T(text, 13, FontWeights.SemiBold, 0.8));

        public static UIElement StatusPill(LauncherState state)
        {
            var dot = new PulseDot { VerticalAlignment = VerticalAlignment.Center };
            dot.Update(States.Color(state), States.Pulses(state));
            return new Border
            {
                CornerRadius = new CornerRadius(999), Padding = new Thickness(12, 6, 12, 6),
                Background = K.Black(0.35), BorderBrush = K.White(0.12), BorderThickness = new Thickness(1),
                HorizontalAlignment = HorizontalAlignment.Left,
                Child = K.H(8, dot, K.T(States.Label(state), 12.5, FontWeights.Bold, 0.92)),
            };
        }

        UIElement Actions(RecentGame game)
        {
            if (m.Busy) return K.AppearIn(new ProgressCapsule(m), 0);
            if (m.RobloxRunning && m.NeedsRestart)
            {
                // Roblox only reads settings when it starts.
                var apply = K.Button(K.Label("\uE72C", "Restart to Apply", 20), m.RestartRoblox, K.Size.Large, tip: "Close and reopen Roblox with your latest settings");
                apply.IsDefault = true;
                return apply;
            }
            if (m.RobloxRunning)
            {
                return K.H(14,
                    K.Button(K.Label("\uE8A7", "Open Roblox", 20), () => m.Launch(), K.Size.Large),
                    Bottom(K.Button(K.Label("\uE72C", "Restart"), m.RestartRoblox, glass: true, tip: "Close and reopen Roblox with your latest settings")));
            }
            var play = K.Button(K.Label("\uE768", PlayLabel, 20), () => m.Launch(game?.LaunchLink), K.Size.Large, tip: game == null ? null : "Join " + game.DisplayName);
            play.IsDefault = true;
            if (game == null) return play;
            return K.H(14, play, Bottom(K.Button("Just open Roblox", () => m.Launch(), glass: true)));
        }

        static FrameworkElement Bottom(FrameworkElement e)
        {
            e.VerticalAlignment = VerticalAlignment.Center;
            return e;
        }
    }

    /// <summary>Download progress with a ring, the current step and a cancel button.</summary>
    sealed class ProgressCapsule : Border
    {
        readonly LauncherModel m;
        readonly ProgressRing ring = new ProgressRing { Width = 36, Height = 36 };
        readonly GlowBar bar = new GlowBar { Width = 270 };
        readonly TextBlock stage = K.T("", 14, FontWeights.Bold);

        public ProgressCapsule(LauncherModel model)
        {
            m = model;
            CornerRadius = new CornerRadius(20);
            Padding = new Thickness(16, 12, 16, 12);
            Background = K.Black(0.5);
            BorderBrush = K.White(0.15);
            BorderThickness = new Thickness(1);
            HorizontalAlignment = HorizontalAlignment.Left;
            var cancel = K.IconButton("\uE711", m.Cancel, "Cancel");
            cancel.VerticalAlignment = VerticalAlignment.Center;
            Child = K.H(14, ring, K.V(8, stage, bar), cancel);
            Refresh();
            PropertyChangedEventHandler handler = (s, e) =>
            {
                if (e.PropertyName == nameof(LauncherModel.Stage) || e.PropertyName == nameof(LauncherModel.Progress)) Refresh();
            };
            Loaded += (s, e) => m.PropertyChanged += handler;
            Unloaded += (s, e) => m.PropertyChanged -= handler;
        }

        void Refresh()
        {
            stage.Text = string.IsNullOrEmpty(m.Stage) ? "Working…" : m.Stage;
            ring.Value = m.Progress;
            bar.Value = m.Progress;
        }
    }

    /// <summary>A circular progress indicator with the percentage in the middle.</summary>
    sealed class ProgressRing : Grid
    {
        readonly Path arc = new Path { StrokeThickness = 4, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
        readonly TextBlock percent = K.T("", 11, FontWeights.Black);
        readonly RotateTransform spin = new RotateTransform();
        double? value = -1;

        public ProgressRing()
        {
            Children.Add(new Ellipse { Stroke = K.White(0.14), StrokeThickness = 4 });
            arc.SetResourceReference(Shape.StrokeProperty, "AccentBrush");
            arc.RenderTransform = spin;
            arc.RenderTransformOrigin = new Point(0.5, 0.5);
            Children.Add(arc);
            percent.HorizontalAlignment = HorizontalAlignment.Center;
            percent.VerticalAlignment = VerticalAlignment.Center;
            Children.Add(percent);
            SizeChanged += (s, e) => Draw();
        }

        public double? Value
        {
            get => value;
            set
            {
                if (value == this.value) return;
                var wasIndeterminate = this.value == null;
                this.value = value;
                percent.Text = value.HasValue ? ((int)(value.Value * 100)).ToString() : "";
                if (value == null && !wasIndeterminate && Motion.Enabled)
                    spin.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(0.9)) { RepeatBehavior = RepeatBehavior.Forever });
                else if (value != null)
                {
                    spin.BeginAnimation(RotateTransform.AngleProperty, null);
                    spin.Angle = 0;
                }
                Draw();
            }
        }

        void Draw()
        {
            var size = Math.Min(ActualWidth, ActualHeight);
            if (size <= 0) return;
            var r = (size - 4) / 2;
            var fraction = value.HasValue ? Math.Max(0.02, Math.Min(value.Value, 0.999)) : 0.28;
            var center = new Point(size / 2, size / 2);
            var start = new Point(center.X, center.Y - r);
            var angle = fraction * 2 * Math.PI;
            var end = new Point(center.X + r * Math.Sin(angle), center.Y - r * Math.Cos(angle));
            var figure = new PathFigure { StartPoint = start, IsClosed = false };
            figure.Segments.Add(new ArcSegment(end, new Size(r, r), 0, fraction > 0.5, SweepDirection.Clockwise, true));
            arc.Data = new PathGeometry(new[] { figure });
        }
    }

    /// <summary>A glowing bar; with no value it sweeps back and forth.</summary>
    sealed class GlowBar : Grid
    {
        readonly Border fill = new Border { CornerRadius = new CornerRadius(4), HorizontalAlignment = HorizontalAlignment.Left };
        readonly TranslateTransform sweep = new TranslateTransform();
        double? value = -1;

        public GlowBar()
        {
            Height = 8;
            Children.Add(new Border { CornerRadius = new CornerRadius(4), Background = K.White(0.14) });
            Children.Add(fill);
            ClipToBounds = true;
            SizeChanged += (s, e) => Draw();
        }

        public double? Value
        {
            get => value;
            set
            {
                if (value == this.value) return;
                this.value = value;
                Draw();
            }
        }

        void Draw()
        {
            var width = ActualWidth;
            if (width <= 0) return;
            var accent = (Color)Application.Current.Resources["AccentColor"];
            if (value is double v)
            {
                sweep.BeginAnimation(TranslateTransform.XProperty, null);
                fill.RenderTransform = null;
                fill.Background = new LinearGradientBrush(new GradientStopCollection
                {
                    new GradientStop(Theme.WithAlpha(accent, 0.85), 0), new GradientStop(accent, 0.5), new GradientStop(Theme.WithAlpha(Colors.White, 0.95), 1),
                }, 0);
                var target = Math.Max(10, width * v);
                if (Motion.Enabled && fill.ActualWidth > 0)
                    fill.BeginAnimation(WidthProperty, new DoubleAnimation(target, TimeSpan.FromMilliseconds(250)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
                else
                {
                    fill.BeginAnimation(WidthProperty, null);
                    fill.Width = target;
                }
            }
            else
            {
                fill.BeginAnimation(WidthProperty, null);
                fill.Width = width * 0.35;
                fill.Background = new LinearGradientBrush(new GradientStopCollection
                {
                    new GradientStop(Theme.WithAlpha(accent, 0), 0), new GradientStop(accent, 0.5), new GradientStop(Theme.WithAlpha(accent, 0), 1),
                }, 0);
                fill.RenderTransform = sweep;
                if (Motion.Enabled)
                    sweep.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(0, width * 0.65, TimeSpan.FromSeconds(0.9))
                    { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut } });
            }
        }
    }

    /// <summary>A burst of little bricks and studs, fired after a launch.</summary>
    sealed class ConfettiBurst : Canvas
    {
        readonly Random random = new Random();

        public ConfettiBurst()
        {
            IsHitTestVisible = false;
            ClipToBounds = true;
        }

        public void Burst(Color[] colors)
        {
            if (!Motion.Enabled || ActualWidth <= 0) return;
            var origin = new Point(ActualWidth * 0.14, ActualHeight * 0.8);
            for (var i = 0; i < 70; i++)
            {
                var color = colors[random.Next(colors.Length)];
                Shape piece = random.Next(2) == 0
                    ? new Rectangle { Width = 16, Height = 11, RadiusX = 3, RadiusY = 3 }
                    : (Shape)new Ellipse { Width = 12, Height = 12 };
                piece.Fill = new SolidColorBrush(color);
                var scale = 0.5 + random.NextDouble() * 0.9;
                var move = new TranslateTransform(origin.X, origin.Y);
                var turn = new RotateTransform(random.Next(360));
                piece.RenderTransformOrigin = new Point(0.5, 0.5);
                piece.RenderTransform = new TransformGroup { Children = { new ScaleTransform(scale, scale), turn, move } };
                Children.Add(piece);

                // Thrown upward in a cone, then falling under gravity.
                var angle = -Math.PI / 2 + (random.NextDouble() - 0.5) * Math.PI / 1.5;
                var speed = 430 + (random.NextDouble() - 0.5) * 340;
                double vx = Math.Cos(angle) * speed, vy = Math.Sin(angle) * speed;
                var life = TimeSpan.FromSeconds(2.2 + random.NextDouble() * 0.6);
                var x = new DoubleAnimationUsingKeyFrames { Duration = life };
                var y = new DoubleAnimationUsingKeyFrames { Duration = life };
                for (var t = 0.0; t <= life.TotalSeconds + 0.001; t += 0.1)
                {
                    x.KeyFrames.Add(new LinearDoubleKeyFrame(origin.X + vx * t, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(t))));
                    y.KeyFrames.Add(new LinearDoubleKeyFrame(origin.Y + vy * t + 380 * t * t, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(t))));
                }
                var fade = new DoubleAnimation(1, 0, life) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn } };
                var shape = piece;
                fade.Completed += (s, e) => Children.Remove(shape);
                move.BeginAnimation(TranslateTransform.XProperty, x);
                move.BeginAnimation(TranslateTransform.YProperty, y);
                turn.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(turn.Angle, turn.Angle + (random.NextDouble() - 0.5) * 1400, life));
                piece.BeginAnimation(OpacityProperty, fade);
            }
        }
    }
}

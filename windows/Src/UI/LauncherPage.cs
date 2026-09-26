using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;

namespace AppleLabs
{
    sealed class LauncherPage : Stack
    {
        static readonly string[] Order = { "look", "accounts", "general", "help" };

        public LauncherPage(LauncherModel m)
        {
            Spacing = 24;
            var tabs = K.Tabs(new[]
            {
                ("Look", "\uE790", "look"),
                ("Accounts", "\uE716", "accounts"),
                ("General", "\uE8AB", "general"),
                ("Help", "\uE897", "help"),
            }, m.Settings.LauncherTab, t => m.SetTab("launcher", t));
            Children.Add(K.PageHeader("Launcher", "How this app looks and behaves.", tabs));
            Children.Add(new Live(m, new[] { nameof(LauncherModel.ErrorMessage) },
                () => m.ErrorMessage == null ? null : K.ErrorBanner(m.ErrorMessage, () => m.ErrorMessage = null)));
            Children.Add(new TabHost(m, Order, () => m.Settings.LauncherTab, tab =>
            {
                switch (tab)
                {
                    case "accounts": return Accounts(m);
                    case "general": return General(m);
                    case "help": return Help(m);
                    default: return Look(m);
                }
            }));
        }

        // ------------------------------------------------------------------
        // Look

        static UIElement Look(LauncherModel m)
        {
            var themes = new Live(m, new[] { nameof(LauncherModel.ThemeId), nameof(LauncherModel.CustomTheme), nameof(LauncherModel.BackgroundImage) }, () =>
            {
                var grid = new Tiles { Columns = 4, Spacing = 14 };
                var i = 0;
                foreach (var id in Theme.All)
                {
                    var themeId = id;
                    var theme = id == ThemeId.Custom ? m.CustomTheme : Theme.Preset(id);
                    var name = K.H(6, K.T(Theme.Name(id), 15, FontWeights.Black), id == ThemeId.Custom ? K.Icon("\uE9E9", 11, K.White(0.6)) : null);
                    var content = K.V(10, ThemePreview(theme, id == ThemeId.Custom ? m.BackgroundImage : null), name);
                    grid.Children.Add(Tile.Choice(content, m.ThemeId == id, () => m.ThemeId = themeId, ++i, 22, new Thickness(14)));
                }
                var stack = K.V(20, grid);
                if (m.ThemeId == ThemeId.Custom) stack.Children.Add(CustomEditor(m));
                return stack;
            });

            var fonts = new Live(m, new[] { nameof(LauncherModel.FontId) }, () =>
            {
                var grid = new Tiles { MinColumnWidth = 140, Spacing = 12 };
                var i = 10;
                foreach (var (id, name, family) in LauncherFonts.All)
                {
                    var fid = id;
                    var aa = K.T("Aa", 30, FontWeights.Black);
                    aa.FontFamily = new FontFamily(family);
                    var label = K.T(name, 13, FontWeights.SemiBold, 0.75);
                    label.FontFamily = new FontFamily(family);
                    grid.Children.Add(Tile.Choice(K.V(4, aa, label), m.FontId == id, () => m.FontId = fid, ++i, 22, new Thickness(16)));
                }
                return grid;
            });

            var motion = K.Group(
                K.SettingRow("Moving background", "Drifting colours and studs behind everything", K.Switch(m.AnimatedBackground, v => m.AnimatedBackground = v)),
                K.SettingRow("Studs", "The grid of Roblox-style studs in the background", K.Switch(m.ShowStuds, v => m.ShowStuds = v)),
                K.SettingRow("Celebrate launches", "A burst of confetti when Roblox starts", K.Switch(m.CelebrateLaunches, v => m.CelebrateLaunches = v)));

            return K.V(20,
                K.AppearIn(K.SectionLabel("Theme"), 1), themes,
                K.AppearIn(K.SectionLabel("Font"), 10), fonts,
                K.AppearIn(K.SectionLabel("Size"), 18), K.AppearIn(K.Group(ScaleControl(m)), 19),
                K.AppearIn(K.SectionLabel("Motion"), 20), K.AppearIn(motion, 21));
        }

        /// <summary>A little swatch of a theme for its tile.</summary>
        static UIElement ThemePreview(Theme theme, BitmapSource image)
        {
            var grid = new Grid { Height = 74, ClipToBounds = true };
            if (theme.IsGlass)
            {
                // A pretend desktop seen through frosted glass.
                grid.Children.Add(new Rectangle
                {
                    Fill = new LinearGradientBrush(new GradientStopCollection
                    {
                        new GradientStop(Color.FromRgb(250, 158, 77), 0), new GradientStop(Color.FromRgb(82, 133, 250), 0.5), new GradientStop(Color.FromRgb(158, 82, 217), 1),
                    }, 45),
                });
                grid.Children.Add(new Ellipse { Width = 30, Height = 30, Fill = K.White(0.8), Margin = new Thickness(-68, -24, 0, 0), Effect = new System.Windows.Media.Effects.BlurEffect { Radius = 10 } });
                grid.Children.Add(new Rectangle { Fill = K.White(0.18) });
                grid.Children.Add(new Rectangle { Fill = new LinearGradientBrush(Color.FromArgb(64, 255, 255, 255), Colors.Transparent, 90) });
            }
            else if (image != null)
            {
                grid.Children.Add(new Rectangle { Fill = Brushes.Black });
                grid.Children.Add(new Image { Source = image, Stretch = Stretch.UniformToFill });
                grid.Children.Add(new Rectangle { Fill = StylePage.StudPattern(14), Opacity = 0.3 });
            }
            else
            {
                grid.Children.Add(new Rectangle { Fill = new SolidColorBrush(theme.Base) });
                grid.Children.Add(new Rectangle
                {
                    Fill = new LinearGradientBrush(new GradientStopCollection
                    {
                        new GradientStop(theme.Glows[0], 0), new GradientStop(theme.Glows[1], 0.5), new GradientStop(theme.Glows[2], 1),
                    }, 45),
                    Opacity = 0.9,
                });
                grid.Children.Add(new Rectangle { Fill = StylePage.StudPattern(14), Opacity = 0.45 });
            }
            grid.Children.Add(new Ellipse
            {
                Width = 22, Height = 22,
                Fill = new SolidColorBrush(theme.Accent),
                Stroke = K.White(0.75), StrokeThickness = 2,
            });
            grid.Children.Add(new Border { CornerRadius = new CornerRadius(13), BorderBrush = K.White(0.12), BorderThickness = new Thickness(1) });
            grid.SizeChanged += (s, e) => grid.Clip = new RectangleGeometry(new Rect(grid.RenderSize), 13, 13);
            return grid;
        }

        static UIElement CustomEditor(LauncherModel m)
        {
            var theme = m.CustomTheme;
            Theme Edit(Action<Theme> change)
            {
                var t = m.CustomTheme.Copy();
                change(t);
                return t;
            }
            UIElement Swatch(string title, Color color, Action<Color> set)
            {
                var chip = new Border
                {
                    Width = 44, Height = 26, CornerRadius = new CornerRadius(8),
                    Background = new SolidColorBrush(color), BorderBrush = K.White(0.4), BorderThickness = new Thickness(1),
                    HorizontalAlignment = HorizontalAlignment.Center,
                };
                var pick = K.Plain(chip, () => { if (Files.PickColor(color) is Color c) set(c); }, "Pick a colour for " + title);
                var hex = K.T(Theme.Hex(color), 10, null, 0.45);
                hex.FontFamily = new FontFamily("Cascadia Mono, Consolas");
                var column = K.V(7, pick, Center(K.T(title, 11.5, FontWeights.SemiBold, 0.7)), Center(hex));
                return new Border { Padding = new Thickness(0, 10, 0, 10), CornerRadius = new CornerRadius(12), Background = K.Black(0.2), Child = column, Margin = new Thickness(5, 0, 5, 0) };
            }
            var swatches = new UniformGrid { Columns = 5, Margin = new Thickness(-5, 0, -5, 0) };
            swatches.Children.Add(Swatch("Accent", theme.Accent, c => m.CustomTheme = Edit(t => { t.Accent = c; t.HeroGlow = Theme.Mix(c, Colors.Black, 0.55); })));
            swatches.Children.Add(Swatch("Glow 1", theme.Glows[0], c => m.CustomTheme = Edit(t => t.Glows[0] = c)));
            swatches.Children.Add(Swatch("Glow 2", theme.Glows[1], c => m.CustomTheme = Edit(t => t.Glows[1] = c)));
            swatches.Children.Add(Swatch("Glow 3", theme.Glows[2], c => m.CustomTheme = Edit(t => t.Glows[2] = c)));
            swatches.Children.Add(Swatch("Background", theme.Base, c => m.CustomTheme = Edit(t => t.Base = c)));

            var startFrom = new ContextMenu();
            foreach (var id in Theme.All.Where(t => t != ThemeId.Custom))
            {
                var item = new MenuItem { Header = Theme.Name(id) };
                var from = id;
                item.Click += (s, e) =>
                {
                    var t = Theme.Preset(from);
                    t.Id = ThemeId.Custom;
                    if (t.IsGlass || t.Base.A == 0) t.Base = Color.FromRgb(13, 13, 13);
                    m.CustomTheme = t;
                };
                startFrom.Items.Add(item);
            }
            var start = K.Button(K.Label("\uE8C8", "Start From"), null, K.Size.Small, glass: true);
            start.ContextMenu = startFrom;
            start.Click += (s, e) => { startFrom.PlacementTarget = start; startFrom.Placement = PlacementMode.Bottom; startFrom.IsOpen = true; };
            var surprise = K.Button(K.Label("\uE8B1", "Surprise Me"), () => m.CustomTheme = Theme.Surprise(), K.Size.Small);

            var header = K.Row(10, K.V(3, K.T("Your colours", 16, FontWeights.Black), K.T("Click a swatch to pick any colour.", 12, null, 0.6)), start, surprise);
            return K.AppearIn(K.Card(K.V(16, header, swatches, BackgroundPicker(m)), 20, new Thickness(18), highlighted: true), 9);
        }

        static FrameworkElement Center(FrameworkElement e)
        {
            e.HorizontalAlignment = HorizontalAlignment.Center;
            return e;
        }

        /// <summary>Picks a picture to show behind the launcher, with dim and blur controls.</summary>
        static UIElement BackgroundPicker(LauncherModel m)
        {
            var image = m.BackgroundImage;
            var thumb = new Grid { Width = 76, Height = 48, Background = K.Black(0.3) };
            if (image != null)
            {
                thumb.Children.Add(new Image { Source = image, Stretch = Stretch.UniformToFill });
                thumb.Children.Add(new Rectangle { Fill = new SolidColorBrush(Color.FromArgb((byte)(m.BackgroundDim * 255), 0, 0, 0)) });
            }
            else thumb.Children.Add(K.Icon("\uE91B", 17, K.White(0.5)));
            thumb.Clip = new RectangleGeometry(new Rect(0, 0, 76, 48), 10, 10);
            var framed = new Grid { Children = { thumb, new Border { CornerRadius = new CornerRadius(10), BorderBrush = K.White(0.15), BorderThickness = new Thickness(1) } } };

            var text = K.V(3, K.T("Background picture", 14, FontWeights.SemiBold),
                K.T(image == null ? "Show any picture behind the launcher." : "Shown behind everything while Custom is on.", 12, null, 0.55, wrap: true));
            text.VerticalAlignment = VerticalAlignment.Center;

            var trailing = new List<UIElement>();
            if (image != null)
            {
                var dim = new Slider { Minimum = 0, Maximum = 0.8, Value = m.BackgroundDim, Width = 90, Style = (Style)Application.Current.FindResource("AccentSlider"), VerticalAlignment = VerticalAlignment.Center };
                dim.ValueChanged += (s, e) => m.BackgroundDim = dim.Value;
                trailing.Add(K.H(8, Mid(K.T("Dim", 12, FontWeights.SemiBold, 0.7)), dim));
                trailing.Add(K.H(8, Mid(K.T("Blur", 12, FontWeights.SemiBold, 0.7)), K.Switch(m.BackgroundBlur, v => m.BackgroundBlur = v)));
            }
            trailing.Add(K.Button(image == null ? "Choose…" : "Change…", () =>
            {
                var file = Files.Open("Choose a picture for the launcher's background", "Pictures|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.webp");
                if (file != null) m.SetBackgroundImage(file);
            }, K.Size.Small));
            if (image != null) trailing.Add(K.IconButton("\uE74D", () => m.SetBackgroundImage(null), "Remove the picture"));
            foreach (var t in trailing.OfType<FrameworkElement>()) t.VerticalAlignment = VerticalAlignment.Center;

            var row = K.Row(14, K.H(14, framed, text), trailing.ToArray());
            return new Border { Padding = new Thickness(12), CornerRadius = new CornerRadius(14), Background = K.Black(0.2), Child = row };
        }

        static FrameworkElement Mid(FrameworkElement e)
        {
            e.VerticalAlignment = VerticalAlignment.Center;
            return e;
        }

        /// <summary>Zooms the whole launcher. The new size applies when you let go of the slider.</summary>
        static UIElement ScaleControl(LauncherModel m) => new Live(m, new[] { nameof(LauncherModel.UiScale) }, () =>
        {
            var percent = K.T($"{Math.Round(m.UiScale * 100)}%", 13, FontWeights.Bold);
            percent.Width = 46;
            percent.TextAlignment = TextAlignment.Right;
            percent.VerticalAlignment = VerticalAlignment.Center;
            var slider = new Slider
            {
                Minimum = 0.8, Maximum = 1.3, Value = m.UiScale, Width = 150,
                TickFrequency = 0.05, IsSnapToTickEnabled = true,
                Style = (Style)Application.Current.FindResource("AccentSlider"),
                VerticalAlignment = VerticalAlignment.Center,
            };
            slider.ValueChanged += (s, e) => percent.Text = $"{Math.Round(slider.Value * 100)}%";
            slider.PreviewMouseUp += (s, e) => m.UiScale = slider.Value;
            slider.LostMouseCapture += (s, e) => m.UiScale = slider.Value;
            var minus = K.IconButton("\uE738", () => m.Zoom(-0.05), "Smaller");
            minus.IsEnabled = m.UiScale > 0.8 + 0.001;
            var plus = K.IconButton("\uE710", () => m.Zoom(0.05), "Bigger");
            plus.IsEnabled = m.UiScale < 1.3 - 0.001;
            var reset = K.Button("Reset", () => m.UiScale = 1, K.Size.Small, glass: true);
            reset.IsEnabled = Math.Abs(m.UiScale - 1) > 0.001;
            return K.SettingRow("Interface size", "Zoom the whole launcher. Ctrl + and Ctrl − work too.", K.H(10, minus, slider, plus, percent, reset));
        });

        // ------------------------------------------------------------------
        // Accounts

        static UIElement Accounts(LauncherModel m)
        {
            m.RefreshAccounts();
            var intro = K.Card(K.H(16, K.IconBadge("\uE716", 50), K.V(4,
                K.T("Switch Roblox accounts in one click", 16, FontWeights.Black),
                K.T("Each saved account is a copy of the Roblox app's own sign-in, kept only on this PC and encrypted for your Windows account. The launcher never sees your password, and removing an account here doesn't sign it out anywhere.", 12.5, null, 0.65, wrap: true))),
                20, new Thickness(18));
            var cards = new Live(m, new[] { nameof(LauncherModel.AccountList), nameof(LauncherModel.CurrentAccount), nameof(LauncherModel.AccountsWorking), nameof(LauncherModel.AccountsError), nameof(LauncherModel.RobloxRunning), nameof(LauncherModel.Busy) }, () =>
            {
                var stack = K.V(14);
                if (m.AccountsError != null) stack.Children.Add(K.ErrorBanner(m.AccountsError, () => m.AccountsError = null));
                var grid = new Tiles { MinColumnWidth = 260, Spacing = 14 };
                var i = 1;
                foreach (var account in m.AccountList) grid.Children.Add(K.AppearIn(AccountCard(m, account), ++i));
                if (m.CurrentAccount != null && !m.CurrentIsSaved)
                {
                    var save = K.Button("Save", m.SaveCurrentAccount, K.Size.Small);
                    save.IsEnabled = !m.AccountsWorking;
                    grid.Children.Add(K.Card(K.Row(14, K.H(14, K.Avatar(m.Avatar(m.CurrentAccount.UserId), 54, K.White(0.3)),
                        Mid(K.V(3, K.T(m.CurrentAccount.Name, 16, FontWeights.Black), K.T("Signed in now · not saved", 12, null, 0.6)))), save), 20, new Thickness(16)));
                }
                var plus = K.Icon("\uE710", 20, K.White(0.8));
                var ring = new Ellipse { Width = 54, Height = 54, Stroke = K.White(0.4), StrokeThickness = 2, StrokeDashArray = new DoubleCollection { 2.5, 2 } };
                var add = Tile.Choice(K.H(14, new Grid { Children = { ring, plus } },
                    Mid(K.V(3, K.T("Add account", 16, FontWeights.Black), K.T("Sign in to another Roblox account", 12, null, 0.6)))),
                    false, () =>
                    {
                        if (Ask.Confirm(Window.GetWindow(stack), "Add another account?",
                            "Your current account is saved first. Roblox then opens signed out so you can sign in to another account; it's saved automatically when you close Roblox.",
                            "Sign Out and Open Roblox"))
                            m.AddAccount();
                    }, 0, 20, new Thickness(16));
                add.IsEnabled = !m.AccountsWorking && !m.Busy;
                grid.Children.Add(add);
                stack.Children.Add(grid);
                return stack;
            });
            return K.V(18, K.AppearIn(intro, 1), cards,
                K.T("Website Play buttons join with whichever account is signed in on roblox.com in your browser.", 12, null, 0.5, wrap: true));
        }

        static UIElement AccountCard(LauncherModel m, RobloxAccount account)
        {
            var lines = K.V(3, K.T(account.Name, 16, FontWeights.Black), K.T("@" + account.Username, 12, null, 0.6));
            if (account.Active)
            {
                var signedIn = K.H(5, K.Icon("\uE73E", 11, K.Res("AccentTextBrush")), K.T("Signed in", 11.5, FontWeights.Bold));
                ((TextBlock)signedIn.Children[1]).Foreground = K.Res("AccentTextBrush");
                lines.Children.Add(signedIn);
            }
            lines.VerticalAlignment = VerticalAlignment.Center;
            var buttons = K.V(8);
            buttons.HorizontalAlignment = HorizontalAlignment.Right;
            if (!account.Active)
            {
                var switchButton = K.Button("Switch", () =>
                {
                    if (m.RobloxRunning && !Ask.Confirm(Application.Current.MainWindow, $"Switch to {account.Name}?",
                        $"Roblox is open. It will close and reopen signed in as {account.Name}.", "Close Roblox and Switch")) return;
                    m.SwitchAccount(account);
                }, K.Size.Small);
                switchButton.IsEnabled = !m.AccountsWorking && !m.Busy;
                buttons.Children.Add(switchButton);
            }
            var remove = K.IconButton("\uE74D", () =>
            {
                if (Ask.Confirm(Application.Current.MainWindow, $"Remove {account.Name}?",
                    "The launcher forgets this account's saved sign-in. It stays signed in wherever else you use it.", "Remove", destructive: true))
                    m.RemoveAccount(account);
            }, $"Remove {account.Name} from the launcher");
            remove.HorizontalAlignment = HorizontalAlignment.Right;
            buttons.Children.Add(remove);
            return K.Card(K.Row(14, K.H(14, K.Avatar(m.Avatar(account.UserId), 54, account.Active ? K.Res("AccentBrush") : K.White(0.3)), lines), buttons),
                20, new Thickness(16), highlighted: account.Active);
        }

        // ------------------------------------------------------------------
        // General

        static UIElement General(LauncherModel m)
        {
            var channel = new TextBox
            {
                Style = (Style)Application.Current.FindResource("Field"),
                Text = m.Channel,
                Width = 140,
                TextAlignment = TextAlignment.Right,
                FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                FontWeight = FontWeights.SemiBold,
                Tag = "LIVE",
            };
            channel.KeyDown += (s, e) => { if (e.Key == Key.Enter) m.Channel = channel.Text; };
            channel.LostKeyboardFocus += (s, e) => m.Channel = channel.Text;

            var behaviour = K.Group(
                K.SettingRow("Close when Roblox starts", "Off: the launcher stays open while you play", K.Switch(m.CloseOnLaunch, v => m.CloseOnLaunch = v)),
                K.SettingRow("Handle website links", "Play buttons on roblox.com go through the launcher, so updates, mods and settings always apply",
                    K.Switch(m.IsLinkHandler, m.SetLinkHandler)),
                K.SettingRow("Show recently played games", "Reads Roblox's logs on this PC and fetches names, pictures and player counts from Roblox",
                    K.Switch(m.ShowRecentGames, v => m.ShowRecentGames = v)));

            var roblox = new Live(m, new[] { nameof(LauncherModel.Installed), nameof(LauncherModel.Busy), nameof(LauncherModel.Progress), nameof(LauncherModel.RobloxRunning) }, () =>
            {
                var reinstall = K.Button(K.Label("\uE896", "Reinstall"), m.Reinstall, K.Size.Small, glass: true);
                reinstall.IsEnabled = !m.Busy;
                var rows = new List<UIElement>
                {
                    K.SettingRow("Channel", "LIVE for everyone; others usually need an account with access", channel),
                    K.SettingRow("Install location", Roblox.InstalledDir ?? Paths.Versions,
                        K.Button(K.Label("\uE8B7", "Show"), () => K.Open(Roblox.InstalledDir ?? Paths.Home), K.Size.Small, glass: true)),
                    K.SettingRow("Reinstall Roblox", "Downloads a fresh copy. Needed to switch channel right away", reinstall),
                };
                if (m.Busy)
                {
                    var bar = new GlowBar { Value = m.Progress, Margin = new Thickness(18, 0, 18, 14) };
                    rows.Add(bar);
                }
                return K.Group(rows.ToArray());
            });

            var links = K.H(10,
                K.Button(K.Label("\uE8B7", "Data Folder"), () => K.Open(Paths.Home), K.Size.Small, glass: true),
                K.Button(K.Label("\uE8A5", "Log"), () => K.Open(Paths.LogFile), K.Size.Small, glass: true),
                K.Button(K.Label("\uE74D", "Uninstall…"), () => Setup.UninstallWithQuestions(Application.Current.MainWindow), K.Size.Small, glass: true));

            return K.V(20,
                K.AppearIn(behaviour, 1),
                K.AppearIn(K.SectionLabel("Roblox", m.Installed == null ? "Not installed" : "Version " + m.Installed.Display), 2),
                K.AppearIn(roblox, 3),
                K.AppearIn(links, 4));
        }

        // ------------------------------------------------------------------
        // Help

        static readonly (string q, string a)[] Faqs =
        {
            ("How do I join a game from the website?",
             "Keep Handle website links on in General, then press Play on roblox.com. The launcher updates Roblox, applies your loadout, then joins the game."),
            ("I changed a setting but nothing happened.",
             "Changes load when Roblox starts. If Roblox is open, use Restart. Some FastFlags do nothing because Roblox only honours flags on its allowlist."),
            ("Where do my recent games come from?",
             "From Roblox's own log files on this PC. Game names, pictures and player counts come from Roblox's public web APIs. Turn it off in General to stop both."),
            ("How does account switching work?",
             "Saving an account keeps a copy of the Roblox app's own sign-in on this PC, still encrypted for your Windows account. Switching swaps it in while Roblox is closed. The launcher never sees your password; remove an account here to forget it."),
            ("Do mods survive Roblox updates?",
             "Yes. Updates install into a fresh folder, and the launcher puts your mods and FastFlags back before the game starts."),
            ("Windows SmartScreen warned me about Apple Labs.",
             "The launcher isn't signed with a paid certificate, so Windows doesn't recognise it yet. Choose More info, then Run anyway. It's built from the code on GitHub."),
            ("How do I uninstall everything?",
             "Use Uninstall in General, or Apple Labs in Windows Settings › Apps. It removes the launcher and the copy of Roblox it installed, and can keep or remove your settings."),
        };

        static UIElement Help(LauncherModel m)
        {
            var stack = K.V(10);
            var i = 0;
            foreach (var (q, a) in Faqs) stack.Children.Add(K.AppearIn(FaqRow(q, a), ++i));
            var logo = new Image { Source = Images.Logo, Width = 56, Height = 56 };
            RenderOptions.SetBitmapScalingMode(logo, BitmapScalingMode.HighQuality);
            var about = K.Card(K.Row(10,
                K.H(16, logo, Mid(K.V(4, K.T("Apple Labs " + App.Version, 17, FontWeights.Black),
                    K.T("Inspired by Bloxstrap and Fishstrap. Not affiliated with Roblox Corporation.", 12, null, 0.55, wrap: true)))),
                K.Button(K.Label("\uE8A5", "Log"), () => K.Open(Paths.LogFile), K.Size.Small, glass: true),
                K.Button(K.Label("\uE783", "Report a Problem"), () => K.Open("https://github.com/kirosthepuppy/apple-labs/issues"), K.Size.Small)),
                20, new Thickness(18));
            return K.V(18, stack, K.AppearIn(about, 8));
        }

        static UIElement FaqRow(string question, string answer)
        {
            var chevron = K.Icon("\uE70D", 12);
            var turn = new RotateTransform();
            chevron.RenderTransform = turn;
            chevron.RenderTransformOrigin = new Point(0.5, 0.5);
            var body = K.T(answer, 13, null, 0.72, wrap: true);
            body.Visibility = Visibility.Collapsed;
            body.Margin = new Thickness(0, 10, 0, 0);
            var header = K.Row(10, K.T(question, 14.5, FontWeights.Bold), chevron);
            var card = K.Card(K.V(0, header, body), 16, new Thickness(16));
            var open = false;
            var button = K.Plain(card, () =>
            {
                open = !open;
                body.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
                card.BorderBrush = open ? K.White(0.25) : K.Res("GlassStrokeBrush");
                if (Motion.Enabled)
                {
                    turn.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(open ? 180 : 0, TimeSpan.FromMilliseconds(300)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.4 } });
                    if (open) body.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(200)));
                }
                else turn.Angle = open ? 180 : 0;
            });
            button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            return button;
        }
    }
}

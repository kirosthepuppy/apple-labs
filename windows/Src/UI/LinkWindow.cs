using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shell;

namespace AppleLabs
{
    /// <summary>The compact window shown when a roblox:// link opens the launcher.</summary>
    sealed class LinkWindow : Window
    {
        readonly LauncherModel m;
        readonly Backdrop backdrop = new Backdrop();

        public LinkWindow(LauncherModel model)
        {
            m = model;
            Title = "Apple Labs";
            Width = 460;
            SizeToContent = SizeToContent.Height;
            ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = new SolidColorBrush(Color.FromRgb(8, 8, 12));
            Foreground = Brushes.White;
            FontFamily = LauncherFonts.Family(m.FontId);
            UseLayoutRounding = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Ideal);
            WindowChrome.SetWindowChrome(this, new WindowChrome { CaptionHeight = 30, GlassFrameThickness = new Thickness(0), ResizeBorderThickness = new Thickness(0), UseAeroCaptionButtons = false });

            var body = new Live(m, new[]
            {
                nameof(LauncherModel.ErrorMessage), nameof(LauncherModel.Stage), nameof(LauncherModel.LinkGame), nameof(LauncherModel.Busy),
            }, Body);
            body.Margin = new Thickness(22, 30, 22, 22);
            Content = new Grid { Children = { backdrop, new Border { Background = K.Black(0.22) }, body } };
            SourceInitialized += (s, e) =>
            {
                var theme = m.Theme;
                ThemeManager.Apply(theme);
                var glass = Dwm.SetGlass(this, theme.IsGlass && m.BackgroundImage == null);
                if (glass) Background = Brushes.Transparent;
                backdrop.Update(theme, m.AnimatedBackground, m.ShowStuds, glass, m.BackgroundImage, m.BackgroundDim);
            };
        }

        UIElement Body()
        {
            var title = m.ErrorMessage != null ? "Couldn't start Roblox" : m.LinkGame != null ? "Joining " + m.LinkGame.DisplayName : "Joining game";
            FrameworkElement icon;
            if (m.LinkGame?.IconUrl != null)
            {
                var image = K.WebImage(m.LinkGame.IconUrl, new Border { Background = K.White(0.1) });
                image.Width = image.Height = 64;
                image.Clip = new RectangleGeometry(new Rect(0, 0, 64, 64), 16, 16);
                icon = new Grid { Children = { image, new Border { CornerRadius = new CornerRadius(16), BorderBrush = K.White(0.25), BorderThickness = new Thickness(1) } } };
            }
            else
            {
                var exe = m.Installed == null ? null : System.IO.Path.Combine(Roblox.VersionDir(m.Installed.Guid), Roblox.PlayerExe);
                var image = new Image { Source = Images.ExeIcon(exe) ?? Images.Logo, Width = 64, Height = 64 };
                RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
                if (Motion.Enabled)
                {
                    var bob = new TranslateTransform();
                    image.RenderTransform = bob;
                    bob.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-3, 3, TimeSpan.FromSeconds(1.4))
                    { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut } });
                }
                icon = image;
            }
            var heading = K.V(4, K.T(title, 20, FontWeights.Black), K.T(m.ErrorMessage == null ? m.Stage : "See the details below.", 13, null, 0.7));
            heading.VerticalAlignment = VerticalAlignment.Center;
            var stack = K.V(16, K.H(16, icon, heading));
            if (m.ErrorMessage != null)
            {
                stack.Children.Add(K.ErrorBanner(m.ErrorMessage));
                var close = K.Button("Close", () => Application.Current.Shutdown(), K.Size.Small);
                close.IsDefault = true;
                close.HorizontalAlignment = HorizontalAlignment.Right;
                stack.Children.Add(close);
            }
            else
            {
                var bar = new GlowBar { Value = m.Progress };
                PropertyChangedEventHandler handler = (s, e) => { if (e.PropertyName == nameof(LauncherModel.Progress)) bar.Value = m.Progress; };
                bar.Loaded += (s, e) => m.PropertyChanged += handler;
                bar.Unloaded += (s, e) => m.PropertyChanged -= handler;
                stack.Children.Add(bar);
                var cancel = K.Button("Cancel", () => { m.Cancel(); Application.Current.Shutdown(); }, K.Size.Small, glass: true);
                cancel.IsCancel = true;
                stack.Children.Add(K.Row(10, null, cancel));
            }
            return stack;
        }
    }
}

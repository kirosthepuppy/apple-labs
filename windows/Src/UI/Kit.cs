using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace AppleLabs
{
    /// <summary>Attached properties the button and field templates read.</summary>
    public static class Chrome
    {
        public static readonly DependencyProperty CornerProperty = DependencyProperty.RegisterAttached(
            "Corner", typeof(CornerRadius), typeof(Chrome), new PropertyMetadata(new CornerRadius(12)));
        public static CornerRadius GetCorner(DependencyObject o) => (CornerRadius)o.GetValue(CornerProperty);
        public static void SetCorner(DependencyObject o, CornerRadius v) => o.SetValue(CornerProperty, v);

        public static readonly DependencyProperty LipSpaceProperty = DependencyProperty.RegisterAttached(
            "LipSpace", typeof(Thickness), typeof(Chrome), new PropertyMetadata(new Thickness(0, 0, 0, 4)));
        public static Thickness GetLipSpace(DependencyObject o) => (Thickness)o.GetValue(LipSpaceProperty);
        public static void SetLipSpace(DependencyObject o, Thickness v) => o.SetValue(LipSpaceProperty, v);

        public static readonly DependencyProperty LipOffsetProperty = DependencyProperty.RegisterAttached(
            "LipOffset", typeof(Thickness), typeof(Chrome), new PropertyMetadata(new Thickness(0, 4, 0, -4)));
        public static Thickness GetLipOffset(DependencyObject o) => (Thickness)o.GetValue(LipOffsetProperty);
        public static void SetLipOffset(DependencyObject o, Thickness v) => o.SetValue(LipOffsetProperty, v);

        public static readonly DependencyProperty FaceProperty = DependencyProperty.RegisterAttached(
            "Face", typeof(Brush), typeof(Chrome), new PropertyMetadata(Brushes.Gray));
        public static Brush GetFace(DependencyObject o) => (Brush)o.GetValue(FaceProperty);
        public static void SetFace(DependencyObject o, Brush v) => o.SetValue(FaceProperty, v);

        public static readonly DependencyProperty LipBrushProperty = DependencyProperty.RegisterAttached(
            "LipBrush", typeof(Brush), typeof(Chrome), new PropertyMetadata(Brushes.Black));
        public static Brush GetLipBrush(DependencyObject o) => (Brush)o.GetValue(LipBrushProperty);
        public static void SetLipBrush(DependencyObject o, Brush v) => o.SetValue(LipBrushProperty, v);

        public static readonly DependencyProperty InkProperty = DependencyProperty.RegisterAttached(
            "Ink", typeof(Brush), typeof(Chrome), new PropertyMetadata(Brushes.White));
        public static Brush GetInk(DependencyObject o) => (Brush)o.GetValue(InkProperty);
        public static void SetInk(DependencyObject o, Brush v) => o.SetValue(InkProperty, v);
    }

    /// <summary>A StackPanel with a gap between children.</summary>
    class Stack : Panel
    {
        public Orientation Orientation = Orientation.Vertical;
        public double Spacing;

        protected override Size MeasureOverride(Size available)
        {
            double main = 0, cross = 0;
            var visible = 0;
            var vertical = Orientation == Orientation.Vertical;
            // In a row, each child gets the width left after the ones before it, so
            // text after an icon wraps inside the row instead of running past it.
            var remaining = available.Width;
            foreach (UIElement child in InternalChildren)
            {
                var childAvailable = vertical
                    ? new Size(available.Width, double.PositiveInfinity)
                    : new Size(double.IsInfinity(remaining) ? double.PositiveInfinity : Math.Max(0, remaining), available.Height);
                child.Measure(childAvailable);
                if (child.Visibility == Visibility.Collapsed) continue;
                visible++;
                var d = child.DesiredSize;
                main += vertical ? d.Height : d.Width;
                cross = Math.Max(cross, vertical ? d.Width : d.Height);
                if (!vertical) remaining -= d.Width + Spacing;
            }
            if (visible > 1) main += Spacing * (visible - 1);
            return vertical ? new Size(cross, main) : new Size(main, cross);
        }

        protected override Size ArrangeOverride(Size final)
        {
            double offset = 0;
            var vertical = Orientation == Orientation.Vertical;
            foreach (UIElement child in InternalChildren)
            {
                if (child.Visibility == Visibility.Collapsed) { child.Arrange(new Rect()); continue; }
                var d = child.DesiredSize;
                if (vertical)
                {
                    child.Arrange(new Rect(0, offset, final.Width, d.Height));
                    offset += d.Height + Spacing;
                }
                else
                {
                    child.Arrange(new Rect(offset, 0, d.Width, final.Height));
                    offset += d.Width + Spacing;
                }
            }
            return final;
        }
    }

    /// <summary>Lays children out left to right, wrapping onto new lines.</summary>
    sealed class Flow : Panel
    {
        public double Spacing = 8;

        protected override Size MeasureOverride(Size available)
        {
            double x = 0, y = 0, row = 0, widest = 0;
            foreach (UIElement child in InternalChildren)
            {
                child.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                var d = child.DesiredSize;
                if (x + d.Width > available.Width && x > 0) { x = 0; y += row + Spacing; row = 0; }
                x += d.Width + Spacing;
                widest = Math.Max(widest, x - Spacing);
                row = Math.Max(row, d.Height);
            }
            return new Size(double.IsInfinity(available.Width) ? widest : Math.Min(widest, available.Width), y + row);
        }

        protected override Size ArrangeOverride(Size final)
        {
            double x = 0, y = 0, row = 0;
            foreach (UIElement child in InternalChildren)
            {
                var d = child.DesiredSize;
                if (x + d.Width > final.Width && x > 0) { x = 0; y += row + Spacing; row = 0; }
                child.Arrange(new Rect(x, y, d.Width, d.Height));
                x += d.Width + Spacing;
                row = Math.Max(row, d.Height);
            }
            return final;
        }
    }

    /// <summary>A grid of equal-width columns: a fixed count, or as many as fit at a minimum width.</summary>
    sealed class Tiles : Panel
    {
        public int Columns;
        public double MinColumnWidth = 200;
        public double Spacing = 14;

        int ColumnCount(double width) =>
            Columns > 0 ? Columns : Math.Max(1, (int)((width + Spacing) / (MinColumnWidth + Spacing)));

        protected override Size MeasureOverride(Size available)
        {
            var width = double.IsInfinity(available.Width) ? MinColumnWidth * 3 : available.Width;
            var cols = ColumnCount(width);
            var colWidth = (width - Spacing * (cols - 1)) / cols;
            double height = 0, row = 0;
            var i = 0;
            foreach (UIElement child in InternalChildren)
            {
                child.Measure(new Size(colWidth, double.PositiveInfinity));
                row = Math.Max(row, child.DesiredSize.Height);
                if (++i % cols == 0) { height += row + Spacing; row = 0; }
            }
            if (i % cols != 0) height += row; else if (i > 0) height -= Spacing;
            return new Size(width, height);
        }

        protected override Size ArrangeOverride(Size final)
        {
            var cols = ColumnCount(final.Width);
            var colWidth = (final.Width - Spacing * (cols - 1)) / cols;
            var children = InternalChildren.Cast<UIElement>().ToList();
            double y = 0;
            for (var start = 0; start < children.Count; start += cols)
            {
                var rowItems = children.Skip(start).Take(cols).ToList();
                var rowHeight = rowItems.Max(c => c.DesiredSize.Height);
                for (var c = 0; c < rowItems.Count; c++)
                    rowItems[c].Arrange(new Rect(c * (colWidth + Spacing), y, colWidth, rowHeight));
                y += rowHeight + Spacing;
            }
            return final;
        }
    }

    /// <summary>
    /// Part of a page that is rebuilt when some of the model's properties change,
    /// a little like a SwiftUI view body.
    /// </summary>
    sealed class Live : ContentControl
    {
        readonly INotifyPropertyChanged source;
        readonly HashSet<string> watched;
        readonly Func<UIElement> build;
        bool pending;

        public Live(INotifyPropertyChanged source, IEnumerable<string> properties, Func<UIElement> build)
        {
            this.source = source;
            watched = new HashSet<string>(properties);
            this.build = build;
            Focusable = false;
            Content = build();
            Loaded += (s, e) => source.PropertyChanged += Changed;
            Unloaded += (s, e) => source.PropertyChanged -= Changed;
        }

        void Changed(object sender, PropertyChangedEventArgs e)
        {
            if (!watched.Contains(e.PropertyName) || pending) return;
            pending = true;
            // Several properties often change together; rebuild once.
            Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() =>
            {
                pending = false;
                Content = build();
            }));
        }

        public void Rebuild() => Content = build();
    }

    /// <summary>Small helpers for building the interface in code.</summary>
    static class K
    {
        public static Brush Res(string key) => (Brush)Application.Current.Resources[key];

        public static SolidColorBrush White(double opacity) => new SolidColorBrush(Color.FromArgb((byte)Math.Round(opacity * 255), 255, 255, 255));
        public static SolidColorBrush Black(double opacity) => new SolidColorBrush(Color.FromArgb((byte)Math.Round(opacity * 255), 0, 0, 0));

        public static TextBlock T(string text, double size, FontWeight? weight = null, double opacity = 1, bool wrap = false)
        {
            var t = new TextBlock
            {
                Text = text ?? "",
                FontSize = size,
                FontWeight = weight ?? FontWeights.Normal,
                TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap,
                TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis,
            };
            // Full-strength text inherits its colour, so it follows the button or tab it sits in.
            if (opacity < 1) t.Foreground = White(opacity);
            return t;
        }

        public static TextBlock Icon(string glyph, double size, Brush brush = null)
        {
            var t = new TextBlock
            {
                Text = glyph,
                FontFamily = (FontFamily)Application.Current.Resources["IconFont"],
                FontSize = size,
                VerticalAlignment = VerticalAlignment.Center,
                TextAlignment = TextAlignment.Center,
            };
            if (brush != null) t.Foreground = brush;
            return t;
        }

        public static Stack V(double spacing, params UIElement[] children) => Build(Orientation.Vertical, spacing, children);
        public static Stack H(double spacing, params UIElement[] children) => Build(Orientation.Horizontal, spacing, children);

        static Stack Build(Orientation o, double spacing, IEnumerable<UIElement> children)
        {
            var s = new Stack { Orientation = o, Spacing = spacing };
            foreach (var c in children) if (c != null) s.Children.Add(c);
            return s;
        }

        /// <summary>A horizontal row whose last-but-one child stretches (like a Spacer before trailing items).</summary>
        public static Grid Row(double spacing, UIElement leading, params UIElement[] trailing)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            if (leading != null) g.Children.Add(leading);
            var col = 1;
            foreach (var t in trailing)
            {
                if (t == null) continue;
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                if (t is FrameworkElement fe) fe.Margin = new Thickness(spacing, fe.Margin.Top, fe.Margin.Right, fe.Margin.Bottom);
                Grid.SetColumn(t, col++);
                g.Children.Add(t);
            }
            return g;
        }

        public static Stack Label(string glyph, string text, double size = 0)
        {
            var icon = Icon(glyph, size > 0 ? size - 1 : 12);
            var label = new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center };
            if (size > 0) label.FontSize = size;
            return H(7, icon, label);
        }

        public static Border Card(UIElement child, double corner = 20, Thickness? padding = null, bool highlighted = false, Brush tint = null)
        {
            return new Border
            {
                Child = child,
                CornerRadius = new CornerRadius(corner),
                Padding = padding ?? new Thickness(18),
                Background = highlighted ? new LinearGradientBrush(Color.FromArgb(0x21, 255, 255, 255), Color.FromArgb(0x12, 255, 255, 255), 90) : Res("GlassFillBrush"),
                BorderBrush = highlighted ? (tint ?? Res("AccentBrush")) : Res("GlassStrokeBrush"),
                BorderThickness = new Thickness(highlighted ? 2 : 1),
            };
        }

        public enum Size { Small, Regular, Large }

        public static Button Button(object content, Action click, Size size = Size.Regular, bool glass = false, string tip = null)
        {
            var key = (glass ? "Glass" : "Chunky") + (size == Size.Small ? ".Small" : size == Size.Large && !glass ? ".Large" : "");
            var b = new Button { Content = content, Style = (Style)Application.Current.FindResource(key) };
            if (tip != null) b.ToolTip = tip;
            if (click != null) b.Click += (s, e) => click();
            return b;
        }

        public static Button IconButton(string glyph, Action click, string tip, bool glass = true, Size size = Size.Small) =>
            Button(Icon(glyph, 11), click, size, glass, tip);

        public static Button Plain(UIElement content, Action click, string tip = null)
        {
            var b = new Button { Content = content, Style = (Style)Application.Current.FindResource("Plain") };
            if (tip != null) b.ToolTip = tip;
            if (click != null) b.Click += (s, e) => click();
            return b;
        }

        public static ToggleButton Switch(bool isOn, Action<bool> changed)
        {
            var t = new ToggleButton { IsChecked = isOn, Style = (Style)Application.Current.FindResource("Switch"), VerticalAlignment = VerticalAlignment.Center };
            t.Checked += (s, e) => changed(true);
            t.Unchecked += (s, e) => changed(false);
            return t;
        }

        static int groupCounter;

        /// <summary>A row of choices in capsules with one selected.</summary>
        public static Border Chips<T>(IEnumerable<(string label, T value)> options, T selected, Action<T> changed, string style = "Chip")
        {
            var group = "chips" + (++groupCounter);
            var row = H(4);
            foreach (var (label, value) in options)
            {
                var content = (object)label;
                var r = new RadioButton
                {
                    Content = content,
                    GroupName = group,
                    IsChecked = EqualityComparer<T>.Default.Equals(value, selected),
                    Style = (Style)Application.Current.FindResource(style),
                };
                var v = value;
                r.Checked += (s, e) => { if (r.IsLoaded) changed(v); };
                row.Children.Add(r);
            }
            return new Border
            {
                Child = row,
                Padding = new Thickness(3),
                CornerRadius = new CornerRadius(999),
                Background = Black(0.28),
                BorderBrush = White(0.08),
                BorderThickness = new Thickness(1),
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Center,
            };
        }

        /// <summary>A page's sub-tabs.</summary>
        public static Border Tabs<T>(IEnumerable<(string label, string glyph, T value)> items, T selected, Action<T> changed)
        {
            var group = "tabs" + (++groupCounter);
            var row = H(4);
            foreach (var (label, glyph, value) in items)
            {
                var content = H(6, Icon(glyph, 12), new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center });
                var r = new RadioButton
                {
                    Content = content,
                    GroupName = group,
                    IsChecked = EqualityComparer<T>.Default.Equals(value, selected),
                    Style = (Style)Application.Current.FindResource("PageTab"),
                };
                var v = value;
                r.Checked += (s, e) => { if (r.IsLoaded) changed(v); };
                row.Children.Add(r);
            }
            return new Border
            {
                Child = row,
                Padding = new Thickness(4),
                CornerRadius = new CornerRadius(999),
                Background = Black(0.3),
                BorderBrush = White(0.1),
                BorderThickness = new Thickness(1),
                VerticalAlignment = VerticalAlignment.Bottom,
            };
        }

        public static UIElement PageHeader(string title, string subtitle, UIElement trailing = null)
        {
            var text = V(6, T(title, 34, FontWeights.Black), T(subtitle, 14, null, 0.65, wrap: true));
            return AppearIn(Row(20, text, trailing), 0);
        }

        public static UIElement SectionLabel(string text, string trailing = null) =>
            Row(10, T(text, 18, FontWeights.Black), trailing == null ? null : T(trailing, 12, null, 0.55));

        /// <summary>A row inside a group: title and optional detail on the left, a control on the right.</summary>
        public static UIElement SettingRow(string title, string detail, UIElement control)
        {
            var left = V(3, T(title, 14, FontWeights.SemiBold), detail == null ? null : T(detail, 12, null, 0.55, wrap: true));
            if (control is FrameworkElement fe) fe.VerticalAlignment = VerticalAlignment.Center;
            var row = Row(16, left, control);
            row.Margin = new Thickness(18, 13, 18, 13);
            return row;
        }

        /// <summary>Rows in one glass card with dividers between them.</summary>
        public static Border Group(params UIElement[] rows)
        {
            var stack = V(0);
            var first = true;
            foreach (var row in rows.Where(r => r != null))
            {
                if (!first) stack.Children.Add(new Border { Height = 1, Background = Res("DividerBrush"), Margin = new Thickness(18, 0, 0, 0) });
                stack.Children.Add(row);
                first = false;
            }
            return Card(stack, 20, new Thickness(0));
        }

        public static Border IconBadge(string glyph, double size = 46)
        {
            var accent = (Color)Application.Current.Resources["AccentColor"];
            return new Border
            {
                Width = size,
                Height = size,
                CornerRadius = new CornerRadius(size * 0.3),
                Background = new LinearGradientBrush(Theme.Mix(accent, Colors.White, 0.2), Theme.WithAlpha(accent, 0.75), 90),
                BorderBrush = White(0.25),
                BorderThickness = new Thickness(1),
                Child = Icon(glyph, size * 0.4),
            };
        }

        public static Border ErrorBanner(string message, Action dismiss = null)
        {
            var text = T(message, 13, null, 1, wrap: true);
            var row = Row(10, H(10, Icon("\uE7BA", 15, new SolidColorBrush(Color.FromRgb(255, 165, 0))), text),
                dismiss == null ? null : Plain(Icon("\uE711", 11, White(0.6)), dismiss, "Dismiss"));
            return new Border
            {
                Child = row,
                Padding = new Thickness(12),
                CornerRadius = new CornerRadius(12),
                Background = new SolidColorBrush(Color.FromArgb(36, 255, 165, 0)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(77, 255, 165, 0)),
                BorderThickness = new Thickness(1),
            };
        }

        public static Border Capsule(UIElement child, double background = 0.1, Thickness? padding = null) => new Border
        {
            Child = child,
            Padding = padding ?? new Thickness(9, 4, 9, 4),
            CornerRadius = new CornerRadius(999),
            Background = White(background),
            HorizontalAlignment = HorizontalAlignment.Left,
        };

        public static Flow Chips(IEnumerable<string> items)
        {
            var flow = new Flow { Spacing = 6 };
            foreach (var item in items) flow.Children.Add(Capsule(T(item, 11.5, FontWeights.Bold)));
            return flow;
        }

        /// <summary>Fades and slides an element in when it first appears, staggered by index.</summary>
        public static T AppearIn<T>(T element, int index) where T : UIElement
        {
            if (!Motion.Enabled || !Motion.JustShown) return element;
            element.Opacity = 0;
            var shift = new TranslateTransform(0, 12);
            element.RenderTransform = shift;
            RoutedEventHandler loaded = null;
            loaded = (s, e) =>
            {
                ((FrameworkElement)(object)element).Loaded -= loaded;
                var delay = TimeSpan.FromMilliseconds(Math.Min(index, 8) * 25);
                var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
                element.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(220)) { BeginTime = delay });
                shift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(300)) { BeginTime = delay, EasingFunction = ease });
            };
            if (element is FrameworkElement fe) fe.Loaded += loaded;
            else element.Opacity = 1;
            return element;
        }

        /// <summary>A picture from the web that fades in, over a placeholder.</summary>
        public static Grid WebImage(string url, UIElement placeholder, Stretch stretch = Stretch.UniformToFill)
        {
            var grid = new Grid { ClipToBounds = true };
            if (placeholder != null) grid.Children.Add(placeholder);
            if (string.IsNullOrEmpty(url)) return grid;
            try
            {
                var bitmap = Images.Web(url);
                var image = new Image { Source = bitmap, Stretch = stretch, Opacity = bitmap.IsDownloading ? 0 : 1 };
                RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
                if (bitmap.IsDownloading)
                {
                    bitmap.DownloadCompleted += (s, e) =>
                    {
                        image.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(350)));
                        if (placeholder != null) placeholder.Visibility = Visibility.Hidden;
                    };
                    bitmap.DownloadFailed += (s, e) => image.Visibility = Visibility.Collapsed;
                }
                else if (placeholder != null) placeholder.Visibility = Visibility.Hidden;
                grid.Children.Add(image);
            }
            catch (Exception e) when (e is UriFormatException || e is NotSupportedException) { }
            return grid;
        }

        /// <summary>A round avatar with a placeholder until the picture loads.</summary>
        public static FrameworkElement Avatar(string url, double size, Brush ring = null)
        {
            var accent = (Color)Application.Current.Resources["AccentColor"];
            var placeholder = new Border
            {
                Background = new LinearGradientBrush(Theme.Mix(accent, Colors.White, 0.2), accent, 90),
                Child = Icon("\uE77B", size * 0.42, White(0.8)),
            };
            var image = WebImage(url, placeholder);
            image.Width = size;
            image.Height = size;
            image.Clip = new EllipseGeometry(new Point(size / 2, size / 2), size / 2, size / 2);
            var ringShape = new System.Windows.Shapes.Ellipse
            {
                Width = size,
                Height = size,
                Stroke = ring ?? White(0.4),
                StrokeThickness = 2,
                IsHitTestVisible = false,
            };
            return new Grid { Width = size, Height = size, Children = { image, ringShape } };
        }

        /// <summary>Opens a URL or folder in the default app.</summary>
        public static void Open(string target)
        {
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(target) { UseShellExecute = true })?.Dispose(); }
            catch (Exception e) { Log.Warn($"could not open {target}: {e.Message}"); }
        }
    }

    /// <summary>Whether to animate; off when Windows asks for less motion.</summary>
    static class Motion
    {
        public static bool Enabled => SystemParameters.ClientAreaAnimation;

        /// <summary>When a page or tab last appeared; parts rebuilt later don't animate in again.</summary>
        public static DateTime PageShownAt = DateTime.MinValue;

        public static bool JustShown => (DateTime.UtcNow - PageShownAt).TotalMilliseconds < 700;
    }

    /// <summary>Images from files, the web and the app's own resources.</summary>
    static class Images
    {
        static readonly Dictionary<string, BitmapImage> WebCache = new Dictionary<string, BitmapImage>();

        public static BitmapImage Web(string url)
        {
            if (WebCache.TryGetValue(url, out var cached)) return cached;
            var b = new BitmapImage();
            b.BeginInit();
            b.UriSource = new Uri(url);
            b.CacheOption = BitmapCacheOption.OnLoad;
            b.EndInit();
            if (WebCache.Count > 200) WebCache.Clear();
            WebCache[url] = b;
            return b;
        }

        public static BitmapSource File(string path, int decodeWidth = 0)
        {
            try
            {
                if (path == null || !System.IO.File.Exists(path)) return null;
                var b = new BitmapImage();
                b.BeginInit();
                b.UriSource = new Uri(path);
                b.CacheOption = BitmapCacheOption.OnLoad;
                b.CreateOptions = BitmapCreateOptions.IgnoreImageCache;
                if (decodeWidth > 0) b.DecodePixelWidth = decodeWidth;
                b.EndInit();
                b.Freeze();
                return b;
            }
            catch (Exception e) when (e is NotSupportedException || e is System.IO.IOException || e is ArgumentException || e is UnauthorizedAccessException)
            {
                return null;
            }
        }

        static BitmapSource logo;

        /// <summary>The launcher's own icon.</summary>
        public static BitmapSource Logo
        {
            get
            {
                if (logo != null) return logo;
                var b = new BitmapImage(new Uri("pack://application:,,,/AppleLabs;component/Assets/Logo.png"));
                b.Freeze();
                return logo = b;
            }
        }

        static readonly Dictionary<string, BitmapSource> ExeIcons = new Dictionary<string, BitmapSource>(StringComparer.OrdinalIgnoreCase);

        [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        static extern uint PrivateExtractIcons(string file, int index, int cx, int cy, IntPtr[] icons, uint[] ids, uint count, uint flags);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool DestroyIcon(IntPtr icon);

        /// <summary>A program's own icon at 256 px, e.g. Roblox's.</summary>
        public static BitmapSource ExeIcon(string exe)
        {
            if (exe == null || !System.IO.File.Exists(exe)) return null;
            if (ExeIcons.TryGetValue(exe, out var cached)) return cached;
            BitmapSource result = null;
            try
            {
                var handles = new IntPtr[1];
                var ids = new uint[1];
                if (PrivateExtractIcons(exe, 0, 256, 256, handles, ids, 1, 0) > 0 && handles[0] != IntPtr.Zero)
                {
                    result = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(handles[0], Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                    result.Freeze();
                    DestroyIcon(handles[0]);
                }
            }
            catch (Exception e) { Log.Warn("could not read the icon of " + exe + ": " + e.Message); }
            ExeIcons[exe] = result;
            return result;
        }

        /// <summary>A picture blurred on the CPU once, so showing it costs nothing afterwards.</summary>
        public static BitmapSource Blurred(BitmapSource source, int radius)
        {
            var small = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
            int w = small.PixelWidth, h = small.PixelHeight, stride = w * 4;
            var pixels = new byte[h * stride];
            small.CopyPixels(pixels, stride, 0);
            var temp = new byte[pixels.Length];
            for (var pass = 0; pass < 3; pass++)
            {
                BoxBlur(pixels, temp, w, h, radius, horizontal: true);
                BoxBlur(temp, pixels, w, h, radius, horizontal: false);
            }
            var result = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
            result.Freeze();
            return result;
        }

        static void BoxBlur(byte[] src, byte[] dst, int w, int h, int r, bool horizontal)
        {
            int lines = horizontal ? h : w, length = horizontal ? w : h;
            var window = 2 * r + 1;
            for (var line = 0; line < lines; line++)
            {
                for (var c = 0; c < 4; c++)
                {
                    int Index(int i) => horizontal ? (line * w + i) * 4 + c : (i * w + line) * 4 + c;
                    var sum = 0;
                    for (var i = -r; i <= r; i++) sum += src[Index(Math.Min(Math.Max(i, 0), length - 1))];
                    for (var i = 0; i < length; i++)
                    {
                        dst[Index(i)] = (byte)(sum / window);
                        sum += src[Index(Math.Min(i + r + 1, length - 1))] - src[Index(Math.Max(i - r, 0))];
                    }
                }
            }
        }
    }
}

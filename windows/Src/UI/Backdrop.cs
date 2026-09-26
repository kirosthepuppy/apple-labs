using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;

namespace AppleLabs
{
    /// <summary>
    /// Colour glows drifting behind the window and a grid of Roblox-style studs.
    /// Each layer is rendered once into a cached bitmap and only moved, at 30fps,
    /// so the moving background costs next to nothing.
    /// </summary>
    sealed class Backdrop : Grid
    {
        readonly Rectangle baseLayer = new Rectangle();
        readonly Image picture = new Image { Stretch = Stretch.UniformToFill, Visibility = Visibility.Collapsed };
        readonly Rectangle pictureDim = new Rectangle { Fill = Brushes.Black, Visibility = Visibility.Collapsed };
        readonly Canvas glowCanvas = new Canvas { ClipToBounds = true };
        readonly Ellipse[] glows = new Ellipse[3];
        readonly TranslateTransform[] glowMoves = new TranslateTransform[3];
        readonly Rectangle studs = new Rectangle();
        readonly TranslateTransform studMove = new TranslateTransform();
        readonly Rectangle vignette = new Rectangle { IsHitTestVisible = false };
        bool animated = true;
        Theme theme;
        const double Tile = 30;

        // Where each glow drifts between (fractions of the window) and its size.
        static readonly (Point from, Point to, double size)[] Paths =
        {
            (new Point(0.10, 0.15), new Point(0.25, 0.35), 1.10),
            (new Point(0.45, 0.30), new Point(0.58, 0.48), 0.90),
            (new Point(0.85, 0.85), new Point(0.70, 0.70), 1.20),
        };

        public Backdrop()
        {
            IsHitTestVisible = false;
            Children.Add(baseLayer);
            RenderOptions.SetBitmapScalingMode(picture, BitmapScalingMode.HighQuality);
            Children.Add(picture);
            Children.Add(pictureDim);
            Children.Add(glowCanvas);
            for (var i = 0; i < 3; i++)
            {
                glowMoves[i] = new TranslateTransform();
                glows[i] = new Ellipse { RenderTransform = glowMoves[i], CacheMode = new BitmapCache(0.5) };
                glowCanvas.Children.Add(glows[i]);
            }
            var studCanvas = new Canvas { ClipToBounds = true };
            studs.RenderTransform = studMove;
            studs.CacheMode = new BitmapCache();
            studs.Fill = StudBrush();
            studCanvas.Children.Add(studs);
            Children.Add(studCanvas);
            Children.Add(vignette);
            SizeChanged += (s, e) => Layout();
        }

        static Brush StudBrush()
        {
            var group = new DrawingGroup();
            group.Children.Add(new GeometryDrawing(Brushes.Transparent, null, new RectangleGeometry(new Rect(0, 0, Tile, Tile))));
            var c = Tile / 2;
            group.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromArgb(41, 0, 0, 0)), null, new EllipseGeometry(new Point(c, c + 0.8), 3.8, 3.8)));
            group.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromArgb(19, 255, 255, 255)), null, new EllipseGeometry(new Point(c, c), 3.6, 3.6)));
            group.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromArgb(23, 255, 255, 255)), null, new EllipseGeometry(new Point(c - 0.7, c - 0.9), 1.5, 1.5)));
            var brush = new DrawingBrush(group)
            {
                TileMode = TileMode.Tile,
                Viewport = new Rect(0, 0, Tile, Tile),
                ViewportUnits = BrushMappingMode.Absolute,
                Stretch = Stretch.None,
            };
            brush.Freeze();
            return brush;
        }

        /// <summary>Paints the theme; <paramref name="glass"/> means the window itself is frosted.</summary>
        public void Update(Theme theme, bool animated, bool showStuds, bool glass, BitmapSource image, double dim)
        {
            this.theme = theme;
            var usePicture = image != null && theme.Id == ThemeId.Custom;
            picture.Source = usePicture ? image : null;
            picture.Visibility = pictureDim.Visibility = usePicture ? Visibility.Visible : Visibility.Collapsed;
            pictureDim.Opacity = dim;

            if (usePicture) baseLayer.Fill = Brushes.Black;
            else if (glass) baseLayer.Fill = new SolidColorBrush(Color.FromArgb(46, 0, 0, 0));
            else if (theme.IsGlass) baseLayer.Fill = new SolidColorBrush(Color.FromRgb(16, 18, 30)); // no acrylic on this Windows
            else baseLayer.Fill = new SolidColorBrush(theme.Base);

            var alpha = usePicture ? 0.18 : theme.IsGlass ? 0.32 : 0.85;
            for (var i = 0; i < 3; i++)
            {
                var color = theme.Glows[i];
                glows[i].Fill = new RadialGradientBrush(new GradientStopCollection
                {
                    new GradientStop(Theme.WithAlpha(color, alpha), 0),
                    new GradientStop(Theme.WithAlpha(color, alpha * 0.4), 0.55),
                    new GradientStop(Theme.WithAlpha(color, 0), 1),
                });
            }
            studs.Visibility = showStuds ? Visibility.Visible : Visibility.Collapsed;
            // A soft vignette keeps the edges from getting too bright.
            vignette.Fill = new RadialGradientBrush
            {
                RadiusX = 0.8,
                RadiusY = 0.8,
                GradientStops = { new GradientStop(Colors.Transparent, 0.25), new GradientStop(Color.FromArgb((byte)(theme.IsGlass ? 71 : 128), 0, 0, 0), 1) },
            };
            var wantAnimated = animated && Motion.Enabled;
            if (wantAnimated != this.animated)
            {
                this.animated = wantAnimated;
                Restart();
            }
        }

        void Layout()
        {
            double w = ActualWidth, h = ActualHeight;
            if (w <= 0 || h <= 0) return;
            for (var i = 0; i < 3; i++)
            {
                var side = Math.Max(w, h) * Paths[i].size;
                glows[i].Width = glows[i].Height = side;
                Canvas.SetLeft(glows[i], w * Paths[i].from.X - side / 2);
                Canvas.SetTop(glows[i], h * Paths[i].from.Y - side / 2);
            }
            // A tile bigger than the window on each side, so scrolling by one tile loops seamlessly.
            studs.Width = w + Tile * 2;
            studs.Height = h + Tile * 2;
            Canvas.SetLeft(studs, -Tile);
            Canvas.SetTop(studs, -Tile);
            Restart();
        }

        static readonly int FrameRate = 30;

        void Restart()
        {
            double w = ActualWidth, h = ActualHeight;
            for (var i = 0; i < 3; i++)
            {
                glowMoves[i].BeginAnimation(TranslateTransform.XProperty, null);
                glowMoves[i].BeginAnimation(TranslateTransform.YProperty, null);
                if (!animated || w <= 0) continue;
                var duration = TimeSpan.FromSeconds(12 + i * 3);
                var ease = new SineEase { EasingMode = EasingMode.EaseInOut };
                var dx = new DoubleAnimation(0, w * (Paths[i].to.X - Paths[i].from.X), duration) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = ease };
                var dy = new DoubleAnimation(0, h * (Paths[i].to.Y - Paths[i].from.Y), duration) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = ease };
                Timeline.SetDesiredFrameRate(dx, FrameRate);
                Timeline.SetDesiredFrameRate(dy, FrameRate);
                glowMoves[i].BeginAnimation(TranslateTransform.XProperty, dx);
                glowMoves[i].BeginAnimation(TranslateTransform.YProperty, dy);
            }
            studMove.BeginAnimation(TranslateTransform.XProperty, null);
            studMove.BeginAnimation(TranslateTransform.YProperty, null);
            if (!animated) return;
            var scroll = TimeSpan.FromSeconds(9);
            var sx = new DoubleAnimation(0, Tile, scroll) { RepeatBehavior = RepeatBehavior.Forever };
            var sy = new DoubleAnimation(0, -Tile, scroll) { RepeatBehavior = RepeatBehavior.Forever };
            Timeline.SetDesiredFrameRate(sx, FrameRate);
            Timeline.SetDesiredFrameRate(sy, FrameRate);
            studMove.BeginAnimation(TranslateTransform.XProperty, sx);
            studMove.BeginAnimation(TranslateTransform.YProperty, sy);
        }
    }
}

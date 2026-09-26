using System;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shell;

namespace AppleLabs
{
    enum ThemeId { Glass, Obsidian, Neon, Lava, Mint, Arctic, Sakura, Custom }

    /// <summary>The colours the whole launcher is painted with.</summary>
    sealed class Theme
    {
        public ThemeId Id;
        /// <summary>Three glow colours drifting behind the window content.</summary>
        public Color[] Glows;
        public Color Accent;
        public Color Base;
        /// <summary>The deep end of the Play card's gradient when there is no game artwork.</summary>
        public Color HeroGlow;

        public bool IsGlass => Id == ThemeId.Glass;

        public static readonly ThemeId[] All =
            { ThemeId.Glass, ThemeId.Obsidian, ThemeId.Neon, ThemeId.Lava, ThemeId.Mint, ThemeId.Arctic, ThemeId.Sakura, ThemeId.Custom };

        public static string Name(ThemeId id) => id.ToString();

        public static ThemeId Parse(string text) =>
            Enum.TryParse(text, true, out ThemeId id) ? id : ThemeId.Obsidian;

        static Color Rgb(double r, double g, double b) => Color.FromRgb((byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));

        public static Theme Preset(ThemeId id)
        {
            switch (id)
            {
                case ThemeId.Glass:
                    return new Theme { Id = id, Glows = new[] { Rgb(0.45, 0.65, 1.0), Rgb(0.70, 0.50, 1.0), Rgb(0.35, 0.85, 0.90) },
                        Accent = Rgb(0.25, 0.52, 1.0), Base = Colors.Transparent, HeroGlow = Rgb(0.10, 0.20, 0.45) };
                case ThemeId.Neon:
                    return new Theme { Id = id, Glows = new[] { Rgb(1.0, 0.18, 0.62), Rgb(0.10, 0.80, 1.0), Rgb(0.42, 0.10, 0.85) },
                        Accent = Rgb(0.96, 0.20, 0.58), Base = Rgb(0.045, 0.02, 0.09), HeroGlow = Rgb(0.34, 0.03, 0.40) };
                case ThemeId.Lava:
                    return new Theme { Id = id, Glows = new[] { Rgb(1.0, 0.38, 0.10), Rgb(0.78, 0.08, 0.12), Rgb(0.40, 0.06, 0.05) },
                        Accent = Rgb(0.93, 0.34, 0.12), Base = Rgb(0.07, 0.025, 0.02), HeroGlow = Rgb(0.45, 0.08, 0.03) };
                case ThemeId.Mint:
                    return new Theme { Id = id, Glows = new[] { Rgb(0.18, 0.85, 0.58), Rgb(0.04, 0.42, 0.40), Rgb(0.55, 0.90, 0.30) },
                        Accent = Rgb(0.08, 0.60, 0.42), Base = Rgb(0.02, 0.06, 0.05), HeroGlow = Rgb(0.03, 0.30, 0.24) };
                case ThemeId.Arctic:
                    return new Theme { Id = id, Glows = new[] { Rgb(0.50, 0.82, 1.0), Rgb(0.22, 0.42, 0.88), Rgb(0.62, 0.74, 0.95) },
                        Accent = Rgb(0.18, 0.52, 0.94), Base = Rgb(0.035, 0.06, 0.11), HeroGlow = Rgb(0.07, 0.24, 0.50) };
                case ThemeId.Sakura:
                    return new Theme { Id = id, Glows = new[] { Rgb(1.0, 0.58, 0.74), Rgb(0.72, 0.36, 0.68), Rgb(1.0, 0.76, 0.58) },
                        Accent = Rgb(0.90, 0.31, 0.53), Base = Rgb(0.075, 0.035, 0.055), HeroGlow = Rgb(0.44, 0.11, 0.30) };
                case ThemeId.Custom:
                    return new Theme { Id = id, Glows = new[] { Rgb(0.95, 0.45, 0.20), Rgb(0.35, 0.20, 0.60), Rgb(0.10, 0.45, 0.85) },
                        Accent = Rgb(0.20, 0.47, 1.0), Base = Rgb(0.05, 0.05, 0.08), HeroGlow = Rgb(0.08, 0.14, 0.45) };
                default:
                    return new Theme { Id = ThemeId.Obsidian, Glows = new[] { Rgb(0.36, 0.20, 0.62), Rgb(0.12, 0.10, 0.26), Rgb(0.55, 0.22, 0.52) },
                        Accent = Rgb(0.58, 0.40, 1.0), Base = Rgb(0.035, 0.03, 0.06), HeroGlow = Rgb(0.22, 0.09, 0.42) };
            }
        }

        /// <summary>A random but harmonious palette for the custom theme.</summary>
        public static Theme Surprise()
        {
            var random = new Random();
            var hue = random.NextDouble();
            var spread = 0.08 + random.NextDouble() * 0.22;
            return new Theme
            {
                Id = ThemeId.Custom,
                Glows = new[] { Hsb(hue, 0.75, 0.95), Hsb(hue + spread, 0.7, 0.6), Hsb(hue - spread, 0.8, 0.85) },
                Accent = Hsb(hue + spread / 2, 0.75, 0.82),
                Base = Hsb(hue, 0.45, 0.06),
                HeroGlow = Hsb(hue, 0.8, 0.4),
            };
        }

        public Theme Copy() => new Theme { Id = Id, Glows = (Color[])Glows.Clone(), Accent = Accent, Base = Base, HeroGlow = HeroGlow };

        public Color[] Confetti => new[] { Glows[0], Glows[1], Glows[2], Accent, Colors.White, Rgb(1.0, 0.82, 0.25) };

        // ------------------------------------------------------------------
        // Colour helpers

        public static Color Hsb(double h, double s, double v)
        {
            h = ((h % 1) + 1) % 1 * 6;
            var i = (int)Math.Floor(h);
            var f = h - i;
            double p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
            double r, g, b;
            switch (i % 6)
            {
                case 0: r = v; g = t; b = p; break;
                case 1: r = q; g = v; b = p; break;
                case 2: r = p; g = v; b = t; break;
                case 3: r = p; g = q; b = v; break;
                case 4: r = t; g = p; b = v; break;
                default: r = v; g = p; b = q; break;
            }
            return Rgb(r, g, b);
        }

        /// <summary>Relative luminance, 0 (black) to 1 (white).</summary>
        public static double Luminance(Color c)
        {
            double Channel(byte v)
            {
                var x = v / 255.0;
                return x <= 0.03928 ? x / 12.92 : Math.Pow((x + 0.055) / 1.055, 2.4);
            }
            return 0.2126 * Channel(c.R) + 0.7152 * Channel(c.G) + 0.0722 * Channel(c.B);
        }

        /// <summary>Text and icons drawn on the accent: dark on light accents.</summary>
        public Color OnAccent => Luminance(Accent) > 0.5 ? Color.FromRgb(20, 20, 20) : Colors.White;

        public static Color Mix(Color a, Color b, double t) => Color.FromArgb(
            (byte)Math.Round(a.A + (b.A - a.A) * t), (byte)Math.Round(a.R + (b.R - a.R) * t),
            (byte)Math.Round(a.G + (b.G - a.G) * t), (byte)Math.Round(a.B + (b.B - a.B) * t));

        public static Color WithAlpha(Color c, double alpha) => Color.FromArgb((byte)Math.Round(Math.Min(Math.Max(alpha, 0), 1) * 255), c.R, c.G, c.B);

        public static string Hex(Color c) => $"#{c.R:X2}{c.G:X2}{c.B:X2}";

        public static Color? ParseHex(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return null;
            text = text.Trim().TrimStart('#');
            if (text.Length != 6 || !int.TryParse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var v)) return null;
            return Color.FromRgb((byte)(v >> 16), (byte)(v >> 8), (byte)v);
        }
    }

    /// <summary>The launcher's own font, chosen on Launcher › Look.</summary>
    static class LauncherFonts
    {
        public static readonly (string id, string name, string family)[] All =
        {
            ("segoe", "Segoe UI", "Segoe UI Variable Display, Segoe UI"),
            ("bahnschrift", "Bahnschrift", "Bahnschrift, Segoe UI"),
            ("trebuchet", "Trebuchet MS", "Trebuchet MS, Segoe UI"),
            ("georgia", "Georgia", "Georgia, Segoe UI"),
            ("consolas", "Consolas", "Consolas, Segoe UI"),
            ("comic", "Comic Sans MS", "Comic Sans MS, Segoe UI"),
        };

        public static FontFamily Family(string id)
        {
            foreach (var f in All) if (f.id == id) return new FontFamily(f.family);
            return new FontFamily(All[0].family);
        }
    }

    /// <summary>Pushes a theme into the app-wide brushes the styles use.</summary>
    static class ThemeManager
    {
        public static void Apply(Theme theme)
        {
            var r = Application.Current.Resources;
            var accent = theme.Accent;
            r["AccentColor"] = accent;
            r["AccentBrush"] = Frozen(new SolidColorBrush(accent));
            r["AccentDarkBrush"] = Frozen(new SolidColorBrush(Theme.Mix(accent, Colors.Black, 0.45)));
            r["AccentTextBrush"] = Frozen(new SolidColorBrush(Theme.Mix(accent, Colors.White, 0.35)));
            r["OnAccentBrush"] = Frozen(new SolidColorBrush(theme.OnAccent));
            var face = new LinearGradientBrush(Theme.Mix(accent, Colors.White, 0.22), accent, 90);
            r["AccentFaceBrush"] = Frozen(face);
        }

        static T Frozen<T>(T f) where T : Freezable
        {
            f.Freeze();
            return f;
        }
    }

    /// <summary>
    /// Windows 11's frosted "acrylic" window background, for the Glass theme.
    /// Older Windows falls back to the dark background.
    /// </summary>
    static class Dwm
    {
        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        [DllImport("dwmapi.dll")]
        static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);

        [StructLayout(LayoutKind.Sequential)]
        struct Margins { public int Left, Right, Top, Bottom; }

        const int UseImmersiveDarkMode = 20;
        const int SystemBackdropType = 38;

        /// <summary>Acrylic needs Windows 11 22H2 (build 22621) or later.</summary>
        public static bool SupportsAcrylic => Environment.OSVersion.Version.Build >= 22621;

        public static void DarkTitleBar(Window window)
        {
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return;
            var on = 1;
            DwmSetWindowAttribute(hwnd, UseImmersiveDarkMode, ref on, sizeof(int));
        }

        /// <summary>Turns the frosted background on or off. Returns whether it is on.</summary>
        public static bool SetGlass(Window window, bool glass)
        {
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return false;
            DarkTitleBar(window);
            var on = glass && SupportsAcrylic;
            var source = HwndSource.FromHwnd(hwnd);
            // WindowChrome re-applies its own frame margins, so it has to ask for
            // the whole-window frame too or it undoes ours.
            if (WindowChrome.GetWindowChrome(window) is WindowChrome chrome)
            {
                var updated = (WindowChrome)chrome.Clone();
                updated.GlassFrameThickness = on ? new Thickness(-1) : new Thickness(0);
                WindowChrome.SetWindowChrome(window, updated);
            }
            try
            {
                var margins = on ? new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 } : new Margins();
                DwmExtendFrameIntoClientArea(hwnd, ref margins);
                var type = on ? 3 : 1; // 3 = acrylic, 1 = none
                DwmSetWindowAttribute(hwnd, SystemBackdropType, ref type, sizeof(int));
                if (source?.CompositionTarget != null)
                    source.CompositionTarget.BackgroundColor = on ? Colors.Transparent : Color.FromRgb(8, 8, 12);
            }
            catch (DllNotFoundException) { on = false; }
            catch (EntryPointNotFoundException) { on = false; }
            return on;
        }
    }
}

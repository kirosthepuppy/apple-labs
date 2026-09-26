using System;
using System.Collections.Generic;
using System.Linq;

namespace AppleLabs
{
    /// <summary>The launcher's preferences, saved as settings.json.</summary>
    sealed class Settings
    {
        public string Theme = "obsidian";
        public string CustomAccent = "#3378FF";
        public string CustomBase = "#0D0D14";
        public string CustomHero = "#142473";
        public string[] CustomGlows = { "#F27333", "#593399", "#1A73D9" };
        public string Font = "segoe";
        public double UiScale = 1.0;
        public bool AnimatedBackground = true;
        public bool ShowStuds = true;
        public bool CelebrateLaunches = true;
        public bool CloseOnLaunch = false;
        public bool ShowRecentGames = true;
        public bool HandleLinks = true;
        public double BackgroundDim = 0.35;
        public bool BackgroundBlur = false;
        public string Channel = "LIVE";
        public string CustomFontName;
        public string Page = "play";
        public string GraphicsTab = "presets";
        public string StyleTab = "cursor";
        public string LauncherTab = "look";
        public bool DesktopShortcutOffered;
        public bool RetiredFlagsRemoved;

        public static Settings Load()
        {
            var s = new Settings();
            var o = Json.TryParseObject(Paths.ReadText(Paths.Settings));
            if (o == null) return s;
            s.Theme = o.Str("theme") ?? s.Theme;
            s.CustomAccent = o.Str("customAccent") ?? s.CustomAccent;
            s.CustomBase = o.Str("customBase") ?? s.CustomBase;
            s.CustomHero = o.Str("customHero") ?? s.CustomHero;
            var glows = o.Arr("customGlows")?.OfType<string>().ToArray();
            if (glows != null && glows.Length == 3) s.CustomGlows = glows;
            s.Font = o.Str("font") ?? s.Font;
            s.UiScale = Clamp(o.Double("uiScale") ?? s.UiScale, 0.8, 1.3);
            s.AnimatedBackground = o.Bool("animatedBackground") ?? s.AnimatedBackground;
            s.ShowStuds = o.Bool("showStuds") ?? s.ShowStuds;
            s.CelebrateLaunches = o.Bool("celebrateLaunches") ?? s.CelebrateLaunches;
            s.CloseOnLaunch = o.Bool("closeOnLaunch") ?? s.CloseOnLaunch;
            s.ShowRecentGames = o.Bool("showRecentGames") ?? s.ShowRecentGames;
            s.HandleLinks = o.Bool("handleLinks") ?? s.HandleLinks;
            s.BackgroundDim = Clamp(o.Double("backgroundDim") ?? s.BackgroundDim, 0, 0.8);
            s.BackgroundBlur = o.Bool("backgroundBlur") ?? s.BackgroundBlur;
            s.Channel = o.Str("channel") ?? s.Channel;
            s.CustomFontName = o.Str("customFontName");
            s.Page = o.Str("page") ?? s.Page;
            s.GraphicsTab = o.Str("graphicsTab") ?? s.GraphicsTab;
            s.StyleTab = o.Str("styleTab") ?? s.StyleTab;
            s.LauncherTab = o.Str("launcherTab") ?? s.LauncherTab;
            s.DesktopShortcutOffered = o.Bool("desktopShortcutOffered") ?? false;
            s.RetiredFlagsRemoved = o.Bool("retiredFlagsRemoved") ?? false;
            return s;
        }

        public void Save()
        {
            var o = new Dictionary<string, object>
            {
                ["theme"] = Theme,
                ["customAccent"] = CustomAccent,
                ["customBase"] = CustomBase,
                ["customHero"] = CustomHero,
                ["customGlows"] = CustomGlows,
                ["font"] = Font,
                ["uiScale"] = UiScale,
                ["animatedBackground"] = AnimatedBackground,
                ["showStuds"] = ShowStuds,
                ["celebrateLaunches"] = CelebrateLaunches,
                ["closeOnLaunch"] = CloseOnLaunch,
                ["showRecentGames"] = ShowRecentGames,
                ["handleLinks"] = HandleLinks,
                ["backgroundDim"] = BackgroundDim,
                ["backgroundBlur"] = BackgroundBlur,
                ["channel"] = Channel,
                ["customFontName"] = CustomFontName,
                ["page"] = Page,
                ["graphicsTab"] = GraphicsTab,
                ["styleTab"] = StyleTab,
                ["launcherTab"] = LauncherTab,
                ["desktopShortcutOffered"] = DesktopShortcutOffered,
                ["retiredFlagsRemoved"] = RetiredFlagsRemoved,
            };
            try { Paths.WriteAtomic(Paths.Settings, Json.Write(o)); }
            catch (Exception e) { Log.Warn("could not save settings: " + e.Message); }
        }

        static double Clamp(double v, double lo, double hi) => Math.Min(Math.Max(v, lo), hi);
    }
}

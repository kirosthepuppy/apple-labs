using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace AppleLabs
{
    /// <summary>The launcher's overall state, shown in the status pills.</summary>
    enum LauncherState { Checking, NotInstalled, UpdateReady, Ready, Working, Playing, Failed }

    static class States
    {
        public static string Label(LauncherState s)
        {
            switch (s)
            {
                case LauncherState.Checking: return "Checking";
                case LauncherState.NotInstalled: return "Not installed";
                case LauncherState.UpdateReady: return "Update ready";
                case LauncherState.Ready: return "Ready";
                case LauncherState.Working: return "Working";
                case LauncherState.Playing: return "Playing";
                default: return "Needs attention";
            }
        }

        public static Color Color(LauncherState s)
        {
            switch (s)
            {
                case LauncherState.Ready: return System.Windows.Media.Color.FromRgb(52, 199, 89);
                case LauncherState.Playing: return System.Windows.Media.Color.FromRgb(89, 166, 255);
                case LauncherState.Working:
                case LauncherState.Checking: return System.Windows.Media.Color.FromRgb(255, 159, 10);
                case LauncherState.UpdateReady:
                case LauncherState.NotInstalled: return System.Windows.Media.Color.FromRgb(255, 214, 10);
                default: return System.Windows.Media.Color.FromRgb(255, 69, 58);
            }
        }

        public static bool Pulses(LauncherState s) => s == LauncherState.Working || s == LauncherState.Playing || s == LauncherState.Checking;
    }

    /// <summary>One entry in the Play page's "Your loadout" strip.</summary>
    sealed class LoadoutItem
    {
        public string Id, Glyph, Text;
        public bool Active;
        public string Page, Tab;
    }

    /// <summary>
    /// State shared by every screen. Changed only on the UI thread; slow work runs
    /// on the thread pool and reports back through the dispatcher.
    /// </summary>
    sealed class LauncherModel : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        public readonly Settings Settings;
        readonly Dispatcher ui;
        readonly DispatcherTimer poll;
        CancellationTokenSource cancel;

        public LauncherModel(Settings settings)
        {
            Settings = settings;
            ui = Dispatcher.CurrentDispatcher;
            installed = Roblox.Installed;
            running = Roblox.IsRunning;
            LoadFlags();
            var cache = Settings.ShowRecentGames ? Games.LoadCache() : (new List<RecentGame>(), null);
            games = cache.Item1;
            player = cache.Item2;
            LoadBackgroundImage();
            poll = new DispatcherTimer(TimeSpan.FromSeconds(2), DispatcherPriority.Background, (s, e) => RefreshRunning(), ui);
            poll.Start();
        }

        void Raise(params string[] names)
        {
            foreach (var n in names) PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
        }

        bool Set<T>(ref T field, T value, params string[] names)
        {
            if (EqualityComparer<T>.Default.Equals(field, value)) return false;
            field = value;
            Raise(names);
            return true;
        }

        void OnUi(Action action)
        {
            if (ui.CheckAccess()) action();
            else ui.BeginInvoke(action);
        }

        // ------------------------------------------------------------------
        // Status

        VersionInfo latest, installed;
        bool statusChecked, busy, running, needsRestart;
        string stage = "", error;
        double? progress;

        public VersionInfo Latest => latest;
        public VersionInfo Installed => installed;
        public bool Busy { get => busy; private set => Set(ref busy, value, nameof(Busy), nameof(State)); }
        public string Stage { get => stage; private set => Set(ref stage, value, nameof(Stage)); }
        public double? Progress { get => progress; private set => Set(ref progress, value, nameof(Progress)); }
        public string ErrorMessage { get => error; set => Set(ref error, value, nameof(ErrorMessage), nameof(State)); }
        public bool RobloxRunning => running;
        public bool NeedsRestart { get => needsRestart; set => Set(ref needsRestart, value, nameof(NeedsRestart)); }

        public LauncherState State
        {
            get
            {
                if (busy) return LauncherState.Working;
                if (error != null) return LauncherState.Failed;
                if (running) return LauncherState.Playing;
                if (latest == null && !statusChecked) return LauncherState.Checking;
                if (installed == null) return LauncherState.NotInstalled;
                if (latest != null && latest.Guid != installed.Guid) return LauncherState.UpdateReady;
                return LauncherState.Ready;
            }
        }

        public string ShortVersion => installed?.Short;

        public async void RefreshStatus()
        {
            installed = Roblox.Installed;
            Raise(nameof(Installed), nameof(State), nameof(ShortVersion));
            try
            {
                var fetched = await Roblox.FetchLatest(Settings.Channel);
                latest = fetched;
            }
            catch (Exception e)
            {
                Log.Warn("could not check for updates: " + e.Message);
            }
            statusChecked = true;
            Raise(nameof(Latest), nameof(State));
        }

        /// <summary>Called a moment after Roblox quits, e.g. to pick up new games from its logs.</summary>
        public event Action RobloxExited;

        public void RefreshRunning()
        {
            var now = Roblox.IsRunning;
            if (now == running) return;
            var exited = running && !now;
            running = now;
            if (!now) NeedsRestart = false;
            Raise(nameof(RobloxRunning), nameof(State));
            if (exited)
            {
                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
                timer.Tick += (s, e) => { timer.Stop(); RobloxExited?.Invoke(); };
                timer.Start();
            }
        }

        // ------------------------------------------------------------------
        // Tasks

        /// <summary>Runs slow work with the progress UI. Only one at a time.</summary>
        async Task<bool> RunTask(string title, Func<CancellationToken, ProgressHandler, Task> work)
        {
            if (busy) return false;
            Busy = true;
            ErrorMessage = null;
            Stage = title;
            Progress = null;
            cancel = new CancellationTokenSource();
            var token = cancel.Token;
            string lastStage = null;
            double lastProgress = -1;
            ProgressHandler report = (s, p) =>
            {
                // Only publish real changes: downloads report many times per percent.
                var rounded = p.HasValue ? Math.Round(p.Value, 2) : -1;
                if (s == lastStage && rounded == lastProgress) return;
                lastStage = s;
                lastProgress = rounded;
                OnUi(() =>
                {
                    Stage = s;
                    Progress = p.HasValue ? rounded : (double?)null;
                });
            };
            try
            {
                await Task.Run(() => work(token, report), token);
                return true;
            }
            catch (OperationCanceledException)
            {
                Stage = "Cancelled";
                return false;
            }
            catch (Exception e)
            {
                Log.Error(title + ": " + e);
                ErrorMessage = e.Message;
                return false;
            }
            finally
            {
                Busy = false;
                Progress = null;
                cancel = null;
                installed = Roblox.Installed;
                Raise(nameof(Installed), nameof(State), nameof(ShortVersion));
                RefreshRunning();
                InvalidateMods();
            }
        }

        public void Cancel() => cancel?.Cancel();

        /// <summary>Updates if needed, applies flags and mods, then starts Roblox (joining <paramref name="link"/> if given).</summary>
        public async void Launch(string link = null, bool quitAfter = false)
        {
            if (running && link == null)
            {
                Roblox.BringToFront();
                return;
            }
            var channel = Settings.Channel;
            var ok = await RunTask(link == null ? "Starting Roblox" : "Joining game", async (token, report) =>
            {
                VersionInfo newest = null;
                try { newest = await Roblox.FetchLatest(channel, token).ConfigureAwait(false); }
                catch (Exception e) when (!(e is OperationCanceledException) && Roblox.Installed != null)
                {
                    // Never block a launch on a network hiccup if Roblox is already installed.
                    Log.Warn("could not check for updates, launching what's installed: " + e.Message);
                }
                if (newest != null)
                {
                    await Roblox.Install(newest, report, token).ConfigureAwait(false);
                    OnUi(() => { latest = newest; Raise(nameof(Latest)); });
                }
                else
                {
                    Roblox.ApplyCustomizations();
                }
                report(link == null ? "Starting Roblox" : "Joining game", null);
                Roblox.Start(link);
            });
            if (!ok) return;
            Stage = link == null ? "Roblox started" : "Joining game";
            if (Settings.CelebrateLaunches) Celebrations++;
            if (quitAfter || Settings.CloseOnLaunch)
            {
                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.8) };
                timer.Tick += (s, e) => { timer.Stop(); Application.Current.Shutdown(); };
                timer.Start();
            }
        }

        public async void CheckForUpdates()
        {
            var channel = Settings.Channel;
            await RunTask("Checking for updates", async (token, report) =>
            {
                var newest = await Roblox.FetchLatest(channel, token).ConfigureAwait(false);
                OnUi(() => { latest = newest; statusChecked = true; Raise(nameof(Latest)); });
                await Roblox.Install(newest, report, token).ConfigureAwait(false);
            });
        }

        public async void Reinstall()
        {
            var channel = Settings.Channel;
            await RunTask("Reinstalling Roblox", async (token, report) =>
            {
                var newest = await Roblox.FetchLatest(channel, token).ConfigureAwait(false);
                await Roblox.Install(newest, report, token, force: true).ConfigureAwait(false);
            });
        }

        public async void RestartRoblox()
        {
            await QuitRoblox();
            NeedsRestart = false;
            Launch();
        }

        public async Task QuitRoblox()
        {
            if (!Roblox.IsRunning) return;
            Stage = "Closing Roblox";
            await Roblox.Quit();
            RefreshRunning();
        }

        int celebrations;
        /// <summary>Bumped after each successful launch to fire the confetti.</summary>
        public int Celebrations { get => celebrations; private set => Set(ref celebrations, value, nameof(Celebrations)); }

        // ------------------------------------------------------------------
        // FastFlags

        Dictionary<string, object> flags = new Dictionary<string, object>();
        string flagsError;

        public Dictionary<string, object> Flags => flags;
        public string FlagsError { get => flagsError; private set => Set(ref flagsError, value, nameof(FlagsError)); }

        public void LoadFlags()
        {
            try
            {
                flags = FastFlags.Load();
                FlagsError = null;
            }
            catch (FormatException)
            {
                FlagsError = "fflags.json is not valid JSON. Fix or clear it before editing flags here.";
            }
            Raise(nameof(Flags), nameof(ActivePreset), nameof(Loadout));
        }

        void SaveFlags(Dictionary<string, object> updated)
        {
            try
            {
                FastFlags.Save(updated);
                flags = updated;
                FlagsError = null;
                var dir = Roblox.InstalledDir;
                if (dir != null) Roblox.ApplyFlags(dir);
                if (running) NeedsRestart = true;
            }
            catch (Exception e)
            {
                FlagsError = "Could not save FastFlags: " + e.Message;
            }
            Raise(nameof(Flags), nameof(ActivePreset), nameof(Loadout));
        }

        public void SetFlag(string name, object value) => SetFlags(new Dictionary<string, object> { [name] = value });

        /// <summary>Sets several flags at once; a null value removes that flag.</summary>
        public void SetFlags(Dictionary<string, object> changes)
        {
            var updated = new Dictionary<string, object>(flags);
            foreach (var pair in changes)
            {
                if (pair.Value == null) updated.Remove(pair.Key);
                else updated[pair.Key] = pair.Value;
            }
            SaveFlags(updated);
        }

        public void ReplaceFlags(Dictionary<string, object> all) => SaveFlags(new Dictionary<string, object>(all));

        public string ImportFlags(string json)
        {
            var parsed = FastFlags.ParseImport(json, out var problem);
            if (parsed == null) return problem;
            SetFlags(parsed);
            return null;
        }

        public GraphicsPreset ActivePreset => FastFlags.ActivePreset(flags);

        public void ApplyPreset(GraphicsPreset preset)
        {
            var changes = FastFlags.PresetKeys.ToDictionary(k => k, k => (object)null);
            foreach (var pair in preset.Flags) changes[pair.Key] = pair.Value;
            SetFlags(changes);
        }

        // ------------------------------------------------------------------
        // Mods

        ModsSnapshot mods;
        int modsRevision;

        public ModsSnapshot Mods => mods ?? (mods = AppleLabs.Mods.Read(Settings.CustomFontName));
        /// <summary>Bumped whenever the mods folder changes so views re-read it.</summary>
        public int ModsRevision => modsRevision;

        /// <summary>Forgets the cached mods folder contents, e.g. after it may have changed in Explorer.</summary>
        public void InvalidateMods()
        {
            mods = null;
            modsRevision++;
            Raise(nameof(Mods), nameof(ModsRevision), nameof(Loadout));
        }

        void ModsChanged()
        {
            InvalidateMods();
            Task.Run(() =>
            {
                try
                {
                    var dir = Roblox.InstalledDir;
                    if (dir != null) Roblox.ApplyMods(dir);
                }
                catch (Exception e) { OnUi(() => ErrorMessage = "Could not apply mods: " + e.Message); }
            });
            if (running) NeedsRestart = true;
        }

        void ModAction(Action action)
        {
            try
            {
                action();
                ModsChanged();
            }
            catch (Exception e)
            {
                ErrorMessage = e.Message;
            }
        }

        public void SetCursor(CursorStyle style, string image = null) => ModAction(() => AppleLabs.Mods.SetCursor(style, image));
        public void SetDeathSound(DeathSound choice, string file = null) => ModAction(() => AppleLabs.Mods.SetDeathSound(choice, file));

        public void SetFont(string file, string name = null) => ModAction(() =>
        {
            AppleLabs.Mods.SetFont(file);
            Settings.CustomFontName = file == null ? null : name ?? FontName(file) ?? Path.GetFileNameWithoutExtension(file);
            Settings.Save();
        });

        public void ClearMods() => ModAction(AppleLabs.Mods.Clear);
        public void ApplyMods() => ModsChanged();

        static string FontName(string file)
        {
            try
            {
                using (var collection = new System.Drawing.Text.PrivateFontCollection())
                {
                    collection.AddFontFile(file);
                    return collection.Families.FirstOrDefault()?.Name;
                }
            }
            catch (Exception) { return null; }
        }

        public List<LoadoutItem> Loadout
        {
            get
            {
                var items = new List<LoadoutItem>();
                var preset = ActivePreset;
                items.Add(new LoadoutItem
                {
                    Id = "preset", Glyph = preset?.Glyph ?? "\uE9E9",
                    Text = preset == null ? "Custom graphics" : preset.Id == "default" ? "Default graphics" : preset.Name + " preset",
                    Active = preset?.Id != "default", Page = "graphics", Tab = "presets",
                });
                if (flags.TryGetValue("DFIntTaskSchedulerTargetFps", out var fps) && fps is long n)
                    items.Add(new LoadoutItem { Id = "fps", Glyph = "\uEC4A", Text = n >= 9999 ? "Unlimited FPS" : $"{n} FPS cap", Active = true, Page = "graphics", Tab = "engine" });
                var m = Mods;
                items.Add(new LoadoutItem
                {
                    Id = "cursor", Glyph = "\uE962",
                    Text = m.Cursor == CursorStyle.Standard ? "Default cursor" : m.CursorLabel + " cursor",
                    Active = m.Cursor != CursorStyle.Standard, Page = "style", Tab = "cursor",
                });
                items.Add(new LoadoutItem { Id = "font", Glyph = "\uE8D2", Text = m.FontName ?? "Default font", Active = m.FontFile != null, Page = "style", Tab = "font" });
                items.Add(new LoadoutItem
                {
                    Id = "sound", Glyph = "\uE767",
                    Text = m.Sound == DeathSound.Standard ? "Default death sound" : m.SoundLabel,
                    Active = m.Sound != DeathSound.Standard, Page = "style", Tab = "sound",
                });
                if (m.ExtraCount > 0)
                    items.Add(new LoadoutItem { Id = "mods", Glyph = "\uEA86", Text = $"{m.ExtraCount} extra mod file{(m.ExtraCount == 1 ? "" : "s")}", Active = true, Page = "style", Tab = "files" });
                var custom = flags.Keys.Count(k => !FastFlags.PresetKeys.Contains(k));
                if (custom > 0)
                    items.Add(new LoadoutItem { Id = "flags", Glyph = "\uE7C1", Text = $"{custom} custom FastFlag{(custom == 1 ? "" : "s")}", Active = true, Page = "graphics", Tab = "flags" });
                return items;
            }
        }

        // ------------------------------------------------------------------
        // Pages

        public string Page => Settings.Page;
        public bool Forward { get; private set; } = true;
        static readonly string[] PageOrder = { "play", "graphics", "style", "launcher" };

        public void Go(string page, string tab = null)
        {
            if (tab != null)
            {
                var before = Settings.GraphicsTab + Settings.StyleTab + Settings.LauncherTab;
                if (page == "graphics") Settings.GraphicsTab = tab;
                else if (page == "style") Settings.StyleTab = tab;
                else if (page == "launcher") Settings.LauncherTab = tab;
                if (before != Settings.GraphicsTab + Settings.StyleTab + Settings.LauncherTab) Raise("Tab");
            }
            if (page != Settings.Page)
            {
                Forward = Array.IndexOf(PageOrder, page) > Array.IndexOf(PageOrder, Settings.Page);
                Settings.Page = page;
                Raise(nameof(Page));
            }
            Settings.Save();
        }

        public void SetTab(string page, string tab) => Go(page, tab);

        // ------------------------------------------------------------------
        // Look

        public Theme Theme
        {
            get
            {
                var id = AppleLabs.Theme.Parse(Settings.Theme);
                return id == ThemeId.Custom ? CustomTheme : AppleLabs.Theme.Preset(id);
            }
        }

        public ThemeId ThemeId
        {
            get => AppleLabs.Theme.Parse(Settings.Theme);
            set
            {
                Settings.Theme = value.ToString().ToLowerInvariant();
                Settings.Save();
                Raise(nameof(ThemeId), nameof(Theme));
            }
        }

        /// <summary>The Custom theme's colours, kept even while another theme is in use.</summary>
        public Theme CustomTheme
        {
            get
            {
                var t = AppleLabs.Theme.Preset(ThemeId.Custom);
                t.Accent = AppleLabs.Theme.ParseHex(Settings.CustomAccent) ?? t.Accent;
                t.Base = AppleLabs.Theme.ParseHex(Settings.CustomBase) ?? t.Base;
                t.HeroGlow = AppleLabs.Theme.ParseHex(Settings.CustomHero) ?? t.HeroGlow;
                for (var i = 0; i < 3 && i < Settings.CustomGlows.Length; i++)
                    t.Glows[i] = AppleLabs.Theme.ParseHex(Settings.CustomGlows[i]) ?? t.Glows[i];
                return t;
            }
            set
            {
                Settings.CustomAccent = AppleLabs.Theme.Hex(value.Accent);
                Settings.CustomBase = AppleLabs.Theme.Hex(value.Base);
                Settings.CustomHero = AppleLabs.Theme.Hex(value.HeroGlow);
                Settings.CustomGlows = value.Glows.Select(AppleLabs.Theme.Hex).ToArray();
                Settings.Save();
                Raise(nameof(CustomTheme), nameof(Theme));
            }
        }

        public string FontId
        {
            get => Settings.Font;
            set { Settings.Font = value; Settings.Save(); Raise(nameof(FontId)); }
        }

        public double UiScale
        {
            get => Settings.UiScale;
            set
            {
                var clamped = Math.Min(Math.Max(Math.Round(value * 20) / 20, 0.8), 1.3);
                if (Math.Abs(clamped - Settings.UiScale) < 0.001) return;
                Settings.UiScale = clamped;
                Settings.Save();
                Raise(nameof(UiScale));
            }
        }

        public void Zoom(double step) => UiScale = Settings.UiScale + step;

        public bool AnimatedBackground { get => Settings.AnimatedBackground; set { Settings.AnimatedBackground = value; Settings.Save(); Raise(nameof(AnimatedBackground)); } }
        public bool ShowStuds { get => Settings.ShowStuds; set { Settings.ShowStuds = value; Settings.Save(); Raise(nameof(ShowStuds)); } }
        public bool CelebrateLaunches { get => Settings.CelebrateLaunches; set { Settings.CelebrateLaunches = value; Settings.Save(); Raise(nameof(CelebrateLaunches)); } }
        public bool CloseOnLaunch { get => Settings.CloseOnLaunch; set { Settings.CloseOnLaunch = value; Settings.Save(); Raise(nameof(CloseOnLaunch)); } }

        public string Channel
        {
            get => Settings.Channel;
            set
            {
                var c = string.IsNullOrWhiteSpace(value) ? "LIVE" : value.Trim();
                if (c == Settings.Channel) return;
                Settings.Channel = c;
                Settings.Save();
                Raise(nameof(Channel));
                RefreshStatus();
            }
        }

        // Background picture (Custom theme)

        BitmapSource backgroundImage;
        public BitmapSource BackgroundImage { get => backgroundImage; private set => Set(ref backgroundImage, value, nameof(BackgroundImage)); }

        public double BackgroundDim { get => Settings.BackgroundDim; set { Settings.BackgroundDim = Math.Min(Math.Max(value, 0), 0.8); Settings.Save(); Raise(nameof(BackgroundDim)); } }

        public bool BackgroundBlur
        {
            get => Settings.BackgroundBlur;
            set { Settings.BackgroundBlur = value; Settings.Save(); Raise(nameof(BackgroundBlur)); LoadBackgroundImage(); }
        }

        string BackgroundFile => Directory.Exists(Paths.Home)
            ? Directory.GetFiles(Paths.Home, "Background.*").FirstOrDefault()
            : null;

        public void SetBackgroundImage(string file)
        {
            try
            {
                if (BackgroundFile is string old) File.Delete(old);
                if (file != null)
                {
                    Directory.CreateDirectory(Paths.Home);
                    File.Copy(file, Path.Combine(Paths.Home, "Background" + Path.GetExtension(file).ToLowerInvariant()), true);
                }
            }
            catch (Exception e)
            {
                ErrorMessage = "Could not use that picture: " + e.Message;
            }
            LoadBackgroundImage();
        }

        /// <summary>Decodes, shrinks and (optionally) blurs the picture off the UI thread, once.</summary>
        void LoadBackgroundImage()
        {
            var file = BackgroundFile;
            if (file == null) { BackgroundImage = null; return; }
            var blur = Settings.BackgroundBlur;
            Task.Run(() =>
            {
                var image = Images.File(file, blur ? 640 : 2560);
                if (image != null && blur) image = Images.Blurred(image, 6);
                OnUi(() =>
                {
                    if (BackgroundFile != file || Settings.BackgroundBlur != blur) return;
                    if (image == null) ErrorMessage = "Could not read that picture.";
                    BackgroundImage = image;
                });
            });
        }

        // ------------------------------------------------------------------
        // Website links

        public bool IsLinkHandler => Roblox.LinksOpenWith(App.ExePath);

        public void SetLinkHandler(bool on)
        {
            try
            {
                Settings.HandleLinks = on;
                Settings.Save();
                if (on) Roblox.RegisterLinks(App.ExePath);
                else Roblox.UnregisterLinks(App.ExePath);
            }
            catch (Exception e) { ErrorMessage = "Could not change website links: " + e.Message; }
            Raise(nameof(IsLinkHandler));
        }

        // ------------------------------------------------------------------
        // Recent games

        List<RecentGame> games;
        RobloxPlayer player;
        bool gamesRefreshing;
        RecentGame linkGame;

        public List<RecentGame> RecentGames => games;
        public RobloxPlayer Player => player;
        public bool GamesRefreshing { get => gamesRefreshing; private set => Set(ref gamesRefreshing, value, nameof(GamesRefreshing)); }
        /// <summary>The game a website link is joining, shown in the link window.</summary>
        public RecentGame LinkGame { get => linkGame; private set => Set(ref linkGame, value, nameof(LinkGame)); }

        public bool ShowRecentGames
        {
            get => Settings.ShowRecentGames;
            set
            {
                Settings.ShowRecentGames = value;
                Settings.Save();
                if (value) RefreshGames();
                else
                {
                    games = new List<RecentGame>();
                    player = null;
                    Games.ClearCache();
                    Raise(nameof(RecentGames), nameof(Player));
                }
                Raise(nameof(ShowRecentGames));
            }
        }

        public async void RefreshGames()
        {
            if (!Settings.ShowRecentGames || gamesRefreshing) return;
            GamesRefreshing = true;
            try
            {
                var cached = games;
                var cachedPlayer = player;
                var scanned = await Task.Run(() => Games.Refresh(cached, cachedPlayer));
                if (!Settings.ShowRecentGames) return;
                games = scanned.games;
                player = scanned.player;
                Raise(nameof(RecentGames), nameof(Player));

                var detailed = await Games.FetchDetails(games);
                if (player != null && player.AvatarUrl == null)
                {
                    var avatars = await Games.FetchAvatars(new[] { player.UserId.ToString() });
                    if (avatars.TryGetValue(player.UserId.ToString(), out var url)) player.AvatarUrl = url;
                }
                if (!Settings.ShowRecentGames) return;
                games = detailed;
                Raise(nameof(RecentGames), nameof(Player));
                Games.SaveCache(games, player);
            }
            catch (Exception e) { Log.Warn("recent games: " + e.Message); }
            finally { GamesRefreshing = false; }
        }

        /// <summary>Looks up the name and icon for a place a website link is joining.</summary>
        public async void LookUpLinkGame(string link)
        {
            if (!Settings.ShowRecentGames || !(Games.PlaceIdInLink(link) is long place)) return;
            var known = games.FirstOrDefault(g => g.PlaceId == place);
            if (known != null) { LinkGame = known; return; }
            var found = await Games.FetchDetails(new List<RecentGame> { new RecentGame { PlaceId = place, LastPlayed = DateTime.UtcNow } });
            LinkGame = found.FirstOrDefault();
        }

        // ------------------------------------------------------------------
        // Accounts

        List<RobloxAccount> accounts = new List<RobloxAccount>();
        SignedInAccount currentAccount;
        readonly Dictionary<string, string> avatars = new Dictionary<string, string>();
        bool accountsWorking;
        string accountsError;

        public List<RobloxAccount> AccountList => accounts;
        public SignedInAccount CurrentAccount => currentAccount;
        public bool AccountsWorking { get => accountsWorking; private set => Set(ref accountsWorking, value, nameof(AccountsWorking)); }
        public string AccountsError { get => accountsError; set => Set(ref accountsError, value, nameof(AccountsError)); }
        public bool CurrentIsSaved => currentAccount != null && accounts.Any(a => a.UserId == currentAccount.UserId);

        public string Avatar(string userId) => userId != null && avatars.TryGetValue(userId, out var url) ? url : null;

        /// <summary>The picture to show for whoever is signed in.</summary>
        public string CurrentAvatar => Avatar(currentAccount?.UserId) ?? (Settings.ShowRecentGames ? player?.AvatarUrl : null);
        public string CurrentName => currentAccount?.Name ?? (Settings.ShowRecentGames ? player?.DisplayName : null);

        public async void RefreshAccounts()
        {
            try
            {
                var result = await Task.Run(() => (Accounts.List(), Accounts.Current));
                accounts = result.Item1;
                currentAccount = result.Item2;
                Raise(nameof(AccountList), nameof(CurrentAccount), nameof(CurrentAvatar), nameof(CurrentName));
                var missing = accounts.Select(a => a.UserId).Concat(new[] { currentAccount?.UserId })
                    .Where(id => id != null && !avatars.ContainsKey(id)).ToList();
                if (missing.Count == 0) return;
                foreach (var pair in await Games.FetchAvatars(missing)) avatars[pair.Key] = pair.Value;
                Raise(nameof(AccountList), nameof(CurrentAvatar));
            }
            catch (Exception e) { Log.Warn("accounts: " + e.Message); }
        }

        async Task AccountTask(Func<Task> work)
        {
            if (accountsWorking) return;
            AccountsWorking = true;
            AccountsError = null;
            try { await work(); }
            catch (Exception e) { AccountsError = e.Message; }
            finally
            {
                AccountsWorking = false;
                RefreshAccounts();
            }
        }

        /// <summary>Refreshes saved sign-ins after Roblox quits (and finishes adding a new account).</summary>
        public void AutoSaveAccounts()
        {
            if (accountsWorking) return;
            Task.Run(() =>
            {
                try { Accounts.Save(auto: true); } catch (Exception e) { Log.Warn("auto-save account: " + e.Message); }
            }).ContinueWith(t => OnUi(RefreshAccounts));
        }

        public async void SaveCurrentAccount() => await AccountTask(() => Task.Run(() => { Accounts.Save(); }));

        public async void RemoveAccount(RobloxAccount account) => await AccountTask(() => Task.Run(() => Accounts.Remove(account.UserId)));

        /// <summary>Switches Roblox to <paramref name="account"/>, closing it first; if it was open it starts again.</summary>
        public async void SwitchAccount(RobloxAccount account) => await AccountTask(async () =>
        {
            var relaunch = running;
            await QuitRoblox();
            await Task.Run(() => Accounts.Use(account.UserId));
            if (relaunch) Launch();
        });

        /// <summary>Signs Roblox out (after saving the current account) and opens it for another sign-in.</summary>
        public async void AddAccount() => await AccountTask(async () =>
        {
            await QuitRoblox();
            await Task.Run(() => Accounts.Add());
            Launch();
        });
    }
}

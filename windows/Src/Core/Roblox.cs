using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace AppleLabs
{
    sealed class VersionInfo
    {
        /// <summary>The CDN folder name, e.g. "version-2366ba214ec740ca".</summary>
        public string Guid;
        /// <summary>What people call it, e.g. "0.740.0.7400927".</summary>
        public string Display;
        public string Channel;

        public string Short => ShortVersion(Display);

        public static string ShortVersion(string display)
        {
            if (string.IsNullOrEmpty(display)) return null;
            var parts = display.Split('.');
            return parts.Length >= 2 ? parts[0] + "." + parts[1] : display;
        }
    }

    /// <summary>Reports what an install or launch is doing: a stage line and a 0–1 fraction (null = unknown).</summary>
    delegate void ProgressHandler(string stage, double? fraction);

    /// <summary>
    /// Installs, updates and launches the Windows Roblox player straight from
    /// Roblox's CDN, the way Bloxstrap does: each version goes in its own
    /// folder under Versions, then FastFlags and mods are written into it.
    /// </summary>
    static class Roblox
    {
        public const string ProcessName = "RobloxPlayerBeta";
        public const string PlayerExe = "RobloxPlayerBeta.exe";
        static readonly string[] Hosts =
        {
            "https://setup.rbxcdn.com", "https://setup-aws.rbxcdn.com", "https://setup-ak.rbxcdn.com",
        };

        public static readonly HttpClient Http = CreateClient();

        static HttpClient CreateClient()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            ServicePointManager.DefaultConnectionLimit = Math.Max(ServicePointManager.DefaultConnectionLimit, 8);
            var client = new HttpClient { Timeout = TimeSpan.FromMinutes(30) };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("AppleLabs/" + App.Version);
            return client;
        }

        // Where each package from the manifest is unpacked inside a version folder.
        static readonly Dictionary<string, string> PackageRoots = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["RobloxApp.zip"] = "",
            ["redist.zip"] = "",
            ["shaders.zip"] = "shaders",
            ["ssl.zip"] = "ssl",
            ["WebView2.zip"] = "",
            ["WebView2RuntimeInstaller.zip"] = "WebView2RuntimeInstaller",
            ["content-avatar.zip"] = "content/avatar",
            ["content-configs.zip"] = "content/configs",
            ["content-fonts.zip"] = "content/fonts",
            ["content-sky.zip"] = "content/sky",
            ["content-sounds.zip"] = "content/sounds",
            ["content-textures2.zip"] = "content/textures",
            ["content-models.zip"] = "content/models",
            ["content-platform-fonts.zip"] = "PlatformContent/pc/fonts",
            ["content-platform-dictionaries.zip"] = "PlatformContent/pc/shared_compression_dictionaries",
            ["content-terrain.zip"] = "PlatformContent/pc/terrain",
            ["content-textures3.zip"] = "PlatformContent/pc/textures",
            ["extracontent-luapackages.zip"] = "ExtraContent/LuaPackages",
            ["extracontent-translations.zip"] = "ExtraContent/translations",
            ["extracontent-models.zip"] = "ExtraContent/models",
            ["extracontent-textures.zip"] = "ExtraContent/textures",
            ["extracontent-places.zip"] = "ExtraContent/places",
        };

        const string AppSettingsXml =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n" +
            "<Settings>\r\n" +
            "\t<ContentFolder>content</ContentFolder>\r\n" +
            "\t<BaseUrl>http://www.roblox.com</BaseUrl>\r\n" +
            "</Settings>\r\n";

        // Mods the Style page manages, relative to a version folder.
        public const string DeathSoundPath = "content/sounds/ouch.ogg";
        public const string OofPath = "content/sounds/oof.ogg";
        public static readonly string[] CursorPaths =
        {
            "content/textures/Cursors/KeyboardMouse/ArrowCursor.png",
            "content/textures/Cursors/KeyboardMouse/ArrowFarCursor.png",
        };
        public static readonly string[] ClassicCursorSources =
        {
            "content/textures/ArrowCursor.png",
            "content/textures/ArrowFarCursor.png",
        };
        public static readonly string[] FontPaths = { "content/fonts/CustomFont.ttf", "content/fonts/CustomFont.otf" };

        // ------------------------------------------------------------------
        // Versions

        public static string VersionDir(string guid) => Path.Combine(Paths.Versions, guid);

        /// <summary>The version installed by the launcher, if its folder is intact.</summary>
        public static VersionInfo Installed
        {
            get
            {
                var o = Json.TryParseObject(Paths.ReadText(Paths.State));
                var guid = o.Str("guid");
                if (string.IsNullOrEmpty(guid) || !File.Exists(Path.Combine(VersionDir(guid), PlayerExe))) return null;
                return new VersionInfo { Guid = guid, Display = o.Str("version"), Channel = o.Str("channel") ?? "LIVE" };
            }
        }

        public static string InstalledDir => Installed is VersionInfo v ? VersionDir(v.Guid) : null;

        static void SaveInstalled(VersionInfo v)
        {
            Paths.WriteAtomic(Paths.State, Json.Write(new Dictionary<string, object>
            {
                ["guid"] = v.Guid,
                ["version"] = v.Display,
                ["channel"] = v.Channel,
                ["installedAt"] = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            }));
        }

        static bool IsLive(string channel) => string.IsNullOrWhiteSpace(channel) || channel.Equals("LIVE", StringComparison.OrdinalIgnoreCase);

        /// <summary>Asks Roblox which version is current, falling back to LIVE when a channel is closed.</summary>
        public static async Task<VersionInfo> FetchLatest(string channel, CancellationToken cancel = default)
        {
            channel = string.IsNullOrWhiteSpace(channel) ? "LIVE" : channel.Trim();
            var url = "https://clientsettingscdn.roblox.com/v2/client-version/WindowsPlayer";
            if (!IsLive(channel)) url += "/channel/" + Uri.EscapeDataString(channel);
            using (var response = await Http.GetAsync(url, cancel).ConfigureAwait(false))
            {
                if (!response.IsSuccessStatusCode)
                {
                    if (!IsLive(channel))
                    {
                        Log.Warn($"channel {channel} is not available ({(int)response.StatusCode}); using LIVE");
                        return await FetchLatest("LIVE", cancel).ConfigureAwait(false);
                    }
                    throw new InvalidOperationException($"Roblox's version service answered {(int)response.StatusCode}.");
                }
                var o = Json.ParseObject(await response.Content.ReadAsStringAsync().ConfigureAwait(false));
                var guid = o.Str("clientVersionUpload");
                if (string.IsNullOrEmpty(guid)) throw new InvalidOperationException("Roblox's version service gave no version.");
                return new VersionInfo { Guid = guid, Display = o.Str("version") ?? guid, Channel = IsLive(channel) ? "LIVE" : channel };
            }
        }

        static string PackageUrl(string host, VersionInfo v, string file) =>
            IsLive(v.Channel)
                ? $"{host}/{v.Guid}-{file}"
                : $"{host}/channel/{v.Channel.ToLowerInvariant()}/{v.Guid}-{file}";

        sealed class Package
        {
            public string Name, Md5;
            public long PackedSize;
        }

        static List<Package> ParseManifest(string text)
        {
            var lines = text.Replace("\r", "").Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
            if (lines.Count == 0 || lines[0] != "v0") throw new InvalidOperationException("Roblox's package list is in an unknown format.");
            var packages = new List<Package>();
            // After "v0", four lines per package: name, MD5, packed size, unpacked size.
            for (var i = 1; i + 2 < lines.Count; i += 4)
            {
                long.TryParse(lines[i + 2], out var packed);
                packages.Add(new Package { Name = lines[i], Md5 = lines[i + 1].ToLowerInvariant(), PackedSize = packed });
            }
            return packages;
        }

        static string RootFor(string package)
        {
            if (PackageRoots.TryGetValue(package, out var root)) return root;
            // Guess from the naming Roblox uses for the rest.
            var name = Path.GetFileNameWithoutExtension(package);
            if (name.StartsWith("content-", StringComparison.OrdinalIgnoreCase)) return "content/" + name.Substring(8);
            if (name.StartsWith("extracontent-", StringComparison.OrdinalIgnoreCase)) return "ExtraContent/" + name.Substring(13);
            Log.Warn($"unknown package {package}; unpacking it at the top level");
            return "";
        }

        /// <summary>
        /// Installs <paramref name="version"/> unless it is already there, then applies
        /// FastFlags and mods. Safe to call from several launcher windows at once.
        /// </summary>
        public static async Task Install(VersionInfo version, ProgressHandler progress, CancellationToken cancel, bool force = false)
        {
            using (await AcquireInstallLock(cancel).ConfigureAwait(false))
            {
                var dir = VersionDir(version.Guid);
                var current = Installed;
                if (!force && current != null && current.Guid == version.Guid)
                {
                    ApplyCustomizations();
                    return;
                }

                Log.Info($"installing Roblox {version.Display} ({version.Guid}, {version.Channel})");
                progress?.Invoke($"Downloading Roblox {VersionInfo.ShortVersion(version.Display)}", 0);
                var manifest = await GetWithFallback(v => PackageUrl(v, version, "rbxPkgManifest.txt"), cancel).ConfigureAwait(false);
                var packages = ParseManifest(manifest).Where(p => p.Name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)).ToList();
                if (!packages.Any(p => p.Name.Equals("RobloxApp.zip", StringComparison.OrdinalIgnoreCase)))
                    throw new InvalidOperationException("Roblox's package list has no RobloxApp.zip.");

                var staging = dir + ".partial";
                Paths.TryDeleteDirectory(staging);
                Directory.CreateDirectory(staging);
                Directory.CreateDirectory(Paths.Downloads);

                long total = Math.Max(1, packages.Sum(p => p.PackedSize)), done = 0;
                void Report(long bytes)
                {
                    var now = Interlocked.Add(ref done, bytes);
                    progress?.Invoke($"Downloading Roblox {VersionInfo.ShortVersion(version.Display)}", Math.Min(1, (double)now / total));
                }

                var gate = new SemaphoreSlim(4);
                var files = new Dictionary<string, string>();
                var tasks = packages.Select(async p =>
                {
                    await gate.WaitAsync(cancel).ConfigureAwait(false);
                    try
                    {
                        var file = await Download(version, p, Report, cancel).ConfigureAwait(false);
                        lock (files) files[p.Name] = file;
                    }
                    finally { gate.Release(); }
                }).ToList();
                await Task.WhenAll(tasks).ConfigureAwait(false);

                progress?.Invoke("Unpacking Roblox", null);
                foreach (var p in packages)
                {
                    cancel.ThrowIfCancellationRequested();
                    Extract(files[p.Name], Path.Combine(staging, RootFor(p.Name).Replace('/', '\\')));
                }
                File.WriteAllText(Path.Combine(staging, "AppSettings.xml"), AppSettingsXml);
                if (!File.Exists(Path.Combine(staging, PlayerExe)))
                    throw new InvalidOperationException("The download didn't contain " + PlayerExe + ".");

                Paths.TryDeleteDirectory(dir);
                Directory.Move(staging, dir);
                foreach (var f in files.Values) TryDelete(f);

                SaveInstalled(version);
                // A fresh copy has Roblox's original files, so old mod backups are stale.
                Paths.TryDeleteDirectory(Paths.ModState);
                ApplyCustomizations();
                RemoveOldVersions(version.Guid);
                Log.Info($"installed Roblox {version.Display} at {dir}");
            }
        }

        static async Task<string> GetWithFallback(Func<string, string> url, CancellationToken cancel)
        {
            Exception last = null;
            foreach (var host in Hosts)
            {
                try
                {
                    using (var response = await Http.GetAsync(url(host), cancel).ConfigureAwait(false))
                    {
                        response.EnsureSuccessStatusCode();
                        return await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    }
                }
                catch (Exception e) when (!(e is OperationCanceledException) || !cancel.IsCancellationRequested)
                {
                    last = e;
                    Log.Warn($"{url(host)}: {e.Message}");
                }
            }
            throw new InvalidOperationException("Couldn't reach Roblox's download servers. " + last?.Message);
        }

        static async Task<string> Download(VersionInfo version, Package p, Action<long> report, CancellationToken cancel)
        {
            var target = Path.Combine(Paths.Downloads, p.Md5 + "-" + p.Name);
            if (File.Exists(target) && Md5Of(target) == p.Md5)
            {
                report(p.PackedSize);
                return target;
            }
            Exception last = null;
            for (var attempt = 0; attempt < Hosts.Length * 2; attempt++)
            {
                var host = Hosts[attempt % Hosts.Length];
                long counted = 0;
                try
                {
                    using (var response = await Http.GetAsync(PackageUrl(host, version, p.Name), HttpCompletionOption.ResponseHeadersRead, cancel).ConfigureAwait(false))
                    {
                        response.EnsureSuccessStatusCode();
                        using (var source = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
                        using (var output = File.Create(target))
                        {
                            var buffer = new byte[81920];
                            int read;
                            while ((read = await source.ReadAsync(buffer, 0, buffer.Length, cancel).ConfigureAwait(false)) > 0)
                            {
                                await output.WriteAsync(buffer, 0, read, cancel).ConfigureAwait(false);
                                counted += read;
                                report(read);
                            }
                        }
                    }
                    if (Md5Of(target) == p.Md5) return target;
                    throw new InvalidDataException($"{p.Name} didn't match its checksum");
                }
                catch (Exception e) when (!cancel.IsCancellationRequested)
                {
                    last = e;
                    report(-counted);
                    TryDelete(target);
                    Log.Warn($"download of {p.Name} from {host} failed: {e.Message}");
                }
            }
            throw new InvalidOperationException($"Couldn't download {p.Name}. {last?.Message}");
        }

        static string Md5Of(string file)
        {
            using (var md5 = MD5.Create())
            using (var stream = File.OpenRead(file))
                return BitConverter.ToString(md5.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
        }

        /// <summary>Unpacks a Roblox package. Their entries use backslashes and include folder entries.</summary>
        static void Extract(string zip, string destination)
        {
            Directory.CreateDirectory(destination);
            using (var archive = ZipFile.OpenRead(zip))
            {
                foreach (var entry in archive.Entries)
                {
                    var name = entry.FullName.Replace('\\', '/').TrimStart('/');
                    if (name.Length == 0 || name.EndsWith("/")) continue;
                    var target = Paths.Inside(destination, name);
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    entry.ExtractToFile(target, true);
                }
            }
        }

        static void RemoveOldVersions(string keep)
        {
            if (!Directory.Exists(Paths.Versions)) return;
            foreach (var dir in Directory.GetDirectories(Paths.Versions))
            {
                if (Path.GetFileName(dir).Equals(keep, StringComparison.OrdinalIgnoreCase)) continue;
                // A version still in use can't be removed; it goes next time.
                try { Directory.Delete(dir, true); }
                catch (Exception e) { Log.Info($"left {dir} for later: {e.Message}"); }
            }
        }

        static void TryDelete(string file)
        {
            try { if (File.Exists(file)) File.Delete(file); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }

        /// <summary>Only one install at a time, across every launcher window and process.</summary>
        static async Task<IDisposable> AcquireInstallLock(CancellationToken cancel)
        {
            Directory.CreateDirectory(Paths.Home);
            var path = Path.Combine(Paths.Home, "install.lock");
            while (true)
            {
                try { return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None, 1, FileOptions.DeleteOnClose); }
                catch (IOException) { await Task.Delay(400, cancel).ConfigureAwait(false); }
            }
        }

        // ------------------------------------------------------------------
        // FastFlags and mods

        public static void ApplyCustomizations()
        {
            var dir = InstalledDir;
            if (dir == null) return;
            ApplyFlags(dir);
            ApplyMods(dir);
        }

        public static void ApplyFlags(string dir)
        {
            var flags = FastFlags.Load();
            var target = Path.Combine(dir, "ClientSettings", "ClientAppSettings.json");
            Paths.WriteAtomic(target, Json.Write(flags) + "\n");
        }

        /// <summary>
        /// Copies everything in Modifications over the Roblox folder (it mirrors the
        /// version folder, so Modifications\content\sounds\ouch.ogg replaces the
        /// death sound). Originals are backed up so removing a mod restores them,
        /// and a CustomFont.ttf/.otf is wired into every font family.
        /// </summary>
        public static void ApplyMods(string dir)
        {
            Directory.CreateDirectory(Paths.Mods);
            Directory.CreateDirectory(Paths.ModBackups);

            // What should end up in the Roblox folder: relative path → source file or text.
            var wanted = new SortedDictionary<string, Func<string, bool>>(StringComparer.OrdinalIgnoreCase);
            foreach (var file in Directory.EnumerateFiles(Paths.Mods, "*", SearchOption.AllDirectories))
            {
                var name = Path.GetFileName(file);
                if (name.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase) || name.Equals("Thumbs.db", StringComparison.OrdinalIgnoreCase)) continue;
                var rel = Paths.Relative(Paths.Mods, file);
                if (rel == null) continue;
                var source = file;
                wanted[rel] = target => { File.Copy(source, target, true); return true; };
            }

            var font = FontPaths.Select(p => p.Substring("content/fonts/".Length)).FirstOrDefault(p => File.Exists(Path.Combine(Paths.Mods, "content", "fonts", p)));
            if (font != null)
            {
                var families = Path.Combine(dir, "content", "fonts", "families");
                if (Directory.Exists(families))
                {
                    foreach (var fam in Directory.GetFiles(families, "*.json"))
                    {
                        var rel = "content/fonts/families/" + Path.GetFileName(fam);
                        // Build from the original when we've already replaced it.
                        var backup = Path.Combine(Paths.ModBackups, rel.Replace('/', '\\'));
                        var original = File.Exists(backup) ? backup : fam;
                        var text = Regex.Replace(File.ReadAllText(original), "(\"assetId\"\\s*:\\s*)\"[^\"]*\"",
                            "$1\"rbxasset://fonts/" + font + "\"");
                        wanted[rel] = target => { File.WriteAllText(target, text, new UTF8Encoding(false)); return true; };
                    }
                }
            }

            var previous = File.Exists(Paths.ModManifest)
                ? new HashSet<string>(File.ReadAllLines(Paths.ModManifest).Where(l => l.Length > 0), StringComparer.OrdinalIgnoreCase)
                : new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // Put back files whose mod was removed.
            foreach (var rel in previous.Where(r => !wanted.ContainsKey(r)).ToList())
            {
                var live = Paths.Inside(dir, rel);
                var backup = Paths.Inside(Paths.ModBackups, rel);
                try
                {
                    if (File.Exists(backup))
                    {
                        File.Copy(backup, live, true);
                        File.Delete(backup);
                    }
                    else if (File.Exists(live)) File.Delete(live);
                }
                catch (Exception e) { Log.Warn($"could not restore {rel}: {e.Message}"); }
            }

            // Copy mods in, backing up each original the first time we replace it.
            var applied = new List<string>();
            foreach (var pair in wanted)
            {
                var live = Paths.Inside(dir, pair.Key);
                try
                {
                    if (File.Exists(live) && !previous.Contains(pair.Key))
                    {
                        var backup = Paths.Inside(Paths.ModBackups, pair.Key);
                        Directory.CreateDirectory(Path.GetDirectoryName(backup));
                        File.Copy(live, backup, true);
                    }
                    Directory.CreateDirectory(Path.GetDirectoryName(live));
                    pair.Value(live);
                    applied.Add(pair.Key);
                }
                catch (Exception e) { Log.Warn($"could not apply mod {pair.Key}: {e.Message}"); }
            }
            Directory.CreateDirectory(Paths.ModState);
            File.WriteAllLines(Paths.ModManifest, applied);
        }

        /// <summary>Roblox's own copy of a file, even while a mod replaces it.</summary>
        public static string OriginalResource(string relative)
        {
            var backup = Path.Combine(Paths.ModBackups, relative.Replace('/', '\\'));
            if (File.Exists(backup)) return backup;
            var dir = InstalledDir;
            return dir == null ? null : Path.Combine(dir, relative.Replace('/', '\\'));
        }

        public static string Resource(string relative)
        {
            var dir = InstalledDir;
            return dir == null ? null : Path.Combine(dir, relative.Replace('/', '\\'));
        }

        public static string ModFile(string relative) => Path.Combine(Paths.Mods, relative.Replace('/', '\\'));

        // ------------------------------------------------------------------
        // Running Roblox

        public static bool IsRunning
        {
            get
            {
                var processes = Process.GetProcessesByName(ProcessName);
                foreach (var p in processes) p.Dispose();
                return processes.Length > 0;
            }
        }

        public static bool IsRobloxLink(string text) =>
            text != null && (text.StartsWith("roblox-player:", StringComparison.OrdinalIgnoreCase) ||
                             text.StartsWith("roblox:", StringComparison.OrdinalIgnoreCase));

        /// <summary>Starts the installed Roblox, joining <paramref name="link"/> when given.</summary>
        public static void Start(string link = null)
        {
            var dir = InstalledDir ?? throw new InvalidOperationException("Roblox isn't installed yet.");
            if (link != null && !IsRobloxLink(link)) throw new ArgumentException("Not a Roblox link: " + link);
            var info = new ProcessStartInfo(Path.Combine(dir, PlayerExe))
            {
                WorkingDirectory = dir,
                UseShellExecute = false,
                Arguments = link == null ? "--app" : "\"" + link.Replace("\"", "") + "\"",
            };
            Log.Info(link == null ? "starting Roblox" : "launch url");
            Process.Start(info)?.Dispose();
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool SetForegroundWindow(IntPtr hWnd);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        public static void BringToFront()
        {
            foreach (var p in Process.GetProcessesByName(ProcessName))
            {
                using (p)
                {
                    if (p.MainWindowHandle == IntPtr.Zero) continue;
                    ShowWindow(p.MainWindowHandle, 9); // SW_RESTORE
                    SetForegroundWindow(p.MainWindowHandle);
                }
            }
        }

        /// <summary>Asks Roblox to close, and ends it if it hasn't after about ten seconds.</summary>
        public static async Task Quit()
        {
            var processes = Process.GetProcessesByName(ProcessName);
            foreach (var p in processes) { try { p.CloseMainWindow(); } catch (InvalidOperationException) { } }
            for (var i = 0; i < 50 && IsRunning; i++) await Task.Delay(200).ConfigureAwait(false);
            foreach (var p in processes)
            {
                try { if (!p.HasExited) p.Kill(); } catch (Exception) { }
                p.Dispose();
            }
            for (var i = 0; i < 25 && IsRunning; i++) await Task.Delay(200).ConfigureAwait(false);
        }

        // ------------------------------------------------------------------
        // roblox:// and roblox-player:// links

        static readonly string[] Schemes = { "roblox", "roblox-player" };

        public static void RegisterLinks(string exe)
        {
            foreach (var scheme in Schemes)
            {
                using (var key = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{scheme}"))
                {
                    key.SetValue("", "URL: Roblox Protocol");
                    key.SetValue("URL Protocol", "");
                    using (var icon = key.CreateSubKey("DefaultIcon")) icon.SetValue("", $"\"{exe}\",0");
                    using (var command = key.CreateSubKey(@"shell\open\command")) command.SetValue("", $"\"{exe}\" \"%1\"");
                }
            }
            Log.Info("roblox links now open with " + exe);
        }

        public static string LinkHandlerCommand(string scheme = "roblox-player")
        {
            using (var key = Registry.CurrentUser.OpenSubKey($@"Software\Classes\{scheme}\shell\open\command"))
                return key?.GetValue("") as string;
        }

        public static bool LinksOpenWith(string exe)
        {
            var command = LinkHandlerCommand();
            return command != null && command.IndexOf(exe, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        /// <summary>Hands links back to Roblox's own install if there is one; otherwise removes ours.</summary>
        public static void UnregisterLinks(string exe)
        {
            if (!LinksOpenWith(exe)) return;
            var official = OfficialPlayer();
            foreach (var scheme in Schemes)
            {
                if (official != null)
                {
                    using (var command = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{scheme}\shell\open\command"))
                        command.SetValue("", $"\"{official}\" %1");
                    using (var icon = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{scheme}\DefaultIcon"))
                        icon.SetValue("", $"\"{official}\"");
                }
                else
                {
                    Registry.CurrentUser.DeleteSubKeyTree($@"Software\Classes\{scheme}", false);
                }
            }
            Log.Info(official != null ? "roblox links handed back to " + official : "roblox link handler removed");
        }

        /// <summary>Roblox's own player, installed by Roblox's installer, if present.</summary>
        static string OfficialPlayer()
        {
            var versions = Path.Combine(Paths.RobloxLocal, "Versions");
            if (!Directory.Exists(versions)) return null;
            return Directory.GetDirectories(versions)
                .Select(d => Path.Combine(d, PlayerExe))
                .Where(File.Exists)
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .FirstOrDefault();
        }

        // ------------------------------------------------------------------
        // Status

        public static Dictionary<string, object> StatusJson(VersionInfo latest)
        {
            var installed = Installed;
            int modFiles = Directory.Exists(Paths.Mods) ? Directory.EnumerateFiles(Paths.Mods, "*", SearchOption.AllDirectories).Count() : 0;
            Dictionary<string, object> flags;
            try { flags = FastFlags.Load(); } catch (FormatException) { flags = new Dictionary<string, object>(); }
            return new Dictionary<string, object>
            {
                ["version"] = App.Version,
                ["installed"] = installed?.Display,
                ["installedGuid"] = installed?.Guid,
                ["installPath"] = installed == null ? null : VersionDir(installed.Guid),
                ["channel"] = installed?.Channel ?? "LIVE",
                ["latest"] = latest?.Display,
                ["latestGuid"] = latest?.Guid,
                ["upToDate"] = latest == null || installed == null ? (object)null : latest.Guid == installed.Guid,
                ["running"] = IsRunning,
                ["linkHandler"] = LinksOpenWith(App.ExePath),
                ["fflags"] = (long)flags.Count,
                ["modFiles"] = (long)modFiles,
                ["home"] = Paths.Home,
            };
        }
    }
}

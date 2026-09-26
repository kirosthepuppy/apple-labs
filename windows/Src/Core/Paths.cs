using System;
using System.IO;
using System.Text;

namespace AppleLabs
{
    /// <summary>Where everything lives. APPLELABS_HOME moves the launcher's own
    /// folder (used by the tests); ROBLOX_LOCAL_DIR moves Roblox's.</summary>
    static class Paths
    {
        static readonly string LocalAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

        public static readonly string Home = Env("APPLELABS_HOME") ?? Path.Combine(LocalAppData, "AppleLabs");

        public static string InstalledExe => Path.Combine(Home, "Apple Labs.exe");
        public static string Versions => Path.Combine(Home, "Versions");
        public static string Downloads => Path.Combine(Home, "Downloads");
        public static string Mods => Path.Combine(Home, "Modifications");
        public static string ModState => Path.Combine(Home, "ModState");
        public static string ModBackups => Path.Combine(ModState, "Backups");
        public static string ModManifest => Path.Combine(ModState, "applied.txt");
        public static string FFlags => Path.Combine(Home, "fflags.json");
        public static string Settings => Path.Combine(Home, "settings.json");
        public static string State => Path.Combine(Home, "state.json");
        public static string Accounts => Path.Combine(Home, "Accounts");
        public static string LogFile => Path.Combine(Home, "apple-labs.log");
        public static string GamesCache => Path.Combine(Home, "recent-games.json");

        // Roblox's own per-user folder, where its logs and sign-in live.
        public static readonly string RobloxLocal = Env("ROBLOX_LOCAL_DIR") ?? Path.Combine(LocalAppData, "Roblox");
        public static string RobloxLogs => Path.Combine(RobloxLocal, "logs");
        public static string RobloxCookies => Path.Combine(RobloxLocal, "LocalStorage", "RobloxCookies.dat");
        public static string RobloxAppStorage => Path.Combine(RobloxLocal, "LocalStorage", "appStorage.json");

        public static string StartMenuShortcut =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Apple Labs.lnk");
        public static string DesktopShortcut =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Apple Labs.lnk");

        static string Env(string name)
        {
            var value = Environment.GetEnvironmentVariable(name);
            return string.IsNullOrWhiteSpace(value) ? null : value;
        }

        /// <summary>Writes through a temporary file so a crash never leaves half a file.</summary>
        public static void WriteAtomic(string path, string text)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, text, new UTF8Encoding(false));
            if (File.Exists(path)) File.Replace(tmp, path, null);
            else File.Move(tmp, path);
        }

        public static string ReadText(string path) => File.Exists(path) ? File.ReadAllText(path) : null;

        /// <summary>Normalises a relative path inside the mods folder to forward slashes.</summary>
        public static string Relative(string root, string full)
        {
            var r = Path.GetFullPath(root).TrimEnd('\\', '/') + "\\";
            var f = Path.GetFullPath(full);
            return f.StartsWith(r, StringComparison.OrdinalIgnoreCase) ? f.Substring(r.Length).Replace('\\', '/') : null;
        }

        /// <summary>Joins a forward-slash relative path onto a folder, refusing to escape it.</summary>
        public static string Inside(string root, string relative)
        {
            var full = Path.GetFullPath(Path.Combine(root, relative.Replace('/', '\\')));
            var r = Path.GetFullPath(root).TrimEnd('\\', '/') + "\\";
            if (!full.StartsWith(r, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException($"{relative} points outside {root}");
            return full;
        }

        public static void TryDeleteDirectory(string path)
        {
            try { if (Directory.Exists(path)) Directory.Delete(path, true); }
            catch (Exception e) { Log.Warn($"could not remove {path}: {e.Message}"); }
        }
    }

    static class Log
    {
        static readonly object Gate = new object();

        public static void Info(string message) => Write("INFO", message);
        public static void Warn(string message) => Write("WARN", message);
        public static void Error(string message) => Write("ERR ", message);

        static void Write(string level, string message)
        {
            lock (Gate)
            {
                try
                {
                    Directory.CreateDirectory(Paths.Home);
                    var file = new FileInfo(Paths.LogFile);
                    // Keep the log small: start over past 2 MB.
                    if (file.Exists && file.Length > 2 * 1024 * 1024) file.Delete();
                    File.AppendAllText(Paths.LogFile, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {level} {message}\r\n");
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
        }
    }
}

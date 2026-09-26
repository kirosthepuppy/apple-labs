using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace AppleLabs
{
    sealed class RobloxAccount
    {
        public string UserId, Username, DisplayName, SavedAt;
        public bool Active;
        public string Name => string.IsNullOrEmpty(DisplayName) ? Username : DisplayName;
    }

    sealed class SignedInAccount
    {
        public string UserId, Username, DisplayName;
        public string Name => string.IsNullOrEmpty(DisplayName) ? Username : DisplayName;
    }

    /// <summary>
    /// Roblox keeps its sign-in in LocalStorage\RobloxCookies.dat, encrypted for
    /// this Windows user. A saved account is a copy of that file plus the
    /// account's name, kept in the launcher's folder; switching swaps it in
    /// while Roblox is closed. Passwords are never involved and the copies stay
    /// encrypted the same way.
    /// </summary>
    static class Accounts
    {
        static string Dir => Paths.Accounts;
        static string ActiveFile => Path.Combine(Dir, ".active");
        static string SwitchedFile => Path.Combine(Dir, ".switched");
        static string AddingFile => Path.Combine(Dir, ".adding");

        /// <summary>Serialises account changes across launcher windows.</summary>
        static T Locked<T>(Func<T> work)
        {
            using (var mutex = new Mutex(false, @"Local\AppleLabs.Accounts"))
            {
                bool owned;
                try { owned = mutex.WaitOne(TimeSpan.FromSeconds(15)); }
                catch (AbandonedMutexException) { owned = true; }
                if (!owned) throw new InvalidOperationException("Another account change is still running; try again.");
                try { return work(); }
                finally { mutex.ReleaseMutex(); }
            }
        }

        static void Init() => Directory.CreateDirectory(Dir);

        /// <summary>The cookie file holds a Roblox session only while someone is signed in.</summary>
        public static bool RobloxSignedIn
        {
            get
            {
                var file = Paths.RobloxCookies;
                if (!File.Exists(file)) return false;
                try
                {
                    var data = Json.TryParseObject(File.ReadAllText(file)).Str("CookiesData");
                    if (string.IsNullOrEmpty(data)) return false;
                    var plain = ProtectedData.Unprotect(Convert.FromBase64String(data), null, DataProtectionScope.CurrentUser);
                    return Encoding.UTF8.GetString(plain).IndexOf(".ROBLOSECURITY", StringComparison.Ordinal) >= 0;
                }
                catch (Exception e) when (e is CryptographicException || e is FormatException || e is IOException)
                {
                    return false;
                }
            }
        }

        static Dictionary<string, object> Storage => Json.TryParseObject(Paths.ReadText(Paths.RobloxAppStorage));

        /// <summary>Changes whenever Roblox rewrites its app storage, i.e. whenever it has run.</summary>
        static string StorageFingerprint
        {
            get
            {
                var f = new FileInfo(Paths.RobloxAppStorage);
                return f.Exists ? $"{f.LastWriteTimeUtc.Ticks}:{f.Length}" : "none";
            }
        }

        static Dictionary<string, object> SavedInfo(string id) => Json.TryParseObject(Paths.ReadText(Path.Combine(Dir, id, "account.json")));

        /// <summary>The account whose session is in Roblox right now, or null.</summary>
        public static SignedInAccount Current
        {
            get
            {
                if (!RobloxSignedIn) return null;
                if (File.Exists(SwitchedFile) && File.ReadAllText(SwitchedFile).Trim() == StorageFingerprint)
                {
                    // We swapped sessions and Roblox hasn't run since, so its own record is stale.
                    var id = (Paths.ReadText(ActiveFile) ?? "").Trim();
                    var info = id.Length > 0 ? SavedInfo(id) : null;
                    if (info == null) return null;
                    return new SignedInAccount { UserId = id, Username = info.Str("username"), DisplayName = info.Str("displayName") };
                }
                var s = Storage;
                var userId = s.Str("UserId");
                if (string.IsNullOrEmpty(userId) || !userId.All(char.IsDigit)) return null;
                return new SignedInAccount { UserId = userId, Username = s.Str("Username"), DisplayName = s.Str("DisplayName") };
            }
        }

        public static List<RobloxAccount> List()
        {
            Init();
            var current = Current;
            var result = new List<RobloxAccount>();
            foreach (var dir in Directory.GetDirectories(Dir))
            {
                var id = Path.GetFileName(dir);
                var info = SavedInfo(id);
                if (info == null) continue;
                result.Add(new RobloxAccount
                {
                    UserId = id,
                    Username = info.Str("username"),
                    DisplayName = info.Str("displayName"),
                    SavedAt = info.Str("savedAt"),
                    Active = current?.UserId == id,
                });
            }
            return result.OrderBy(a => a.Name, StringComparer.OrdinalIgnoreCase).ToList();
        }

        static string Find(string who)
        {
            if (who.All(char.IsDigit) && SavedInfo(who) != null) return who;
            foreach (var dir in Directory.GetDirectories(Dir))
            {
                var info = SavedInfo(Path.GetFileName(dir));
                if (info == null) continue;
                if (string.Equals(info.Str("username"), who, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(info.Str("displayName"), who, StringComparison.OrdinalIgnoreCase))
                    return Path.GetFileName(dir);
            }
            return null;
        }

        static void MarkSwitched() => File.WriteAllText(SwitchedFile, StorageFingerprint);

        /// <summary>
        /// Remembers the signed-in account. <paramref name="auto"/> (used after Roblox
        /// quits) only refreshes accounts that are already saved, plus one being added,
        /// so removing an account here sticks. Returns the saved account's name.
        /// </summary>
        public static string Save(bool auto = false) => Locked(() => SaveUnlocked(auto, quiet: auto));

        static string SaveUnlocked(bool auto, bool quiet)
        {
            Init();
            var current = Current;
            if (current == null)
            {
                if (quiet) return null;
                throw new InvalidOperationException("No Roblox account is signed in on this PC. Open Roblox and sign in first.");
            }
            var dir = Path.Combine(Dir, current.UserId);
            if (auto && SavedInfo(current.UserId) == null && !File.Exists(AddingFile)) return null;
            Directory.CreateDirectory(dir);
            File.Copy(Paths.RobloxCookies, Path.Combine(dir, "RobloxCookies.tmp"), true);
            var saved = Path.Combine(dir, "RobloxCookies.dat");
            if (File.Exists(saved)) File.Delete(saved);
            File.Move(Path.Combine(dir, "RobloxCookies.tmp"), saved);
            Paths.WriteAtomic(Path.Combine(dir, "account.json"), Json.Write(new Dictionary<string, object>
            {
                ["userId"] = current.UserId,
                ["username"] = current.Username,
                ["displayName"] = current.DisplayName,
                ["savedAt"] = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            }));
            File.WriteAllText(ActiveFile, current.UserId);
            if (File.Exists(AddingFile)) File.Delete(AddingFile);
            Log.Info($"saved account {current.UserId}");
            return current.Name;
        }

        public static string Use(string who) => Locked(() =>
        {
            Init();
            var id = Find(who) ?? throw new InvalidOperationException($"No saved account matches '{who}'.");
            if (Roblox.IsRunning) throw new InvalidOperationException("Close Roblox before switching accounts.");
            // Keep the current session before replacing it.
            SaveUnlocked(auto: false, quiet: true);
            Directory.CreateDirectory(Path.GetDirectoryName(Paths.RobloxCookies));
            File.Copy(Path.Combine(Dir, id, "RobloxCookies.dat"), Paths.RobloxCookies, true);
            File.WriteAllText(ActiveFile, id);
            MarkSwitched();
            if (File.Exists(AddingFile)) File.Delete(AddingFile);
            Log.Info($"switched to account {id}");
            return SavedInfo(id).Str("displayName") ?? id;
        });

        /// <summary>Signs Roblox out on this PC (saving the session first) so another account can sign in.</summary>
        public static void Add() => Locked(() =>
        {
            Init();
            if (Roblox.IsRunning) throw new InvalidOperationException("Close Roblox before adding an account.");
            SaveUnlocked(auto: false, quiet: true);
            var current = Current;
            if (RobloxSignedIn && (current == null || SavedInfo(current.UserId) == null))
                // Never throw away a session we couldn't identify.
                File.Copy(Paths.RobloxCookies, Path.Combine(Dir, $"unsaved-{DateTime.Now:yyyyMMddHHmmss}.dat"), true);
            if (File.Exists(Paths.RobloxCookies)) File.Delete(Paths.RobloxCookies);
            File.WriteAllText(ActiveFile, "");
            MarkSwitched();
            File.WriteAllText(AddingFile, "");
            Log.Info("signed Roblox out to add an account");
            return true;
        });

        public static void Remove(string who) => Locked(() =>
        {
            Init();
            var id = Find(who) ?? throw new InvalidOperationException($"No saved account matches '{who}'.");
            Directory.Delete(Path.Combine(Dir, id), true);
            if ((Paths.ReadText(ActiveFile) ?? "").Trim() == id) File.WriteAllText(ActiveFile, "");
            Log.Info($"removed account {id}");
            return true;
        });
    }
}

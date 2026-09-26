using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace AppleLabs
{
    /// <summary>A Roblox experience the player joined recently, found in Roblox's logs.</summary>
    sealed class RecentGame
    {
        public long PlaceId;
        public long? UniverseId;
        public DateTime LastPlayed;
        public string Name;
        public int? Playing;
        public string IconUrl;
        public string ArtUrl;

        public string DisplayName => Name ?? $"Experience {PlaceId}";
        public string LaunchLink => $"roblox://experiences/start?placeId={PlaceId}";
        public string WebUrl => $"https://www.roblox.com/games/{PlaceId}";
        public string LastPlayedText => RelativeTime(LastPlayed);
        public string PlayingText => Playing is int n && n > 0 ? $"{CompactNumber(n)} playing now" : null;

        public RecentGame Clone() => (RecentGame)MemberwiseClone();

        public static string CompactNumber(int n)
        {
            string Short(double value, string suffix)
            {
                var text = value.ToString(value >= 100 ? "0" : "0.0", CultureInfo.InvariantCulture);
                return (text.EndsWith(".0") ? text.Substring(0, text.Length - 2) : text) + suffix;
            }
            if (n >= 1_000_000) return Short(n / 1_000_000.0, "M");
            if (n >= 1_000) return Short(n / 1_000.0, "K");
            return n.ToString(CultureInfo.InvariantCulture);
        }

        public static string RelativeTime(DateTime when)
        {
            var span = DateTime.UtcNow - when.ToUniversalTime();
            if (span.TotalSeconds < 60) return "just now";
            if (span.TotalMinutes < 60) return Plural((int)span.TotalMinutes, "minute") + " ago";
            if (span.TotalHours < 24) return Plural((int)span.TotalHours, "hour") + " ago";
            if (span.TotalDays < 2) return "yesterday";
            if (span.TotalDays < 30) return Plural((int)span.TotalDays, "day") + " ago";
            if (span.TotalDays < 365) return Plural((int)(span.TotalDays / 30), "month") + " ago";
            return Plural((int)(span.TotalDays / 365), "year") + " ago";
        }

        static string Plural(int n, string unit) => $"{n} {unit}{(n == 1 ? "" : "s")}";
    }

    /// <summary>The account that last joined a game on this PC, from the join ticket in the logs.</summary>
    sealed class RobloxPlayer
    {
        public long UserId;
        public string DisplayName;
        public string AvatarUrl;
    }

    /// <summary>
    /// Recently played experiences and the player's avatar. Everything is read
    /// from Roblox's own log files; names, player counts and pictures come from
    /// Roblox's public web APIs.
    /// </summary>
    static class Games
    {
        const int MaxGames = 12;

        // e.g. "2026-09-25T15:13:55.164Z,77.16,6d553000,6 [FLog::Output] ! Joining game '<job>' place 7041939546 at <address>"
        static readonly Regex Join = new Regex(@"^(\S+?),[^\n]*! Joining game '[^']*' place (\d+)", RegexOptions.Multiline | RegexOptions.Compiled);
        static readonly Regex User = new Regex("\"UserId\":(\\d+),\"UserName\":\"[^\"]*\",\"DisplayName\":\"([^\"]*)\"", RegexOptions.Compiled);
        static readonly Regex Universe = new Regex("\"PlaceId\":(\\d+),\"UniverseId\":(\\d+)", RegexOptions.Compiled);
        static readonly Regex PlaceInLink = new Regex(@"placeId[=:](\d+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public static long? PlaceIdInLink(string link)
        {
            var decoded = Uri.UnescapeDataString(link ?? "");
            var m = PlaceInLink.Match(decoded);
            return m.Success && long.TryParse(m.Groups[1].Value, out var id) ? id : (long?)null;
        }

        // ------------------------------------------------------------------
        // Cache

        public static (List<RecentGame> games, RobloxPlayer player) LoadCache()
        {
            var o = Json.TryParseObject(Paths.ReadText(Paths.GamesCache));
            var games = new List<RecentGame>();
            foreach (var item in o.Arr("games") ?? new List<object>())
            {
                if (!(item is Dictionary<string, object> g) || g.Long("placeId") is null) continue;
                games.Add(new RecentGame
                {
                    PlaceId = g.Long("placeId").Value,
                    UniverseId = g.Long("universeId"),
                    LastPlayed = DateTime.TryParse(g.Str("lastPlayed"), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var d) ? d : DateTime.MinValue,
                    Name = g.Str("name"),
                    Playing = (int?)g.Long("playing"),
                    IconUrl = g.Str("iconUrl"),
                    ArtUrl = g.Str("artUrl"),
                });
            }
            var p = o.Obj("player");
            var player = p?.Long("userId") is long uid
                ? new RobloxPlayer { UserId = uid, DisplayName = p.Str("displayName"), AvatarUrl = p.Str("avatarUrl") }
                : null;
            return (games, player);
        }

        public static void SaveCache(List<RecentGame> games, RobloxPlayer player)
        {
            var o = new Dictionary<string, object>
            {
                ["games"] = games.Select(g => new Dictionary<string, object>
                {
                    ["placeId"] = g.PlaceId,
                    ["universeId"] = g.UniverseId,
                    ["lastPlayed"] = g.LastPlayed.ToUniversalTime().ToString("o"),
                    ["name"] = g.Name,
                    ["playing"] = g.Playing,
                    ["iconUrl"] = g.IconUrl,
                    ["artUrl"] = g.ArtUrl,
                }).ToList(),
                ["player"] = player == null ? null : new Dictionary<string, object>
                {
                    ["userId"] = player.UserId,
                    ["displayName"] = player.DisplayName,
                    ["avatarUrl"] = player.AvatarUrl,
                },
            };
            try { Paths.WriteAtomic(Paths.GamesCache, Json.Write(o)); }
            catch (Exception e) { Log.Warn("could not save recent games: " + e.Message); }
        }

        public static void ClearCache()
        {
            try { if (File.Exists(Paths.GamesCache)) File.Delete(Paths.GamesCache); } catch (IOException) { }
        }

        // ------------------------------------------------------------------
        // Logs

        sealed class Scan
        {
            public readonly List<(long place, DateTime date)> Visits = new List<(long, DateTime)>();
            public readonly Dictionary<long, long> Universes = new Dictionary<long, long>();
            public (long userId, string name, DateTime date)? Player;
        }

        static DateTime ParseStamp(string text, DateTime fallback) =>
            DateTime.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var d) ? d : fallback;

        static Scan ScanLogs()
        {
            var scan = new Scan();
            if (!Directory.Exists(Paths.RobloxLogs)) return scan;
            var logs = new DirectoryInfo(Paths.RobloxLogs).GetFiles("*.log")
                .OrderByDescending(f => f.LastWriteTimeUtc).Take(80);
            foreach (var file in logs)
            {
                string text;
                try
                {
                    // Roblox may still be writing the newest log.
                    using (var stream = new FileStream(file.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                    using (var reader = new StreamReader(stream))
                        text = reader.ReadToEnd();
                }
                catch (IOException) { continue; }
                catch (UnauthorizedAccessException) { continue; }

                foreach (Match m in Join.Matches(text))
                {
                    if (long.TryParse(m.Groups[2].Value, out var place))
                        scan.Visits.Add((place, ParseStamp(m.Groups[1].Value, file.LastWriteTimeUtc)));
                }
                // The join ticket is URL-encoded JSON inside a longer line.
                foreach (var line in text.Split('\n'))
                {
                    if (line.IndexOf("UniverseId", StringComparison.Ordinal) < 0) continue;
                    var decoded = DecodeTicket(line);
                    foreach (Match m in Universe.Matches(decoded))
                    {
                        if (long.TryParse(m.Groups[1].Value, out var place) && long.TryParse(m.Groups[2].Value, out var uni))
                            scan.Universes[place] = uni;
                    }
                    var u = User.Match(decoded);
                    if (u.Success && long.TryParse(u.Groups[1].Value, out var id))
                    {
                        var comma = line.IndexOf(',');
                        var date = ParseStamp(comma > 0 ? line.Substring(0, comma) : "", file.LastWriteTimeUtc);
                        if (scan.Player == null || date > scan.Player.Value.date) scan.Player = (id, u.Groups[2].Value, date);
                    }
                }
            }
            return scan;
        }

        static string DecodeTicket(string line)
        {
            var unescaped = line.Replace("\\", "");
            try { return Uri.UnescapeDataString(unescaped); }
            catch (UriFormatException) { return WebUtility.UrlDecode(unescaped); }
        }

        /// <summary>Newest visit per experience, reusing details already fetched.</summary>
        static List<RecentGame> Merge(Scan scan, List<RecentGame> cached)
        {
            var byPlace = new Dictionary<long, RecentGame>();
            foreach (var (place, date) in scan.Visits)
            {
                if (byPlace.TryGetValue(place, out var existing) && existing.LastPlayed >= date) continue;
                var game = cached.FirstOrDefault(g => g.PlaceId == place)?.Clone() ?? new RecentGame { PlaceId = place };
                game.LastPlayed = date;
                if (game.UniverseId == null && scan.Universes.TryGetValue(place, out var uni)) game.UniverseId = uni;
                byPlace[place] = game;
            }
            // Keep older cached games (logs get cleaned up) below the fresh ones.
            foreach (var game in cached) if (!byPlace.ContainsKey(game.PlaceId)) byPlace[game.PlaceId] = game.Clone();
            var seen = new HashSet<long>();
            return byPlace.Values
                .OrderByDescending(g => g.LastPlayed)
                .Where(g => g.UniverseId == null || seen.Add(g.UniverseId.Value))
                .Take(MaxGames)
                .ToList();
        }

        /// <summary>Reads the logs. Quick; the second step, <see cref="FetchDetails"/>, goes to the network.</summary>
        public static (List<RecentGame> games, RobloxPlayer player) Refresh(List<RecentGame> cached, RobloxPlayer cachedPlayer)
        {
            var scan = ScanLogs();
            var merged = Merge(scan, cached);
            RobloxPlayer player = cachedPlayer;
            if (scan.Player is var p && p != null)
            {
                player = new RobloxPlayer
                {
                    UserId = p.Value.userId,
                    DisplayName = p.Value.name,
                    AvatarUrl = p.Value.userId == cachedPlayer?.UserId ? cachedPlayer.AvatarUrl : null,
                };
            }
            return (merged, player);
        }

        // ------------------------------------------------------------------
        // Roblox web APIs

        static async Task<Dictionary<string, object>> Get(string url)
        {
            try
            {
                using (var response = await Roblox.Http.GetAsync(url).ConfigureAwait(false))
                {
                    if (!response.IsSuccessStatusCode) return null;
                    return Json.TryParseObject(await response.Content.ReadAsStringAsync().ConfigureAwait(false));
                }
            }
            catch (Exception e)
            {
                Log.Warn($"{url}: {e.Message}");
                return null;
            }
        }

        public static async Task<List<RecentGame>> FetchDetails(List<RecentGame> input)
        {
            var games = input.Select(g => g.Clone()).ToList();
            foreach (var g in games.Where(g => g.UniverseId == null))
                g.UniverseId = (await Get($"https://apis.roblox.com/universes/v1/places/{g.PlaceId}/universe").ConfigureAwait(false)).Long("universeId");
            var ids = games.Where(g => g.UniverseId != null).Select(g => g.UniverseId.Value).Distinct().ToList();
            if (ids.Count == 0) return games;
            var list = string.Join(",", ids);

            var info = Get($"https://games.roblox.com/v1/games?universeIds={list}");
            var icons = Get($"https://thumbnails.roblox.com/v1/games/icons?universeIds={list}&returnPolicy=PlaceHolder&size=256x256&format=Png&isCircular=false");
            var art = Get($"https://thumbnails.roblox.com/v1/games/multiget/thumbnails?universeIds={list}&countPerUniverse=1&defaults=true&size=768x432&format=Png&isCircular=false");
            await Task.WhenAll(info, icons, art).ConfigureAwait(false);

            var infoData = info.Result.Arr("data")?.OfType<Dictionary<string, object>>().ToList() ?? new List<Dictionary<string, object>>();
            var iconData = icons.Result.Arr("data")?.OfType<Dictionary<string, object>>().ToList() ?? new List<Dictionary<string, object>>();
            var artData = art.Result.Arr("data")?.OfType<Dictionary<string, object>>().ToList() ?? new List<Dictionary<string, object>>();

            foreach (var g in games)
            {
                if (g.UniverseId is not long uni) continue;
                var gi = infoData.FirstOrDefault(d => d.Long("id") == uni);
                if (gi != null)
                {
                    g.Name = gi.Str("name");
                    g.Playing = (int?)gi.Long("playing");
                }
                var icon = iconData.FirstOrDefault(d => d.Long("targetId") == uni)?.Str("imageUrl");
                if (icon != null) g.IconUrl = icon;
                var wide = artData.FirstOrDefault(d => d.Long("universeId") == uni)?.Arr("thumbnails")?
                    .OfType<Dictionary<string, object>>().FirstOrDefault()?.Str("imageUrl");
                if (wide != null) g.ArtUrl = wide;
            }
            return games;
        }

        public static async Task<Dictionary<string, string>> FetchAvatars(IEnumerable<string> userIds)
        {
            var ids = userIds.Where(i => !string.IsNullOrEmpty(i)).Distinct().OrderBy(i => i).ToList();
            var result = new Dictionary<string, string>();
            if (ids.Count == 0) return result;
            var o = await Get($"https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds={string.Join(",", ids)}&size=150x150&format=Png&isCircular=false").ConfigureAwait(false);
            foreach (var item in o.Arr("data")?.OfType<Dictionary<string, object>>() ?? Enumerable.Empty<Dictionary<string, object>>())
            {
                var id = item.Long("targetId");
                var url = item.Str("imageUrl");
                if (id != null && url != null) result[id.Value.ToString(CultureInfo.InvariantCulture)] = url;
            }
            return result;
        }
    }
}

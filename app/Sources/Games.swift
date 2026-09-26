import AppKit
import Foundation

/// A Roblox experience the player joined recently, found in Roblox's logs.
struct RecentGame: Identifiable, Codable, Equatable {
    let placeId: Int64
    var universeId: Int64?
    var lastPlayed: Date
    var name: String?
    var playing: Int?
    var iconURL: URL?
    var artURL: URL?

    var id: Int64 { placeId }
    var displayName: String { name ?? "Experience \(placeId)" }
    var launchLink: String { "roblox://experiences/start?placeId=\(placeId)" }
    var webURL: URL { URL(string: "https://www.roblox.com/games/\(placeId)")! }

    var lastPlayedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastPlayed, relativeTo: Date())
    }

    var playingText: String? {
        guard let playing, playing > 0 else { return nil }
        return "\(compactNumber(playing)) playing now"
    }
}

/// The account that last joined a game on this Mac, from the join ticket in the logs.
struct RobloxPlayer: Codable, Equatable {
    let userId: Int64
    let displayName: String
    var avatarURL: URL?
}

func compactNumber(_ n: Int) -> String {
    func short(_ value: Double, _ suffix: String) -> String {
        let text = String(format: value >= 100 ? "%.0f" : "%.1f", value)
        return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + suffix
    }
    if n >= 1_000_000 { return short(Double(n) / 1_000_000, "M") }
    if n >= 1_000 { return short(Double(n) / 1_000, "K") }
    return "\(n)"
}

/// Recently played experiences and the player's avatar. Everything is read
/// from Roblox's own log files; names, player counts and pictures come from
/// Roblox's public web APIs.
///
/// Background work only reads snapshots; all published state is changed on
/// the main queue, which is why the unchecked Sendable is safe.
final class GameLibrary: ObservableObject, @unchecked Sendable {
    @Published private(set) var games: [RecentGame] = []
    @Published private(set) var player: RobloxPlayer?
    @Published private(set) var refreshing = false
    /// The game a website link is joining, shown in the link window.
    @Published private(set) var linkGame: RecentGame?
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "showRecentGames")
            if enabled { refresh() } else { clear() }
        }
    }

    private let cacheURL: URL
    private let logsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Roblox")
    private static let maxGames = 12

    init(supportURL: URL) {
        cacheURL = supportURL.appendingPathComponent("recent-games.json")
        UserDefaults.standard.register(defaults: ["showRecentGames": true])
        enabled = UserDefaults.standard.bool(forKey: "showRecentGames")
        if enabled { loadCache() }
    }

    // MARK: - Refresh

    func refresh() {
        guard enabled, !refreshing else { return }
        refreshing = true
        let logs = logsURL
        let cached = games
        let cachedPlayer = player
        Task.detached(priority: .utility) {
            let scan = Self.scanLogs(in: logs)
            let merged = Self.merge(scan: scan, cached: cached)
            let scanned = scan.player.map {
                RobloxPlayer(userId: $0.userId, displayName: $0.displayName,
                             avatarURL: $0.userId == cachedPlayer?.userId ? cachedPlayer?.avatarURL : nil)
            }
            let current = scanned ?? cachedPlayer
            DispatchQueue.main.async { self.publish(games: merged, player: current, done: false) }

            let detailed = await Self.fetchDetails(for: merged)
            var withAvatar = current
            if let p = current, p.avatarURL == nil {
                withAvatar?.avatarURL = await Self.fetchAvatar(userId: p.userId)
            }
            let finalPlayer = withAvatar
            DispatchQueue.main.async { self.publish(games: detailed, player: finalPlayer, done: true) }
        }
    }

    private func publish(games: [RecentGame], player: RobloxPlayer?, done: Bool) {
        if done { refreshing = false }
        guard enabled else { return }
        self.games = games
        self.player = player
        if done { saveCache() }
    }

    private func clear() {
        games = []
        player = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }

    /// Looks up the name and icon for a place a website link is joining.
    func lookUpLinkGame(link: String) {
        guard enabled, let placeId = Self.placeId(inLink: link) else { return }
        if let known = games.first(where: { $0.placeId == placeId }) {
            linkGame = known
            return
        }
        Task.detached(priority: .userInitiated) {
            let game = await Self.fetchDetails(for: [RecentGame(placeId: placeId, lastPlayed: Date())]).first
            DispatchQueue.main.async { self.linkGame = game }
        }
    }

    static func placeId(inLink link: String) -> Int64? {
        let decoded = link.removingPercentEncoding ?? link
        guard let regex = try? NSRegularExpression(pattern: #"placeId[=:](\d+)"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)),
              let range = Range(match.range(at: 1), in: decoded)
        else { return nil }
        return Int64(decoded[range])
    }

    // MARK: - Cache

    private struct Cache: Codable {
        var games: [RecentGame]
        var player: RobloxPlayer?
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        games = cache.games
        player = cache.player
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(Cache(games: games, player: player)) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - Logs

    private struct Visit {
        let placeId: Int64
        let date: Date
    }

    private struct Scan {
        var visits: [Visit] = []
        var universes: [Int64: Int64] = [:]
        var player: (userId: Int64, displayName: String, date: Date)?
    }

    private static func scanLogs(in directory: URL) -> Scan {
        var scan = Scan()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return scan }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let logs = files.filter { $0.pathExtension == "log" }.sorted { modified($0) > modified($1) }.prefix(80)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // e.g. "2026-09-25T15:13:55.164Z,77.16,6d553000,6 [FLog::Output] ! Joining game '<job>' place 7041939546 at <address>"
        let join = try! NSRegularExpression(pattern: #"^(\S+?),[^\n]*! Joining game '[^']*' place (\d+)"#, options: .anchorsMatchLines)
        let user = try! NSRegularExpression(pattern: #""UserId":(\d+),"UserName":"[^"]*","DisplayName":"([^"]*)""#)
        let universe = try! NSRegularExpression(pattern: #""PlaceId":(\d+),"UniverseId":(\d+)"#)

        for file in logs {
            guard let data = try? Data(contentsOf: file) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            let ns = text as NSString
            for m in join.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let place = Int64(ns.substring(with: m.range(at: 2))) else { continue }
                let date = iso.date(from: ns.substring(with: m.range(at: 1))) ?? modified(file)
                scan.visits.append(Visit(placeId: place, date: date))
            }
            // The join ticket is URL-encoded JSON inside a longer line.
            for line in text.split(separator: "\n") where line.contains("UniverseId") {
                let decoded = decodeTicket(String(line))
                let lineNS = decoded as NSString
                let range = NSRange(location: 0, length: lineNS.length)
                for m in universe.matches(in: decoded, range: range) {
                    if let place = Int64(lineNS.substring(with: m.range(at: 1))),
                       let uni = Int64(lineNS.substring(with: m.range(at: 2))) {
                        scan.universes[place] = uni
                    }
                }
                if let m = user.firstMatch(in: decoded, range: range),
                   let id = Int64(lineNS.substring(with: m.range(at: 1))) {
                    let prefix = String(line.prefix(while: { $0 != "," }))
                    let date = iso.date(from: prefix) ?? modified(file)
                    if scan.player == nil || date > scan.player!.date {
                        scan.player = (id, lineNS.substring(with: m.range(at: 2)), date)
                    }
                }
            }
        }
        return scan
    }

    private static func decodeTicket(_ line: String) -> String {
        let unescaped = line.replacingOccurrences(of: "\\", with: "")
        if let decoded = unescaped.removingPercentEncoding { return decoded }
        var text = unescaped
        for (code, char) in [("%3a", ":"), ("%2c", ","), ("%22", "\""), ("%2f", "/"), ("%3d", "="), ("%26", "&"), ("%3f", "?")] {
            text = text.replacingOccurrences(of: code, with: char, options: .caseInsensitive)
        }
        return text
    }

    /// Newest visit per experience, reusing details already fetched.
    private static func merge(scan: Scan, cached: [RecentGame]) -> [RecentGame] {
        var byPlace: [Int64: RecentGame] = [:]
        for visit in scan.visits {
            if let existing = byPlace[visit.placeId], existing.lastPlayed >= visit.date { continue }
            var game = cached.first { $0.placeId == visit.placeId } ?? RecentGame(placeId: visit.placeId, lastPlayed: visit.date)
            game.lastPlayed = visit.date
            if game.universeId == nil { game.universeId = scan.universes[visit.placeId] }
            byPlace[visit.placeId] = game
        }
        // Keep older cached games (logs get cleaned up) below the fresh ones.
        for game in cached where byPlace[game.placeId] == nil {
            byPlace[game.placeId] = game
        }
        var seenUniverses = Set<Int64>()
        return byPlace.values
            .sorted { $0.lastPlayed > $1.lastPlayed }
            .filter { game in
                guard let uni = game.universeId else { return true }
                return seenUniverses.insert(uni).inserted
            }
            .prefix(maxGames)
            .map { $0 }
    }

    // MARK: - Roblox web APIs

    private struct Thumbnails: Decodable {
        struct Item: Decodable {
            let targetId: Int64
            let imageUrl: String?
        }
        let data: [Item]
    }

    private struct WideThumbnails: Decodable {
        struct Item: Decodable {
            let universeId: Int64
            let thumbnails: [Thumbnails.Item]
        }
        let data: [Item]
    }

    private struct Games: Decodable {
        struct Game: Decodable {
            let id: Int64
            let name: String
            let playing: Int?
        }
        let data: [Game]
    }

    private struct Universe: Decodable {
        let universeId: Int64?
    }

    private static func get<T: Decodable>(_ type: T.Type, _ url: String) async -> T? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func fetchDetails(for games: [RecentGame]) async -> [RecentGame] {
        var games = games
        for i in games.indices where games[i].universeId == nil {
            games[i].universeId = await get(Universe.self, "https://apis.roblox.com/universes/v1/places/\(games[i].placeId)/universe")?.universeId
        }
        let ids = Array(Set(games.compactMap(\.universeId)))
        guard !ids.isEmpty else { return games }
        let list = ids.map(String.init).joined(separator: ",")

        async let info = get(Games.self, "https://games.roblox.com/v1/games?universeIds=\(list)")
        async let icons = get(Thumbnails.self, "https://thumbnails.roblox.com/v1/games/icons?universeIds=\(list)&returnPolicy=PlaceHolder&size=256x256&format=Png&isCircular=false")
        async let art = get(WideThumbnails.self, "https://thumbnails.roblox.com/v1/games/multiget/thumbnails?universeIds=\(list)&countPerUniverse=1&defaults=true&size=768x432&format=Png&isCircular=false")
        let (infoResult, iconResult, artResult) = await (info, icons, art)

        for i in games.indices {
            guard let uni = games[i].universeId else { continue }
            if let game = infoResult?.data.first(where: { $0.id == uni }) {
                games[i].name = game.name
                games[i].playing = game.playing
            }
            if let icon = iconResult?.data.first(where: { $0.targetId == uni })?.imageUrl {
                games[i].iconURL = URL(string: icon)
            }
            if let wide = artResult?.data.first(where: { $0.universeId == uni })?.thumbnails.first?.imageUrl {
                games[i].artURL = URL(string: wide)
            }
        }
        return games
    }

    private static func fetchAvatar(userId: Int64) async -> URL? {
        let result = await get(Thumbnails.self, "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=\(userId)&size=150x150&format=Png&isCircular=false")
        return result?.data.first?.imageUrl.flatMap(URL.init(string:))
    }
}

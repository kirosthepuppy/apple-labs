import AppKit
import CoreServices
import Foundation

/// A FastFlag value, typed the same way `roblox-bootstrapper fflags set` does.
enum FlagValue: Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    init(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed == "true" { self = .bool(true) }
        else if trimmed == "false" { self = .bool(false) }
        else if let n = Int(trimmed) { self = .int(n) }
        else { self = .string(text) }
    }

    init?(json: Any) {
        if let n = json as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else if CFNumberIsFloatType(n) { self = .double(n.doubleValue) }
            else { self = .int(n.intValue) }
        } else if let s = json as? String {
            self = .string(s)
        } else {
            return nil
        }
    }

    var text: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .int(let n): return String(n)
        case .double(let d): return String(d)
        case .string(let s): return s
        }
    }

    var json: Any {
        switch self {
        case .bool(let b): return b
        case .int(let n): return n
        case .double(let d): return d
        case .string(let s): return s
        }
    }
}

enum DeathSound: String, CaseIterable, Identifiable {
    case standard, classic, custom
    var id: String { rawValue }
}

enum CursorStyle: String, CaseIterable, Identifiable {
    case standard, classic, custom
    var id: String { rawValue }
}

/// State shared by every screen. All mutation happens on the main thread.
final class LauncherModel: ObservableObject {
    static let robloxBundleID = "com.roblox.RobloxPlayer"
    static let schemes = ["roblox-player", "roblox"]

    @Published var status: BootstrapperStatus?
    @Published var busy = false
    @Published var stage = ""
    @Published var progress: Double?
    @Published var errorMessage: String?
    @Published var robloxRunning = false
    /// Flags or mods changed while Roblox was open.
    @Published var needsRestart = false
    @Published var flags: [String: FlagValue] = [:]
    @Published var flagsError: String?
    /// Bumped whenever the mods folder changes so views re-read it.
    @Published var modsRevision = 0
    @Published var isLinkHandler = false

    @Published var closeOnLaunch: Bool {
        didSet { UserDefaults.standard.set(closeOnLaunch, forKey: "closeOnLaunch") }
    }
    @Published var theme: LauncherTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    @Published var animatedBackground: Bool {
        didSet { UserDefaults.standard.set(animatedBackground, forKey: "animatedBackground") }
    }
    @Published var showStuds: Bool {
        didSet { UserDefaults.standard.set(showStuds, forKey: "showStuds") }
    }
    @Published var celebrateLaunches: Bool {
        didSet { UserDefaults.standard.set(celebrateLaunches, forKey: "celebrateLaunches") }
    }
    /// Bumped after each successful launch to fire the confetti.
    @Published var celebrations = 0
    /// Fonts installed on this Mac that Roblox can load (.ttf/.otf).
    @Published var macFonts: [MacFont] = []
    /// Called a moment after Roblox quits, e.g. to pick up new games from its logs.
    var onRobloxExit: (() -> Void)?

    private var process: Process?
    private var observers: [NSObjectProtocol] = []

    let supportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RobloxBootstrapper", isDirectory: true)
    }()
    var fflagsURL: URL { supportURL.appendingPathComponent("fflags.json") }
    var modsURL: URL { supportURL.appendingPathComponent("Modifications", isDirectory: true) }
    var logURL: URL { supportURL.appendingPathComponent("bootstrapper.log") }

    var robloxAppURL: URL {
        URL(fileURLWithPath: status?.installPath ?? "/Applications/Roblox.app")
    }

    init() {
        UserDefaults.standard.register(defaults: ["closeOnLaunch": true, "animatedBackground": true,
                                                  "showStuds": true, "celebrateLaunches": true])
        closeOnLaunch = UserDefaults.standard.bool(forKey: "closeOnLaunch")
        theme = LauncherTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .sunset
        animatedBackground = UserDefaults.standard.bool(forKey: "animatedBackground")
        showStuds = UserDefaults.standard.bool(forKey: "showStuds")
        celebrateLaunches = UserDefaults.standard.bool(forKey: "celebrateLaunches")
        try? FileManager.default.createDirectory(at: modsURL, withIntermediateDirectories: true)
        loadFlags()
        refreshRunning()
        refreshLinkHandler()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.robloxBundleID else { return }
                self?.refreshRunning()
            })
        }
    }

    // MARK: - Status

    func refreshStatus() {
        ScriptRunner.run(["status", "--json"], completion: { [weak self] result in
            guard let self, result.succeeded,
                  let data = result.output.data(using: .utf8),
                  let status = try? JSONDecoder().decode(BootstrapperStatus.self, from: data)
            else { return }
            self.status = status
        })
    }

    func refreshRunning() {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.robloxBundleID && !$0.isTerminated
        }
        if robloxRunning && !running {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.onRobloxExit?() }
        }
        robloxRunning = running
        if !running { needsRestart = false }
    }

    // MARK: - Tasks

    /// Runs a long script command, feeding its output into `stage`/`progress`.
    func runTask(_ args: [String], title: String, completion: ((Bool) -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        stage = title
        progress = nil
        process = ScriptRunner.run(args, onLine: { [weak self] line in
            self?.handle(line: line)
        }, completion: { [weak self] result in
            guard let self else { return }
            self.busy = false
            self.process = nil
            self.progress = nil
            if !result.succeeded {
                self.errorMessage = result.errorMessage ?? "Something went wrong (exit code \(result.status))."
            }
            self.refreshStatus()
            self.refreshRunning()
            completion?(result.succeeded)
        })
    }

    private func handle(line: String) {
        if line.hasPrefix("@progress ") {
            if let pct = Double(line.dropFirst("@progress ".count)) {
                progress = min(max(pct / 100, 0), 1)
            }
        } else if line.hasPrefix("==> ") {
            stage = String(line.dropFirst(4))
            if !stage.hasPrefix("Downloading") { progress = nil }
        } else if line.hasPrefix("✓ ") {
            stage = String(line.dropFirst(2))
        }
    }

    func cancel() {
        process?.terminate()
    }

    /// Update if needed, apply flags and mods, then start Roblox (optionally
    /// joining the game in `url`).
    func launch(url: String? = nil, quitAfter: Bool = false) {
        var args = ["launch"]
        if let url { args.append(url) }
        runTask(args, title: url == nil ? "Starting Roblox" : "Joining game") { [weak self] ok in
            guard let self, ok else { return }
            self.stage = url == nil ? "Roblox started" : "Joining game"
            if self.celebrateLaunches { self.celebrations += 1 }
            if quitAfter || self.closeOnLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { NSApp.terminate(nil) }
            }
        }
    }

    func checkForUpdates() {
        runTask(["install"], title: "Checking for updates")
    }

    func reinstall() {
        runTask(["install", "--force"], title: "Reinstalling Roblox")
    }

    /// Quit Roblox, wait for it to exit, then launch again through the script.
    func restartRoblox() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == Self.robloxBundleID }
        apps.forEach { $0.terminate() }
        busy = true
        stage = "Closing Roblox"
        waitForRobloxToExit(attempts: 50) { [weak self] in
            guard let self else { return }
            self.busy = false
            self.refreshRunning()
            self.needsRestart = false
            self.launch()
        }
    }

    private func waitForRobloxToExit(attempts: Int, then done: @escaping () -> Void) {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.robloxBundleID && !$0.isTerminated
        }
        if !running || attempts == 0 { done(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForRobloxToExit(attempts: attempts - 1, then: done)
        }
    }

    // MARK: - FastFlags

    func loadFlags() {
        guard let data = try? Data(contentsOf: fflagsURL), !data.isEmpty else {
            flags = [:]
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            flagsError = "fflags.json is not valid JSON. Fix or clear it before editing flags here."
            return
        }
        flagsError = nil
        flags = object.compactMapValues(FlagValue.init(json:))
    }

    func setFlag(_ name: String, _ value: FlagValue?) {
        var updated = flags
        updated[name] = value
        saveFlags(updated)
    }

    func setFlags(_ changes: [String: FlagValue?]) {
        var updated = flags
        for (name, value) in changes { updated[name] = value }
        saveFlags(updated)
    }

    func replaceFlags(_ newFlags: [String: FlagValue]) {
        saveFlags(newFlags)
    }

    private func saveFlags(_ newFlags: [String: FlagValue]) {
        flags = newFlags
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            let object = newFlags.mapValues(\.json)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fflagsURL, options: .atomic)
            flagsError = nil
        } catch {
            flagsError = "Could not save flags: \(error.localizedDescription)"
            return
        }
        applyQuietly(["fflags", "apply"])
    }

    /// Merges a JSON object of flags (e.g. copied from Bloxstrap) into ours.
    func importFlags(json text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "That isn't a JSON object like {\"FlagName\": value}." }
        var updated = flags
        for (key, value) in object {
            if let v = FlagValue(json: value) { updated[key] = v }
        }
        saveFlags(updated)
        return nil
    }

    func exportFlagsJSON() -> String {
        let object = flags.mapValues(\.json)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Mods

    func modURL(_ relative: String) -> URL { modsURL.appendingPathComponent(relative) }
    func robloxResource(_ relative: String) -> URL {
        robloxAppURL.appendingPathComponent("Contents/Resources").appendingPathComponent(relative)
    }

    static let deathSoundPath = "content/sounds/ouch.ogg"
    static let cursorPaths = [
        "content/textures/Cursors/KeyboardMouse/ArrowCursor.png",
        "content/textures/Cursors/KeyboardMouse/ArrowFarCursor.png",
    ]
    static let classicCursorSources = [
        "content/textures/ArrowCursor.png",
        "content/textures/ArrowFarCursor.png",
    ]
    static let fontPaths = ["content/fonts/CustomFont.ttf", "content/fonts/CustomFont.otf"]

    var deathSound: DeathSound {
        let mod = modURL(Self.deathSoundPath)
        guard FileManager.default.fileExists(atPath: mod.path) else { return .standard }
        let oof = robloxResource("content/sounds/oof.ogg")
        return FileManager.default.contentsEqual(atPath: mod.path, andPath: oof.path) ? .classic : .custom
    }

    var cursorStyle: CursorStyle {
        let mod = modURL(Self.cursorPaths[0])
        guard FileManager.default.fileExists(atPath: mod.path) else { return .standard }
        // The top-level textures are never modded, so Roblox's copy is the reference.
        let classic = robloxResource(Self.classicCursorSources[0])
        return FileManager.default.contentsEqual(atPath: mod.path, andPath: classic.path) ? .classic : .custom
    }

    var customFontName: String? {
        guard Self.fontPaths.contains(where: { FileManager.default.fileExists(atPath: modURL($0).path) })
        else { return nil }
        return UserDefaults.standard.string(forKey: "customFontName") ?? "Custom font"
    }

    var modFileCount: Int {
        guard let e = FileManager.default.enumerator(at: modsURL, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var count = 0
        for case let url as URL in e where url.lastPathComponent != ".DS_Store" {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { count += 1 }
        }
        return count
    }

    func setDeathSound(_ choice: DeathSound, file: URL? = nil) {
        let dest = modURL(Self.deathSoundPath)
        switch choice {
        case .standard: removeMod(dest)
        case .classic: installMod(from: robloxResource("content/sounds/oof.ogg"), to: dest)
        case .custom: if let file { installMod(from: file, to: dest) }
        }
        modsChanged()
    }

    func setCursor(_ choice: CursorStyle, image: URL? = nil) {
        switch choice {
        case .standard:
            Self.cursorPaths.forEach { removeMod(modURL($0)) }
        case .classic:
            for (src, dst) in zip(Self.classicCursorSources, Self.cursorPaths) {
                installMod(from: robloxResource(src), to: modURL(dst))
            }
        case .custom:
            guard let image, let png = Self.cursorPNG(from: image) else {
                errorMessage = "Could not read that image."
                return
            }
            for dst in Self.cursorPaths {
                let url = modURL(dst)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? png.write(to: url, options: .atomic)
            }
        }
        modsChanged()
    }

    func setFont(_ file: URL?, name: String? = nil) {
        Self.fontPaths.forEach { removeMod(modURL($0)) }
        if let file {
            let ext = file.pathExtension.lowercased() == "otf" ? "otf" : "ttf"
            installMod(from: file, to: modURL("content/fonts/CustomFont.\(ext)"))
            UserDefaults.standard.set(name ?? Self.familyName(of: file) ?? file.deletingPathExtension().lastPathComponent,
                                      forKey: "customFontName")
        }
        modsChanged()
    }

    /// The installed custom font file, if any.
    var customFontURL: URL? {
        Self.fontPaths.map(modURL).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func clearMods() {
        applyQuietly(["mods", "clear"]) { [weak self] in self?.modsRevision += 1 }
        needsRestart = robloxRunning
    }

    func applyMods() { modsChanged() }

    private func installMod(from source: URL, to dest: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
        } catch {
            errorMessage = "Could not add mod: \(error.localizedDescription)"
        }
    }

    private func removeMod(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func modsChanged() {
        modsRevision += 1
        applyQuietly(["mods", "apply"])
    }

    /// Scales an image to Roblox's 64x64 cursor size.
    private static func cursorPNG(from url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let size = 64
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Runs a quick command without the progress UI and notes when Roblox
    /// needs a restart to pick the change up.
    private func applyQuietly(_ args: [String], then done: (() -> Void)? = nil) {
        ScriptRunner.run(args, completion: { [weak self] result in
            guard let self else { return }
            if !result.succeeded {
                self.errorMessage = result.errorMessage
            } else if self.robloxRunning {
                self.needsRestart = true
            }
            done?()
        })
    }

    // MARK: - Settings

    func setConfig(_ key: String, _ value: String) {
        ScriptRunner.run(["config", "set", key, value], completion: { [weak self] result in
            if !result.succeeded { self?.errorMessage = result.errorMessage }
            self?.refreshStatus()
        })
    }

    func refreshLinkHandler() {
        guard let url = URL(string: "roblox-player://"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url)
        else { isLinkHandler = false; return }
        isLinkHandler = handler.standardizedFileURL.path == Bundle.main.bundleURL.standardizedFileURL.path
            || Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    func setLinkHandler(_ enabled: Bool) {
        let target = (enabled ? Bundle.main.bundleIdentifier : Self.robloxBundleID) ?? Self.robloxBundleID
        for scheme in Self.schemes {
            LSSetDefaultHandlerForURLScheme(scheme as CFString, target as CFString)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refreshLinkHandler() }
    }
}

import AppKit
import CoreImage
import CoreServices
import Foundation
import SwiftUI

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

struct ModsSnapshot {
    var deathSound = DeathSound.standard
    var cursorStyle = CursorStyle.standard
    var customFontURL: URL?
    var customFontName: String?
    var fileCount = 0
    var extraCount = 0
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
    @Published var themeID: ThemeID {
        didSet { UserDefaults.standard.set(themeID.rawValue, forKey: "themeID") }
    }
    /// The colours of the Custom theme, kept even while another theme is in use.
    @Published var customTheme: Theme {
        didSet {
            let d = UserDefaults.standard
            d.set(customTheme.accent.hex, forKey: "customAccent")
            d.set(customTheme.base.hex, forKey: "customBase")
            d.set(customTheme.heroGlow.hex, forKey: "customHero")
            d.set(customTheme.glows.map(\.hex), forKey: "customGlows")
        }
    }
    @Published var launcherFont: LauncherFont {
        didSet {
            LauncherFont.current = launcherFont
            UserDefaults.standard.set(launcherFont.rawValue, forKey: "launcherFont")
        }
    }
    /// How big the whole interface is drawn, 0.8–1.3.
    @Published var uiScale: Double {
        didSet {
            let clamped = min(max((uiScale * 20).rounded() / 20, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
            // Assigning inside didSet doesn't re-run it, so save afterwards either way.
            if clamped != uiScale { uiScale = clamped }
            UserDefaults.standard.set(uiScale, forKey: "uiScale")
        }
    }
    static let scaleRange: ClosedRange<Double> = 0.8...1.3
    @Published var animatedBackground: Bool {
        didSet { UserDefaults.standard.set(animatedBackground, forKey: "animatedBackground") }
    }
    @Published var showStuds: Bool {
        didSet { UserDefaults.standard.set(showStuds, forKey: "showStuds") }
    }
    @Published var celebrateLaunches: Bool {
        didSet { UserDefaults.standard.set(celebrateLaunches, forKey: "celebrateLaunches") }
    }
    /// A picture shown behind the launcher while the Custom theme is on.
    @Published private(set) var backgroundImage: NSImage?
    /// How much the background picture is darkened, 0–0.8.
    @Published var backgroundDim: Double {
        didSet { UserDefaults.standard.set(backgroundDim, forKey: "backgroundDim") }
    }
    @Published var backgroundBlur: Bool {
        didSet {
            UserDefaults.standard.set(backgroundBlur, forKey: "backgroundBlur")
            loadBackgroundImage()
        }
    }
    /// Bumped after each successful launch to fire the confetti.
    @Published var celebrations = 0
    /// Fonts installed on this Mac that Roblox can load (.ttf/.otf).
    @Published var macFonts: [MacFont] = []
    /// Called a moment after Roblox quits, e.g. to pick up new games from its logs.
    var onRobloxExit: (() -> Void)?

    private var process: Process?
    private var modsCache: (key: String, snapshot: ModsSnapshot)?
    private var modsReadGeneration = 0
    private var observers: [NSObjectProtocol] = []
    private var runningPoll: Timer?

    let supportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RobloxBootstrapper", isDirectory: true)
    }()
    var fflagsURL: URL { supportURL.appendingPathComponent("fflags.json") }
    var modsURL: URL { supportURL.appendingPathComponent("Modifications", isDirectory: true) }
    var logURL: URL { supportURL.appendingPathComponent("bootstrapper.log") }

    /// The theme in use, with the Custom theme's saved colours filled in.
    var theme: Theme { themeID == .custom ? customTheme : .preset(themeID) }

    func zoom(by step: Double) { uiScale = min(max(uiScale + step, Self.scaleRange.lowerBound), Self.scaleRange.upperBound) }

    var robloxAppURL: URL {
        URL(fileURLWithPath: status?.installPath ?? "/Applications/Roblox.app")
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["closeOnLaunch": false, "animatedBackground": true,
                              "showStuds": true, "celebrateLaunches": true, "uiScale": 1.0,
                              "backgroundDim": 0.35, "backgroundBlur": false])
        // The launcher used to close itself once Roblox started; it stays open now.
        if !d.bool(forKey: "stayOpenMigrated") {
            d.set(false, forKey: "closeOnLaunch")
            d.set(true, forKey: "stayOpenMigrated")
        }
        closeOnLaunch = d.bool(forKey: "closeOnLaunch")
        themeID = ThemeID(rawValue: d.string(forKey: "themeID") ?? "") ?? .obsidian
        var custom = Theme.preset(.custom)
        if let accent = d.string(forKey: "customAccent").flatMap(Color.init(hex:)) { custom.accent = accent }
        if let base = d.string(forKey: "customBase").flatMap(Color.init(hex:)) { custom.base = base }
        if let hero = d.string(forKey: "customHero").flatMap(Color.init(hex:)) { custom.heroGlow = hero }
        if let glows = d.stringArray(forKey: "customGlows")?.compactMap(Color.init(hex:)), glows.count == 3 {
            custom.glows = glows
        }
        customTheme = custom
        let font = LauncherFont(rawValue: d.string(forKey: "launcherFont") ?? "") ?? .avenir
        launcherFont = font
        LauncherFont.current = font
        uiScale = d.double(forKey: "uiScale")
        animatedBackground = UserDefaults.standard.bool(forKey: "animatedBackground")
        showStuds = UserDefaults.standard.bool(forKey: "showStuds")
        celebrateLaunches = UserDefaults.standard.bool(forKey: "celebrateLaunches")
        backgroundDim = d.double(forKey: "backgroundDim")
        backgroundBlur = d.bool(forKey: "backgroundBlur")
        try? FileManager.default.createDirectory(at: modsURL, withIntermediateDirectories: true)
        loadFlags()
        loadBackgroundImage()
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
        // Roblox can start itself in the menu bar at login without those
        // notifications reaching us, so also look every few seconds.
        runningPoll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshRunning() }
        runningPoll?.tolerance = 1
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
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Self.robloxBundleID && !$0.isTerminated
        }
        let running = !apps.isEmpty
        if robloxRunning && !running {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.onRobloxExit?() }
        }
        // Only publish changes: this runs every few seconds.
        if robloxRunning != running { robloxRunning = running }
        let stale = running && robloxHasOldSettings(apps)
        if needsRestart != stale { needsRestart = stale }
    }

    /// Roblox reads FastFlags and mods only when it starts. It's out of date
    /// when they were written after the oldest running copy started, e.g. a
    /// Roblox sitting in the menu bar since login.
    private func robloxHasOldSettings(_ apps: [NSRunningApplication]) -> Bool {
        guard let started = apps.compactMap({ $0.launchDate ?? Self.processStart($0.processIdentifier) }).min() else { return false }
        let written = [
            robloxAppURL.appendingPathComponent("Contents/MacOS/ClientSettings/ClientAppSettings.json"),
            supportURL.appendingPathComponent("mods-applied"),
        ].compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        return written.contains { $0 > started }
    }

    private static func processStart(_ pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    // MARK: - Background image

    /// The saved copy of the chosen background picture, if any.
    private var backgroundFileURL: URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: supportURL, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == "Background" }
    }

    /// Copies `file` into the launcher's folder and shows it, or removes the
    /// picture when `file` is nil.
    func setBackgroundImage(_ file: URL?) {
        let fm = FileManager.default
        if let old = backgroundFileURL { try? fm.removeItem(at: old) }
        if let file {
            let dest = supportURL.appendingPathComponent("Background").appendingPathExtension(file.pathExtension.lowercased())
            do {
                try fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
                try fm.copyItem(at: file, to: dest)
            } catch {
                errorMessage = "Could not use that picture: \(error.localizedDescription)"
            }
        }
        loadBackgroundImage()
    }

    /// Decodes, shrinks and (optionally) blurs the picture off the main
    /// thread, so it is prepared once rather than on every redraw.
    private func loadBackgroundImage() {
        guard let url = backgroundFileURL else {
            backgroundImage = nil
            return
        }
        let blur = backgroundBlur
        DispatchQueue.global(qos: .userInitiated).async {
            let image = Self.prepareBackground(url, blur: blur)
            DispatchQueue.main.async {
                // A newer choice may have landed while this one was decoding.
                guard self.backgroundFileURL == url, self.backgroundBlur == blur else { return }
                if image == nil { self.errorMessage = "Could not read that picture." }
                self.backgroundImage = image
            }
        }
    }

    private static func prepareBackground(_ url: URL, blur: Bool) -> NSImage? {
        guard var image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
        let longest = max(image.extent.width, image.extent.height)
        if longest > 2560 {
            let scale = 2560 / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let extent = image.extent
        if blur {
            image = image.clampedToExtent().applyingGaussianBlur(sigma: 28).cropped(to: extent)
        }
        guard let cg = CIContext().createCGImage(image, from: extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: extent.width, height: extent.height))
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
        // Only publish real changes: every publish redraws the whole window,
        // and downloads report progress many times per percent.
        if line.hasPrefix("@progress ") {
            if let pct = Double(line.dropFirst("@progress ".count)) {
                let value = min(max(pct.rounded() / 100, 0), 1)
                if value != progress { progress = value }
            }
        } else if line.hasPrefix("==> ") {
            let next = String(line.dropFirst(4))
            if next != stage { stage = next }
            if !stage.hasPrefix("Downloading") && progress != nil { progress = nil }
        } else if line.hasPrefix("✓ ") {
            let next = String(line.dropFirst(2))
            if next != stage { stage = next }
        }
    }

    func cancel() {
        process?.terminate()
    }

    /// Update if needed, apply flags and mods, then start Roblox (optionally
    /// joining the game in `url`).
    func launch(url: String? = nil, quitAfter: Bool = false) {
        refreshRunning()
        if robloxRunning && needsRestart && !busy {
            // A running Roblox keeps the settings it started with; restart it so
            // the new FastFlags and mods apply.
            quitRoblox { [weak self] in self?.startLaunch(url: url, quitAfter: quitAfter) }
            return
        }
        startLaunch(url: url, quitAfter: quitAfter)
    }

    private func startLaunch(url: String?, quitAfter: Bool) {
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
        quitRoblox { [weak self] in
            self?.needsRestart = false
            self?.launch()
        }
    }

    /// Asks Roblox to quit and calls `done` once it has (or after ~10 seconds).
    func quitRoblox(then done: @escaping () -> Void) {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == Self.robloxBundleID }
        guard !apps.isEmpty else { done(); return }
        apps.forEach { $0.terminate() }
        busy = true
        stage = needsRestart ? "Restarting Roblox to apply your settings" : "Closing Roblox"
        waitForRobloxToExit(attempts: 50) { [weak self] in
            guard let self else { return }
            // Roblox in the menu bar sometimes ignores a polite quit.
            let stuck = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == Self.robloxBundleID && !$0.isTerminated }
            stuck.forEach { $0.forceTerminate() }
            self.waitForRobloxToExit(attempts: stuck.isEmpty ? 0 : 15) {
                self.busy = false
                self.refreshRunning()
                done()
            }
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
        // Earlier versions set a few flags Roblox has since stopped reading; drop them once.
        if !UserDefaults.standard.bool(forKey: "retiredFlagsRemoved") {
            UserDefaults.standard.set(true, forKey: "retiredFlagsRemoved")
            if Self.retiredFlags.contains(where: { flags[$0] != nil }) {
                var cleaned = flags
                Self.retiredFlags.forEach { cleaned[$0] = nil }
                saveFlags(cleaned)
            }
        }
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

    var deathSound: DeathSound { modsSnapshot.deathSound }
    var cursorStyle: CursorStyle { modsSnapshot.cursorStyle }
    var customFontName: String? { modsSnapshot.customFontName }
    var modFileCount: Int { modsSnapshot.fileCount }
    /// Files in the mods folder that aren't managed by the Style page.
    var extraModCount: Int { modsSnapshot.extraCount }
    /// The installed custom font file, if any.
    var customFontURL: URL? { modsSnapshot.customFontURL }

    /// What's in the mods folder. Reading it means walking the folder and
    /// comparing files, so it's done once per change rather than on every redraw.
    private var modsSnapshot: ModsSnapshot {
        let key = "\(modsRevision)|\(status?.installPath ?? "")|\(status?.installed ?? "")|\(modsReadGeneration)"
        if let cached = modsCache, cached.key == key { return cached.snapshot }
        let snapshot = readMods()
        modsCache = (key, snapshot)
        return snapshot
    }

    /// Forgets the cached mods folder contents, e.g. after the user may have
    /// changed it in Finder.
    func rereadMods() {
        modsReadGeneration += 1
        objectWillChange.send()
    }

    private func readMods() -> ModsSnapshot {
        let fm = FileManager.default
        var snapshot = ModsSnapshot()

        let sound = modURL(Self.deathSoundPath)
        if fm.fileExists(atPath: sound.path) {
            let oof = robloxResource("content/sounds/oof.ogg")
            snapshot.deathSound = fm.contentsEqual(atPath: sound.path, andPath: oof.path) ? .classic : .custom
        }

        let cursor = modURL(Self.cursorPaths[0])
        if fm.fileExists(atPath: cursor.path) {
            // The top-level textures are never modded, so Roblox's copy is the reference.
            let classic = robloxResource(Self.classicCursorSources[0])
            snapshot.cursorStyle = fm.contentsEqual(atPath: cursor.path, andPath: classic.path) ? .classic : .custom
        }

        snapshot.customFontURL = Self.fontPaths.map(modURL).first { fm.fileExists(atPath: $0.path) }
        if snapshot.customFontURL != nil {
            snapshot.customFontName = UserDefaults.standard.string(forKey: "customFontName") ?? "Custom font"
        }

        let known = Set([Self.deathSoundPath] + Self.cursorPaths + Self.fontPaths)
        if let e = fm.enumerator(at: modsURL, includingPropertiesForKeys: [.isRegularFileKey]) {
            let base = modsURL.standardizedFileURL.path + "/"
            for case let url as URL in e where url.lastPathComponent != ".DS_Store" {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                snapshot.fileCount += 1
                let rel = url.standardizedFileURL.path.replacingOccurrences(of: base, with: "")
                if !known.contains(rel) { snapshot.extraCount += 1 }
            }
        }
        return snapshot
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

    func clearMods() {
        applyQuietly(["mods", "clear"]) { [weak self] in self?.modsRevision += 1 }
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
            }
            self.refreshRunning()
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

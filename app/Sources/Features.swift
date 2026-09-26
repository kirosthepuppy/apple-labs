import AppKit
import CoreText
import SwiftUI

struct MacFont: Identifiable, Hashable {
    let family: String
    let postScriptName: String
    let url: URL
    var id: String { family }
}

/// A one-click bundle of engine FastFlags.
struct GraphicsPreset: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let blurb: String
    let highlights: [String]
    /// 1–5 ratings shown as meters on the preset cards.
    let speed: Int
    let looks: Int
    let flags: [String: FlagValue]
}

/// One entry in the Play page's "Your loadout" strip.
struct LoadoutItem: Identifiable {
    enum Destination {
        case graphics(GraphicsTab)
        case style(StyleTab)
    }

    let id: String
    let symbol: String
    let text: String
    let active: Bool
    let destination: Destination
}

/// The launcher's overall state, shown in the status pills.
enum LauncherState: Equatable {
    case checking, notInstalled, updateReady, ready, working, playing, failed

    var label: String {
        switch self {
        case .checking: return "Checking"
        case .notInstalled: return "Not installed"
        case .updateReady: return "Update ready"
        case .ready: return "Ready"
        case .working: return "Working"
        case .playing: return "Playing"
        case .failed: return "Needs attention"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .green
        case .playing: return Color(red: 0.35, green: 0.65, blue: 1)
        case .working, .checking: return .orange
        case .updateReady, .notInstalled: return .yellow
        case .failed: return .red
        }
    }

    var pulses: Bool { self == .working || self == .playing || self == .checking }
}

extension LauncherModel {
    // MARK: - State

    var state: LauncherState {
        if busy { return .working }
        if errorMessage != nil { return .failed }
        if robloxRunning { return .playing }
        guard let status else { return .checking }
        if status.installed == nil { return .notInstalled }
        if status.upToDate == false { return .updateReady }
        return .ready
    }

    /// "0.740" from "0.740.0.7400927".
    var shortVersion: String? {
        guard let v = status?.installed else { return nil }
        return v.split(separator: ".").prefix(2).joined(separator: ".")
    }

    // MARK: - Presets

    /// The flags Roblox still reads from ClientAppSettings.json. Since September
    /// 2025 it ignores every other one:
    /// https://devforum.roblox.com/t/allowlist-for-local-client-configuration-via-fast-flags/3966569
    static let allowedFlags: Set<String> = [
        "DFIntCSGLevelOfDetailSwitchingDistance", "DFIntCSGLevelOfDetailSwitchingDistanceL12",
        "DFIntCSGLevelOfDetailSwitchingDistanceL23", "DFIntCSGLevelOfDetailSwitchingDistanceL34",
        "FFlagHandleAltEnterFullscreenManually", "DFFlagTextureQualityOverrideEnabled", "DFIntTextureQualityOverride",
        "FIntDebugForceMSAASamples", "DFFlagDisableDPIScale", "FFlagDebugGraphicsPreferD3D11", "FFlagDebugSkyGray",
        "DFFlagDebugPauseVoxelizer", "DFIntDebugFRMQualityLevelOverride", "FIntFRMMaxGrassDistance",
        "FIntFRMMinGrassDistance", "FFlagDebugGraphicsPreferVulkan", "FFlagDebugGraphicsPreferOpenGL",
        "FIntGrassMovementReducedMotionFactor",
    ]

    /// Flags earlier versions of this launcher set that Roblox now ignores.
    static let retiredFlags = ["DFIntTaskSchedulerTargetFps", "FFlagDisablePostFx", "FIntRenderGrassDetailStrands"]

    static let presetKeys: Set<String> = [
        "FIntDebugForceMSAASamples", "DFFlagTextureQualityOverrideEnabled", "DFIntTextureQualityOverride",
        "FFlagDebugSkyGray", "FIntFRMMinGrassDistance", "FIntFRMMaxGrassDistance",
    ]

    static let presets: [GraphicsPreset] = [
        GraphicsPreset(
            id: "default", name: "Roblox default", symbol: "circle.dashed",
            blurb: "No engine tweaks. Roblox decides everything.",
            highlights: ["Stock settings"], speed: 3, looks: 3, flags: [:]),
        GraphicsPreset(
            id: "balanced", name: "Balanced", symbol: "scale.3d",
            blurb: "Smoother edges without costing much speed.",
            highlights: ["2× anti-aliasing", "Medium textures"], speed: 4, looks: 3,
            flags: [
                "FIntDebugForceMSAASamples": .int(2),
                "DFFlagTextureQualityOverrideEnabled": .bool(true),
                "DFIntTextureQualityOverride": .int(2),
            ]),
        GraphicsPreset(
            id: "performance", name: "Performance", symbol: "bolt.fill",
            blurb: "Less to draw, for steadier frame rates.",
            highlights: ["No anti-aliasing", "Low textures", "No grass"], speed: 5, looks: 2,
            flags: [
                "FIntDebugForceMSAASamples": .int(1),
                "DFFlagTextureQualityOverrideEnabled": .bool(true),
                "DFIntTextureQualityOverride": .int(1),
                "FIntFRMMinGrassDistance": .int(0),
                "FIntFRMMaxGrassDistance": .int(0),
            ]),
        GraphicsPreset(
            id: "quality", name: "Quality", symbol: "sparkles",
            blurb: "Crisp edges and full textures on a strong Mac.",
            highlights: ["4× anti-aliasing", "High textures"], speed: 3, looks: 5,
            flags: [
                "FIntDebugForceMSAASamples": .int(4),
                "DFFlagTextureQualityOverrideEnabled": .bool(true),
                "DFIntTextureQualityOverride": .int(3),
            ]),
        GraphicsPreset(
            id: "potato", name: "Potato", symbol: "leaf.fill",
            blurb: "Everything turned down for older Macs.",
            highlights: ["No anti-aliasing", "Lowest textures", "No grass", "Gray sky"], speed: 5, looks: 1,
            flags: [
                "FIntDebugForceMSAASamples": .int(1),
                "DFFlagTextureQualityOverrideEnabled": .bool(true),
                "DFIntTextureQualityOverride": .int(0),
                "FFlagDebugSkyGray": .bool(true),
                "FIntFRMMinGrassDistance": .int(0),
                "FIntFRMMaxGrassDistance": .int(0),
            ]),
    ]

    /// The preset whose flags exactly match the current engine flags.
    var activePreset: GraphicsPreset? {
        let current = flags.filter { Self.presetKeys.contains($0.key) }
        return Self.presets.first { $0.flags == current }
    }

    func applyPreset(_ preset: GraphicsPreset) {
        var changes: [String: FlagValue?] = [:]
        for key in Self.presetKeys { changes[key] = .some(nil) }
        for (key, value) in preset.flags { changes[key] = value }
        setFlags(changes)
    }

    /// Plain-English names for the engine flags that are set.
    var flagSummary: String {
        let names: [(String, String)] = [
            ("FIntDebugForceMSAASamples", "anti-aliasing"),
            ("DFIntTextureQualityOverride", "textures"),
            ("FIntFRMMaxGrassDistance", "grass"),
            ("FFlagDebugSkyGray", "sky"),
        ]
        let set = names.filter { flags[$0.0] != nil }.map(\.1)
        let others = flags.keys.filter { !Self.presetKeys.contains($0) }.count
        var parts = set
        if others > 0 { parts.append("\(others) custom flag\(others == 1 ? "" : "s")") }
        guard !parts.isEmpty else { return "Using Roblox's defaults" }
        return parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst()
    }

    // MARK: - Loadout

    var loadout: [LoadoutItem] {
        var items: [LoadoutItem] = []
        let preset = activePreset
        items.append(LoadoutItem(
            id: "preset", symbol: preset?.symbol ?? "slider.horizontal.3",
            text: preset.map { $0.id == "default" ? "Default graphics" : "\($0.name) preset" } ?? "Custom graphics",
            active: preset?.id != "default", destination: .graphics(.presets)))
        items.append(LoadoutItem(id: "cursor", symbol: "cursorarrow",
                                 text: cursorStyle == .standard ? "Default cursor" : "\(cursorLabel) cursor",
                                 active: cursorStyle != .standard, destination: .style(.cursor)))
        items.append(LoadoutItem(id: "font", symbol: "textformat",
                                 text: customFontName ?? "Default font",
                                 active: customFontName != nil, destination: .style(.font)))
        items.append(LoadoutItem(id: "sound", symbol: "speaker.wave.2.fill",
                                 text: deathSound == .standard ? "Default death sound" : deathSoundLabel,
                                 active: deathSound != .standard, destination: .style(.sound)))
        let extras = extraModCount
        if extras > 0 {
            items.append(LoadoutItem(id: "mods", symbol: "puzzlepiece.extension.fill",
                                     text: "\(extras) extra mod file\(extras == 1 ? "" : "s")",
                                     active: true, destination: .style(.files)))
        }
        let custom = flags.keys.filter { !Self.presetKeys.contains($0) }.count
        if custom > 0 {
            items.append(LoadoutItem(id: "flags", symbol: "flag.fill",
                                     text: "\(custom) custom FastFlag\(custom == 1 ? "" : "s")",
                                     active: true, destination: .graphics(.flags)))
        }
        return items
    }

    // MARK: - Mods summary

    var activeModCount: Int {
        var count = extraModCount
        if deathSound != .standard { count += 1 }
        if cursorStyle != .standard { count += 1 }
        if customFontURL != nil { count += 1 }
        return count
    }

    /// Roblox's original copy of a resource, even while a mod replaces it.
    func originalResource(_ relative: String) -> URL {
        let backup = supportURL.appendingPathComponent("ModBackups").appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: backup.path) ? backup : robloxResource(relative)
    }

    var deathSoundLabel: String {
        switch deathSound {
        case .standard: return "Default"
        case .classic: return "Classic \u{201C}oof\u{201D}"
        case .custom: return "Custom sound"
        }
    }

    var cursorLabel: String {
        switch cursorStyle {
        case .standard: return "Default"
        case .classic: return "Classic arrow"
        case .custom: return "Custom image"
        }
    }

    // MARK: - Fonts

    /// Loads the Mac's .ttf/.otf font families in the background.
    func loadMacFonts() {
        guard macFonts.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = NSFontManager.shared
            var result: [MacFont] = []
            for family in manager.availableFontFamilies where !family.hasPrefix(".") {
                guard let members = manager.availableMembers(ofFontFamily: family), !members.isEmpty else { continue }
                let regular = members.first { ($0[1] as? String) == "Regular" } ?? members[0]
                guard let name = regular[0] as? String,
                      let font = NSFont(name: name, size: 13),
                      let url = CTFontCopyAttribute(font as CTFont, kCTFontURLAttribute) as? URL,
                      ["ttf", "otf"].contains(url.pathExtension.lowercased())
                else { continue }
                result.append(MacFont(family: family, postScriptName: name, url: url))
            }
            DispatchQueue.main.async { self.macFonts = result }
        }
    }

    static func familyName(of url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first
        else { return nil }
        return CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String
    }

    /// A SwiftUI font for previewing the custom font, registering the mod
    /// file with this process if it is not installed on the Mac.
    func customFontPreview(size: CGFloat) -> Font? {
        guard let url = customFontURL else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let family = Self.familyName(of: url) else { return nil }
        return .custom(family, size: size)
    }
}

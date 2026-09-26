import AppKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case play = "Play"
    case mods = "Mods"
    case fastFlags = "FastFlags"
    case settings = "Settings"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .play: return "play.circle"
        case .mods: return "paintbrush"
        case .fastFlags: return "flag"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: LauncherModel
    @AppStorage("section") private var savedSection = SidebarItem.play.rawValue
    @State private var section: SidebarItem?

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch section ?? .play {
            case .play: PlayView()
            case .mods: ModsView()
            case .fastFlags: FlagsView()
            case .settings: SettingsView()
            case .about: AboutView()
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .onAppear {
            section = SidebarItem(rawValue: savedSection) ?? .play
            model.refreshStatus()
        }
        .onChange(of: section) { savedSection = ($0 ?? .play).rawValue }
    }
}

// MARK: - Shared pieces

struct RobloxIcon: View {
    @EnvironmentObject var model: LauncherModel
    var size: CGFloat

    var body: some View {
        let path = model.robloxAppURL.path
        let image = FileManager.default.fileExists(atPath: path)
            ? NSWorkspace.shared.icon(forFile: path)
            : NSApp.applicationIconImage ?? NSImage()
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct TaskProgress: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        VStack(spacing: 8) {
            if let progress = model.progress {
                ProgressView(value: progress)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Text(model.stage).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let progress = model.progress {
                    Text("\(Int(progress * 100))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).textSelection(.enabled)
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RestartBanner: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.blue)
            Text("Roblox is open. Restart it to use your new settings.").font(.callout)
            Spacer(minLength: 0)
            Button("Restart Roblox") { model.restartRoblox() }.disabled(model.busy)
        }
        .padding(10)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Play

struct PlayView: View {
    @EnvironmentObject var model: LauncherModel

    private var versionLine: String {
        guard let s = model.status else { return "Checking version…" }
        guard let installed = s.installed else {
            return s.latest.map { "Not installed · version \($0) will be downloaded" } ?? "Not installed"
        }
        switch s.upToDate {
        case true?: return "Version \(installed) · up to date"
        case false?: return "Version \(installed) · update to \(s.latest ?? "?") on next launch"
        case nil: return "Version \(installed) · offline"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            RobloxIcon(size: 112).shadow(radius: 6, y: 3)
            VStack(spacing: 4) {
                Text("Roblox").font(.largeTitle.weight(.bold))
                Text(versionLine).foregroundStyle(.secondary)
            }

            Button {
                model.launch()
            } label: {
                Label(model.robloxRunning ? "Open Roblox" : "Launch Roblox", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 220, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.busy)

            Group {
                if model.busy {
                    HStack {
                        TaskProgress()
                        Button("Cancel") { model.cancel() }
                    }
                } else if let error = model.errorMessage {
                    ErrorBanner(message: error) { model.errorMessage = nil }
                } else if model.needsRestart && model.robloxRunning {
                    RestartBanner()
                } else if !model.stage.isEmpty {
                    Text(model.stage).font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 440, minHeight: 44)

            Spacer()

            HStack(spacing: 10) {
                SummaryChip(symbol: "flag", text: "\(model.flags.count) FastFlag\(model.flags.count == 1 ? "" : "s")")
                SummaryChip(symbol: "paintbrush", text: modsText)
                SummaryChip(symbol: "antenna.radiowaves.left.and.right", text: model.status?.channel ?? "LIVE")
                SummaryChip(symbol: "cpu", text: model.status?.arch == "x86_64" ? "Intel" : "Apple silicon")
            }
            .id(model.modsRevision)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup {
                Button { model.checkForUpdates() } label: {
                    Label("Check for Updates", systemImage: "arrow.down.circle")
                }
                .help("Check for a new Roblox version and install it")
                .disabled(model.busy || model.robloxRunning)
            }
        }
        .navigationTitle("Play")
    }

    private var modsText: String {
        let n = model.modFileCount
        return n == 0 ? "No mods" : "\(n) mod file\(n == 1 ? "" : "s")"
    }
}

struct SummaryChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

// MARK: - Link launch window

/// The compact window shown when a roblox:// link opens the launcher.
struct LinkLaunchView: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                RobloxIcon(size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Roblox").font(.title2.weight(.semibold))
                    Text(model.errorMessage == nil ? model.stage : "Couldn't start Roblox")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            if let error = model.errorMessage {
                ErrorBanner(message: error)
                HStack {
                    Spacer()
                    Button("Close") { NSApp.terminate(nil) }.keyboardShortcut(.defaultAction)
                }
            } else {
                if let progress = model.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        model.cancel()
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

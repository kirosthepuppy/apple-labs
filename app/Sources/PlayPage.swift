import AppKit
import SwiftUI

struct PlayPage: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var library: GameLibrary

    private var heroGame: RecentGame? { library.enabled ? library.games.first : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Greeting().appearIn(0)
            Stage(game: heroGame).appearIn(1)
            if let error = model.errorMessage {
                ErrorBanner(message: error) { withAnimation(.bounce) { model.errorMessage = nil } }
            }
            if library.enabled {
                JumpBackIn(games: Array(library.games.dropFirst())).appearIn(2)
            }
            Loadout().appearIn(3)
        }
        .animation(.bounce, value: model.errorMessage)
    }
}

// MARK: - Greeting

private struct Greeting: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var library: GameLibrary

    private var salutation: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Up late"
        }
    }

    private var name: String? { library.enabled ? library.player?.displayName : nil }

    private var line: String {
        switch model.state {
        case .working: return model.stage.isEmpty ? "Getting Roblox ready…" : model.stage
        case .playing: return "Roblox is running. Have fun out there!"
        case .notInstalled: return "Roblox isn't installed yet. It downloads when you press Play."
        case .updateReady: return "A Roblox update is ready and installs when you press Play."
        case .failed: return "Something went wrong. The details are below."
        case .checking: return "Checking for the latest Roblox…"
        case .ready: return "Roblox \(model.shortVersion ?? "") is ready. Your loadout applies when the game starts."
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            if library.enabled, let player = library.player {
                Avatar(url: player.avatarURL, size: 58)
                    .transition(.scale.combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(salutation + (name.map { ", \($0)" } ?? ""))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                Text(line)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.68))
                    .contentTransition(.opacity)
            }
        }
        .animation(.bounce, value: model.state)
    }
}

// MARK: - Stage

/// The big card at the top: your last game's artwork with a Play button, or
/// the Roblox logo when there's no history yet.
private struct Stage: View {
    @EnvironmentObject var model: LauncherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let game: RecentGame?
    @Namespace private var ns
    @State private var size = CGSize(width: 900, height: 340)
    @State private var hover = CGSize.zero

    private var fallbackTitle: String {
        switch model.state {
        case .playing: return "Roblox is running"
        case .notInstalled: return "Let's install Roblox"
        case .updateReady: return "Update ready"
        default: return "Ready to play"
        }
    }

    private var playLabel: String {
        switch model.state {
        case .notInstalled: return "Install & Play"
        case .updateReady: return "Update & Play"
        default: return "Play"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            backdrop
            LinearGradient(colors: [.black.opacity(0.88), .black.opacity(0.5), .clear],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            content
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
            ConfettiBurst(trigger: model.celebrations, colors: model.theme.confetti)
                .allowsHitTesting(false)
        }
        .frame(height: 340)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)],
                                                   startPoint: .top, endPoint: .bottom)))
        .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            switch phase {
            case .active(let p):
                withAnimation(.snappy) {
                    hover = CGSize(width: p.x / max(size.width, 1) - 0.5, height: p.y / max(size.height, 1) - 0.5)
                }
            case .ended:
                withAnimation(.wobble) { hover = .zero }
            }
        }
    }

    /// Sized by a GeometryReader so the artwork always fills the card
    /// exactly, whatever width the page gives it.
    private var backdrop: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [.black, model.theme.heroGlow], startPoint: .leading, endPoint: .trailing)
                if let art = game?.artURL {
                    RemoteImage(url: art) { Color.clear }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width * 1.08, height: geo.size.height * 1.08)
                        .offset(x: -hover.width * 20, y: -hover.height * 14)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    RadialGradient(colors: [model.theme.accent.opacity(0.5), .clear],
                                   center: UnitPoint(x: 0.8, y: 0.5), startRadius: 10, endRadius: 300)
                    BobbingImage(image: bundleIcon(model.robloxAppURL) ?? NSApp.applicationIconImage ?? NSImage(),
                                 glow: model.theme.accent, animated: !reduceMotion)
                        .frame(width: 184, height: 184)
                        .rotation3DEffect(.degrees(Double(hover.width) * 30), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .rotation3DEffect(.degrees(Double(-hover.height) * 30), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                        .position(x: geo.size.width - 170, y: geo.size.height / 2)
                }
            }
            .onAppear { size = geo.size }
            .onChange(of: geo.size) { size = $0 }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let game {
                HStack(spacing: 8) {
                    Text("LAST PLAYED")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                    Circle().fill(.white.opacity(0.5)).frame(width: 3, height: 3)
                    Text(game.lastPlayedText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.4)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            } else {
                StatusPill(state: model.state)
            }

            Text(game?.displayName ?? fallbackTitle)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
                .frame(maxWidth: 580, alignment: .leading)

            meta

            actions
                .padding(.top, 8)
                .animation(.bounce, value: model.busy)
                .animation(.bounce, value: model.robloxRunning)
        }
    }

    private var metaItems: [(symbol: String, text: String)] {
        var items: [(symbol: String, text: String)] = []
        if let playing = game?.playingText { items.append(("person.2.fill", playing)) }
        if model.state == .updateReady { items.append(("arrow.down.circle.fill", "Update ready")) }
        if model.robloxRunning && game != nil { items.append(("circle.fill", "Roblox is open")) }
        return items
    }

    @ViewBuilder private var meta: some View {
        let items = metaItems
        if !items.isEmpty {
            HStack(spacing: 16) {
                ForEach(items, id: \.text) { item in
                    Label(item.text, systemImage: item.symbol)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        let accent = model.theme.accent
        if model.busy {
            progressCapsule
                .matchedGeometryEffect(id: "cta", in: ns)
                .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
        } else {
            HStack(spacing: 14) {
                if model.robloxRunning {
                    Button { model.launch() } label: {
                        Label("Open Roblox", systemImage: "arrow.up.forward.app.fill")
                    }
                    .buttonStyle(.chunky(accent, size: .large))
                    .matchedGeometryEffect(id: "cta", in: ns)
                    Button { model.restartRoblox() } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.chunkyGlass())
                    .help("Quit and relaunch Roblox with your latest settings")
                } else if let game {
                    Button { model.launch(url: game.launchLink) } label: {
                        Label(playLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(.chunky(accent, size: .large))
                    .keyboardShortcut(.defaultAction)
                    .matchedGeometryEffect(id: "cta", in: ns)
                    .help("Join \(game.displayName)")
                    Button { model.launch() } label: { Text("Just open Roblox") }
                        .buttonStyle(.chunkyGlass())
                } else {
                    Button { model.launch() } label: {
                        Label(playLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(.chunky(accent, size: .large))
                    .keyboardShortcut(.defaultAction)
                    .matchedGeometryEffect(id: "cta", in: ns)
                }
            }
            .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
        }
    }

    private var progressCapsule: some View {
        HStack(spacing: 14) {
            ProgressRing(value: model.progress, accent: model.theme.accent)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.stage.isEmpty ? "Working…" : model.stage)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                GlowProgressBar(value: model.progress, accent: model.theme.accent)
                    .frame(width: 270)
            }
            Button { model.cancel() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .heavy))
            }
            .buttonStyle(.chunkyGlass(size: .small))
            .help("Cancel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }
}

/// A circular progress indicator with the percentage in the middle.
private struct ProgressRing: View {
    let value: Double?
    let accent: Color
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: 4)
            if let value {
                Circle()
                    .trim(from: 0, to: max(0.02, value))
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: value)
                Text("\(Int(value * 100))")
                    .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
            } else {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 270 : -90))
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                    }
            }
        }
        .shadow(color: accent.opacity(0.6), radius: 6)
    }
}

// MARK: - Jump back in

private struct JumpBackIn: View {
    @EnvironmentObject var library: GameLibrary
    let games: [RecentGame]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Jump back in").font(.system(size: 20, weight: .heavy, design: .rounded))
                Text("From your Roblox history on this Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button { library.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.chunkyGlass(size: .small))
                .disabled(library.refreshing)
            }

            if games.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(library.refreshing
                         ? "Looking through your recent games…"
                         : "Games you play show up here, ready to rejoin in one click.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
                .padding(18)
                .glass()
                .padding(.top, 8)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { i, game in
                            GameTile(game: game).appearIn(i)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .padding(.horizontal, -6)
            }
        }
    }
}

private struct GameTile: View {
    @EnvironmentObject var model: LauncherModel
    let game: RecentGame
    @State private var hovering = false

    var body: some View {
        Button { model.launch(url: game.launchLink) } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteImage(url: game.iconURL) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white.opacity(0.08))
                            Image(systemName: "cube.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(hovering ? 0.55 : 0.12), lineWidth: hovering ? 2 : 1))
                    .shadow(color: .black.opacity(hovering ? 0.5 : 0.3), radius: hovering ? 16 : 8, y: hovering ? 10 : 5)

                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(model.theme.accent))
                        .overlay(Circle().strokeBorder(.white.opacity(0.45)))
                        .shadow(color: model.theme.accent.opacity(0.7), radius: 8)
                        .scaleEffect(hovering ? 1 : 0.3)
                        .opacity(hovering ? 1 : 0)
                        .padding(10)
                }
                Text(game.displayName)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(game.lastPlayedText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 150, alignment: .leading)
            .scaleEffect(hovering ? 1.05 : 1)
            .offset(y: hovering ? -6 : 0)
            .rotationEffect(.degrees(hovering ? -1.5 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.93))
        .onHover { h in withAnimation(.wobble) { hovering = h } }
        .disabled(model.busy)
        .help("Join \(game.displayName)")
        .contextMenu {
            Button("Play") { model.launch(url: game.launchLink) }
            Button("Open on Roblox.com") { NSWorkspace.shared.open(game.webURL) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(game.webURL.absoluteString, forType: .string)
            }
        }
    }
}

// MARK: - Loadout

private struct Loadout: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var router: Router

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Your loadout").font(.system(size: 20, weight: .heavy, design: .rounded))
                Text("Applied every time you play")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            FlowLayout(spacing: 10) {
                ForEach(model.loadout) { item in
                    LoadoutChip(item: item) { router.go(item.destination) }
                }
            }
        }
        .id(model.modsRevision)
    }
}

private struct LoadoutChip: View {
    @EnvironmentObject var model: LauncherModel
    let item: LoadoutItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(item.active ? model.theme.accent : .white.opacity(0.14)))
                    .overlay(Circle().strokeBorder(.white.opacity(item.active ? 0.35 : 0.1)))
                    .rotationEffect(.degrees(hovering ? -12 : 0))
                Text(item.text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(item.active ? 1 : 0.72))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(hovering ? 1 : 0)
                    .offset(x: hovering ? 0 : -5)
            }
            .padding(.leading, 5)
            .padding(.trailing, 13)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(hovering ? 0.15 : 0.08)))
            .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.25 : 0.1)))
            .scaleEffect(hovering ? 1.05 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.92))
        .onHover { h in withAnimation(.wobble) { hovering = h } }
    }
}

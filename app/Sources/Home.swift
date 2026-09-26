import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: LauncherModel
    let navigate: (Page) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HeroCard()
                .appearIn(0)

            SectionLabel(text: "Your setup", trailing: "Changes apply when you press Play")
                .appearIn(1)

            LazyVGrid(columns: columns, spacing: 16) {
                SetupCard(symbol: "square.3.layers.3d", label: "Preset",
                          title: model.activePreset?.name ?? "Custom",
                          detail: model.activePreset?.highlights.joined(separator: ", ") ?? "Your own mix of engine settings",
                          index: 2) { navigate(.presets) }
                SetupCard(symbol: "cursorarrow.rays", label: "Cursor",
                          title: model.cursorLabel,
                          detail: cursorDetail,
                          index: 3) { navigate(.cursor) }
                SetupCard(symbol: "textformat", label: "Font",
                          title: model.customFontName ?? "Roblox default",
                          detail: "Use any font on your Mac",
                          index: 4) { navigate(.font) }
                SetupCard(symbol: "slider.horizontal.3", label: "Game settings",
                          title: model.flags.isEmpty ? "No changes" : "\(model.flags.count) change\(model.flags.count == 1 ? "" : "s")",
                          detail: model.flagSummary,
                          index: 5) { navigate(.gameSettings) }
                SetupCard(symbol: "puzzlepiece.extension", label: "Mods",
                          title: model.activeModCount == 0 ? "None on" : "\(model.activeModCount) mod\(model.activeModCount == 1 ? "" : "s") on",
                          detail: "Sounds, cursors, fonts and more",
                          index: 6) { navigate(.mods) }
                SetupCard(symbol: "speaker.wave.2.fill", label: "Death sound",
                          title: model.deathSoundLabel,
                          detail: "What you hear when you reset",
                          index: 7) { navigate(.mods) }
            }
            .id(model.modsRevision)
        }
    }

    private var cursorDetail: String {
        switch model.cursorStyle {
        case .standard: return "Roblox's current pointer"
        case .classic: return "The black arrow from classic Roblox"
        case .custom: return "Your own image"
        }
    }
}

// MARK: - Hero

private struct HeroCard: View {
    @EnvironmentObject var model: LauncherModel

    private var title: String {
        switch model.state {
        case .working: return "Getting Roblox ready"
        case .playing: return "Roblox is running"
        case .notInstalled: return "Let's install Roblox"
        case .updateReady: return "Update ready"
        case .failed: return "Something went wrong"
        case .checking, .ready: return "Ready to play"
        }
    }

    private var subtitle: String {
        switch model.state {
        case .working:
            return model.stage.isEmpty ? "Just a moment…" : model.stage
        case .playing:
            return model.needsRestart
                ? "Restart Roblox to use the changes you just made."
                : "Have fun! Your mods and settings are loaded."
        case .notInstalled:
            return "Roblox \(model.status?.latest ?? "") will be downloaded straight from Roblox."
        case .updateReady:
            return "Roblox \(model.status?.latest ?? "") installs automatically when you press Play."
        case .failed:
            return "Check the details below, then try again."
        case .checking:
            return "Checking for the latest version of Roblox…"
        case .ready:
            return "Roblox \(model.shortVersion ?? "") is set up. Your mods and settings load when the game starts."
        }
    }

    private var playLabel: String {
        switch model.state {
        case .playing: return "Open Roblox"
        case .notInstalled: return "Install & Play"
        case .updateReady: return "Update & Play"
        default: return "Play"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [.black.opacity(0.85), model.theme.heroGlow],
                                     startPoint: .leading, endPoint: .trailing))
            RadialGradient(colors: [model.theme.accent.opacity(0.45), .clear],
                           center: UnitPoint(x: 0.82, y: 0.5), startRadius: 10, endRadius: 280)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08))

            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    StatusPill(state: model.state)
                    Text(title)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .contentTransition(.opacity)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    actions
                        .padding(.top, 8)
                        .animation(.bounce, value: model.busy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                FloatingIcon()
                    .frame(width: 210, height: 210)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .animation(.bounce, value: model.state)
    }

    @ViewBuilder private var actions: some View {
        if model.busy {
            VStack(alignment: .leading, spacing: 10) {
                GlowProgressBar(value: model.progress, accent: model.theme.accent)
                    .frame(maxWidth: 380)
                HStack(spacing: 12) {
                    if let progress = model.progress {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Button("Cancel") { model.cancel() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        model.errorMessage = nil
                        model.launch()
                    } label: {
                        Label(playLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(accent: model.theme.accent))
                    .keyboardShortcut(.defaultAction)

                    if model.robloxRunning {
                        Button {
                            model.restartRoblox()
                        } label: {
                            Label("Restart Roblox", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                if let error = model.errorMessage {
                    ErrorBanner(message: error) { withAnimation(.bounce) { model.errorMessage = nil } }
                        .frame(maxWidth: 460)
                }
            }
            .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
        }
    }
}

/// The Roblox icon, bobbing gently, tilting toward the pointer, and popping
/// when a launch starts.
private struct FloatingIcon: View {
    @EnvironmentObject var model: LauncherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = CGSize.zero
    @State private var pop: CGFloat = 1
    @State private var spin: Double = 0

    private var icon: NSImage {
        bundleIcon(model.robloxAppURL) ?? bundleIcon(Bundle.main.bundleURL) ?? NSApp.applicationIconImage ?? NSImage()
    }

    var body: some View {
        GeometryReader { geo in
            BobbingImage(image: icon, glow: model.theme.accent, animated: !reduceMotion)
                .frame(width: 172, height: 172)
                .rotation3DEffect(.degrees(Double(tilt.width) * 16 + spin), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(Double(-tilt.height) * 16), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .scaleEffect(pop)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        withAnimation(.snappy) {
                            tilt = CGSize(width: (p.x / geo.size.width - 0.5) * 2,
                                          height: (p.y / geo.size.height - 0.5) * 2)
                        }
                    case .ended:
                        withAnimation(.wobble) { tilt = .zero }
                    }
                }
                .onTapGesture { celebrate() }
        }
        .onChange(of: model.busy) { busy in if busy { celebrate() } }
    }

    private func celebrate() {
        guard !reduceMotion else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { pop = 1.2 }
        DispatchQueue.main.async {
            withAnimation(.wobble) { pop = 1 }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { spin += 360 }
        }
    }
}

// MARK: - Setup cards

private struct SetupCard: View {
    @EnvironmentObject var model: LauncherModel
    let symbol: String
    let label: String
    let title: String
    let detail: String
    let index: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(model.theme.accent.opacity(hovering ? 0.55 : 0.32))
                        )
                        .rotationEffect(.degrees(hovering ? -8 : 0))
                        .scaleEffect(hovering ? 1.08 : 1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.45))
                        .offset(x: hovering ? 4 : 0)
                }
                Spacer(minLength: 16)
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .glass(corner: 20, highlighted: hovering, tint: .white.opacity(0.25))
            .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 16, y: 10)
            .scaleEffect(hovering ? 1.03 : 1)
            .offset(y: hovering ? -4 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.95))
        .onHover { h in withAnimation(.bounce) { hovering = h } }
        .appearIn(index)
    }
}

import AppKit
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case play, graphics, style, launcher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: return "Play"
        case .graphics: return "Graphics"
        case .style: return "Style"
        case .launcher: return "Launcher"
        }
    }

    var symbol: String {
        switch self {
        case .play: return "gamecontroller.fill"
        case .graphics: return "speedometer"
        case .style: return "paintbrush.pointed.fill"
        case .launcher: return "gearshape.fill"
        }
    }

    var shortcut: Character {
        switch self {
        case .play: return "1"
        case .graphics: return "2"
        case .style: return "3"
        case .launcher: return "4"
        }
    }
}

enum GraphicsTab: String, CaseIterable { case presets, engine, flags }
enum StyleTab: String, CaseIterable { case cursor, font, sound, files }
enum LauncherTab: String, CaseIterable { case look, general, help }

/// Which page and sub-tab is showing. Remembered between launches.
final class Router: ObservableObject {
    @Published private(set) var page: Page
    @Published private(set) var forward = true
    @Published var graphicsTab: GraphicsTab { didSet { save() } }
    @Published var styleTab: StyleTab { didSet { save() } }
    @Published var launcherTab: LauncherTab { didSet { save() } }

    init() {
        let d = UserDefaults.standard
        page = Page(rawValue: d.string(forKey: "page") ?? "") ?? .play
        graphicsTab = GraphicsTab(rawValue: d.string(forKey: "graphicsTab") ?? "") ?? .presets
        styleTab = StyleTab(rawValue: d.string(forKey: "styleTab") ?? "") ?? .cursor
        launcherTab = LauncherTab(rawValue: d.string(forKey: "launcherTab") ?? "") ?? .look
    }

    func go(_ next: Page) {
        guard next != page else { return }
        let order = Page.allCases
        forward = (order.firstIndex(of: next) ?? 0) > (order.firstIndex(of: page) ?? 0)
        withAnimation(.bounce) { page = next }
        save()
    }

    func go(_ tab: GraphicsTab) { graphicsTab = tab; go(.graphics) }
    func go(_ tab: StyleTab) { styleTab = tab; go(.style) }
    func go(_ tab: LauncherTab) { launcherTab = tab; go(.launcher) }

    func go(_ destination: LoadoutItem.Destination) {
        switch destination {
        case .graphics(let tab): go(tab)
        case .style(let tab): go(tab)
        }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(page.rawValue, forKey: "page")
        d.set(graphicsTab.rawValue, forKey: "graphicsTab")
        d.set(styleTab.rawValue, forKey: "styleTab")
        d.set(launcherTab.rawValue, forKey: "launcherTab")
    }
}

// MARK: - Window

struct RootView: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var library: GameLibrary

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AnimatedBackground(theme: model.theme, animated: model.animatedBackground, studs: model.showStuds)
            Color.black.opacity(0.2).ignoresSafeArea()

            HStack(alignment: .top, spacing: 0) {
                Rail()
                    .padding(.leading, 14)
                    .padding(.top, 44)
                    .padding(.bottom, 14)

                ZStack {
                    page
                        .id(router.page)
                        .transition(.asymmetric(
                            insertion: .offset(y: router.forward ? 34 : -34).combined(with: .opacity),
                            removal: .opacity.animation(.easeOut(duration: 0.12))))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            StatusCapsule()
                .padding(.top, 12)
                .padding(.trailing, 18)
        }
        .environment(\.colorScheme, .dark)
        .tint(model.theme.accent)
        .frame(minWidth: 1000, minHeight: 680)
        .onAppear {
            model.refreshStatus()
            library.refresh()
            clearFocus()
        }
        .onChange(of: router.page) { _ in clearFocus() }
    }

    private var page: some View {
        ScrollView {
            Group {
                switch router.page {
                case .play: PlayPage()
                case .graphics: GraphicsPage()
                case .style: StylePage()
                case .launcher: LauncherPage()
                }
            }
            .padding(.leading, 26)
            .padding(.trailing, 34)
            .padding(.top, 58)
            .padding(.bottom, 36)
            .frame(maxWidth: 1200, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
    }

    /// Stops the first text field on a page from grabbing keyboard focus.
    private func clearFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

// MARK: - Rail

/// The floating navigation rail. Its selection pill stretches like a blob:
/// the leading edge springs ahead and the trailing edge catches up.
struct Rail: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var library: GameLibrary
    @State private var top: CGFloat = 0
    @State private var bottom: CGFloat = 64
    @State private var logoSpin: Double = 0

    private let itemHeight: CGFloat = 64
    private let gap: CGFloat = 8

    private func edges(_ page: Page) -> (top: CGFloat, bottom: CGFloat) {
        let i = CGFloat(Page.allCases.firstIndex(of: page) ?? 0)
        let t = i * (itemHeight + gap)
        return (t, t + itemHeight)
    }

    var body: some View {
        let accent = model.theme.accent
        VStack(spacing: 0) {
            Button {
                withAnimation(.wobble) { logoSpin += 360 }
                router.go(.play)
            } label: {
                AppLogo(size: 48)
                    .rotationEffect(.degrees(logoSpin))
                    .shadow(color: accent.opacity(0.55), radius: 10, y: 3)
            }
            .buttonStyle(PressableStyle(pressedScale: 0.85))
            .help("Bootstrapper")
            .padding(.top, 14)
            .padding(.bottom, 22)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(LinearGradient(colors: [accent.mixed(with: .white, by: 0.25), accent],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).strokeBorder(.white.opacity(0.3)))
                    .shadow(color: accent.opacity(0.6), radius: 12, y: 4)
                    .frame(width: 64, height: max(bottom - top, 12))
                    .offset(y: top)

                VStack(spacing: gap) {
                    ForEach(Page.allCases) { item in
                        RailItem(page: item, selected: router.page == item) { router.go(item) }
                            .frame(width: 64, height: itemHeight)
                    }
                }
            }
            .frame(width: 64, alignment: .top)

            Spacer(minLength: 20)

            if library.enabled, let player = library.player {
                Avatar(url: player.avatarURL, size: 44)
                    .help("Last played as \(player.displayName)")
                    .padding(.bottom, 16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 86)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.black.opacity(0.34)))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onAppear {
            let e = edges(router.page)
            top = e.top
            bottom = e.bottom
        }
        .onChange(of: router.page) { move(to: $0) }
    }

    private func move(to page: Page) {
        let target = edges(page)
        let lead = Animation.spring(response: 0.26, dampingFraction: 0.72)
        let trail = Animation.spring(response: 0.52, dampingFraction: 0.6)
        if target.top > top {
            withAnimation(lead) { bottom = target.bottom }
        } else {
            withAnimation(lead) { top = target.top }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard router.page == page else { return }
            withAnimation(trail) {
                top = target.top
                bottom = target.bottom
            }
        }
    }
}

private struct RailItem: View {
    let page: Page
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @State private var bump: CGFloat = 1

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: page.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .scaleEffect(bump)
                    .offset(y: hovering && !selected ? -2 : 0)
                Text(page.title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(selected ? 1 : (hovering ? 0.9 : 0.58)))
            .frame(width: 64, height: 64)
            .background {
                if hovering && !selected {
                    RoundedRectangle(cornerRadius: 21, style: .continuous).fill(.white.opacity(0.07))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.88))
        .onHover { h in withAnimation(.snappy) { hovering = h } }
        .onChange(of: selected) { isSelected in
            guard isSelected else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { bump = 1.4 }
            DispatchQueue.main.async { withAnimation(.wobble) { bump = 1 } }
        }
        .help(page.title + "  ⌘" + String(page.shortcut))
    }
}

struct Avatar: View {
    @EnvironmentObject var model: LauncherModel
    let url: URL?
    let size: CGFloat

    var body: some View {
        RemoteImage(url: url) {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: size, height: size)
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: size, height: size)
        .background(Circle().fill(LinearGradient(colors: [model.theme.accent.mixed(with: .white, by: 0.2), model.theme.accent],
                                                 startPoint: .top, endPoint: .bottom)))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

// MARK: - Status capsule

struct StatusCapsule: View {
    @EnvironmentObject var model: LauncherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0

    var body: some View {
        HStack(spacing: 9) {
            PulseDot(color: model.state.color, pulsing: model.state.pulses && !reduceMotion)
                .frame(width: 8, height: 8)
            Text(model.state.label)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
            if let version = model.shortVersion {
                Circle().fill(.white.opacity(0.3)).frame(width: 3, height: 3)
                Text("Roblox \(version)")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Button {
                withAnimation(.wobble) { spin += 360 }
                model.checkForUpdates()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(spin))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .buttonStyle(PressableStyle(pressedScale: 0.8))
            .disabled(model.busy || model.robloxRunning)
            .help("Check for Roblox updates")
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.leading, 13)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.38)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .animation(.bounce, value: model.state)
    }
}

// MARK: - Link launch window

/// The compact window shown when a roblox:// link opens the launcher.
struct LinkLaunchView: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var library: GameLibrary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 0.6

    private var title: String {
        if model.errorMessage != nil { return "Couldn't start Roblox" }
        if let game = library.linkGame { return "Joining \(game.displayName)" }
        return "Joining game"
    }

    var body: some View {
        ZStack {
            AnimatedBackground(theme: model.theme, animated: model.animatedBackground, studs: model.showStuds)
            Color.black.opacity(0.22)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Group {
                        if let icon = library.linkGame?.iconURL {
                            RemoteImage(url: icon) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.1))
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.25)))
                            .shadow(color: model.theme.accent.opacity(0.5), radius: 12)
                        } else {
                            BobbingImage(image: bundleIcon(model.robloxAppURL) ?? NSApp.applicationIconImage ?? NSImage(),
                                         glow: model.theme.accent, amplitude: 3, period: 1.4, animated: !reduceMotion)
                                .frame(width: 64, height: 64)
                        }
                    }
                    .scaleEffect(pop)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                        Text(model.errorMessage == nil ? model.stage : "See the details below.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                    HStack {
                        Spacer()
                        Button("Close") { NSApp.terminate(nil) }
                            .buttonStyle(.chunky(model.theme.accent, size: .small))
                            .keyboardShortcut(.defaultAction)
                    }
                } else {
                    GlowProgressBar(value: model.progress, accent: model.theme.accent)
                    HStack {
                        if let progress = model.progress {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Button("Cancel") {
                            model.cancel()
                            NSApp.terminate(nil)
                        }
                        .buttonStyle(.chunkyGlass(size: .small))
                        .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(22)
            .padding(.top, 16)
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 460)
        .onAppear { withAnimation(.wobble) { pop = 1 } }
    }
}

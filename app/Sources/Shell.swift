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
enum LauncherTab: String, CaseIterable { case look, accounts, general, help }

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

    static let minimumSize = CGSize(width: 960, height: 640)

    var body: some View {
        let scale = CGFloat(model.uiScale)
        ZStack {
            AnimatedBackground(theme: model.theme, animated: model.animatedBackground, studs: model.showStuds)
            Color.black.opacity(model.theme.isGlass ? 0.08 : 0.2).ignoresSafeArea()

            // Everything is laid out at 1/scale of the window and scaled back
            // up, so the Interface size setting zooms the whole launcher.
            GeometryReader { geo in
                foreground
                    .frame(width: geo.size.width / scale, height: geo.size.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
            }
            .ignoresSafeArea()
        }
        .background(WindowStyler(glass: model.theme.isGlass))
        .environment(\.colorScheme, .dark)
        .tint(model.theme.accent)
        .frame(minWidth: Self.minimumSize.width * scale, minHeight: Self.minimumSize.height * scale)
        .onAppear {
            model.refreshStatus()
            library.refresh()
            clearFocus()
        }
        .onChange(of: router.page) { _ in clearFocus() }
    }

    private var foreground: some View {
        ZStack(alignment: .topTrailing) {
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
        // A new font means every view has to redraw its text.
        .id(model.launcherFont)
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
    @EnvironmentObject var accounts: AccountStore
    @State private var top: CGFloat = 0
    @State private var bottom: CGFloat = 64
    @State private var logoSpin: Double = 0
    @State private var showAccounts = false
    @State private var avatarHover = false

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
                        RailItem(page: item, current: router.page) { router.go(item) }
                            .frame(width: 64, height: itemHeight)
                    }
                }
            }
            .frame(width: 64, alignment: .top)

            Spacer(minLength: 20)

            Button { showAccounts.toggle() } label: {
                AccountAvatar(url: accounts.avatar(for: accounts.current?.userId) ?? (library.enabled ? library.player?.avatarURL : nil),
                              size: 44, ring: avatarHover || showAccounts ? accent : .white.opacity(0.4))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(model.theme.onAccent)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(accent))
                            .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1.5))
                            .offset(x: 3, y: 3)
                            .scaleEffect(avatarHover || showAccounts ? 1 : 0.001)
                    }
                    .scaleEffect(avatarHover ? 1.08 : 1)
            }
            .buttonStyle(PressableStyle(pressedScale: 0.88))
            .onHover { h in withAnimation(.wobble) { avatarHover = h } }
            .help(accounts.current.map { "Signed in as \($0.name) · switch accounts" } ?? "Accounts")
            .popover(isPresented: $showAccounts, arrowEdge: .trailing) {
                AccountSwitcher(isPresented: $showAccounts)
                    .environmentObject(model)
                    .environmentObject(router)
                    .environmentObject(accounts)
            }
            .padding(.bottom, 16)
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
    let current: Page
    let action: () -> Void
    @State private var hovering = false
    @State private var bump: CGFloat = 1

    private var selected: Bool { page == current }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: page.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .scaleEffect(bump)
                    .offset(y: hovering && !selected ? -2 : 0)
                Text(page.title)
                    .font(.ui(10.5, .bold))
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
        // Hover-exit events can get lost while the page animates; the pointer
        // is on the clicked item anyway, so clear stale highlights elsewhere.
        .onChange(of: current) { _ in if !selected { hovering = false } }
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
                .font(.ui(12.5, .bold))
            if let version = model.shortVersion {
                Circle().fill(.white.opacity(0.3)).frame(width: 3, height: 3)
                Text("Roblox \(version)")
                    .font(.ui(12.5, .semibold))
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
                            .font(.ui(20, .heavy))
                            .lineLimit(1)
                        Text(model.errorMessage == nil ? model.stage : "See the details below.")
                            .font(.ui(13))
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
                                .font(.ui(12, .bold).monospacedDigit())
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
        .background(WindowStyler(glass: model.theme.isGlass))
        .environment(\.colorScheme, .dark)
        .frame(width: 460)
        .onAppear { withAnimation(.wobble) { pop = 1 } }
    }
}

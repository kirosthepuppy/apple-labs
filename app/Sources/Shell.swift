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

    static let minimumSize = CGSize(width: 1040, height: 660)

    var body: some View {
        let scale = CGFloat(model.uiScale)
        ZStack {
            AnimatedBackground(theme: model.theme, animated: model.animatedBackground, studs: model.showStuds,
                               image: model.backgroundImage, dim: model.backgroundDim)
            Color.black.opacity(model.theme.isGlass ? 0.04 : 0.1).ignoresSafeArea()

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
        let panel = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 228)

                ZStack {
                    page
                        .id(router.page)
                        .transition(.asymmetric(
                            insertion: .offset(y: router.forward ? 14 : -14).combined(with: .opacity),
                            removal: .opacity.animation(.easeOut(duration: 0.08))))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(panel.fill(.black.opacity(model.theme.isGlass ? 0.16 : 0.26)))
                .clipShape(panel)
                .overlay(panel.strokeBorder(.white.opacity(0.07)))
                // A shadow on the bare panel shape is drawn once; on the page it
                // would be redrawn whenever anything on the page changed.
                .background(panel.outerShadow(color: .black.opacity(0.3), radius: 30, y: 10))
                .padding(.top, 56)
                .padding([.trailing, .bottom], 20)
            }

            StatusCapsule()
                .padding(.top, 13)
                .padding(.trailing, 22)
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
            .padding(30)
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

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var library: GameLibrary
    @EnvironmentObject var accounts: AccountStore
    @Namespace private var ns
    @State private var showAccounts = false
    @State private var accountHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { router.go(.play) } label: {
                HStack(spacing: 12) {
                    AppLogo(size: 38)
                        .shadow(color: model.theme.accent.opacity(0.5), radius: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Apple Labs")
                            .font(.ui(21, .heavy))
                        Text("for Roblox on Mac")
                            .font(.ui(11, .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 0.96))
            .padding(.leading, 10)
            .padding(.top, 58)
            .padding(.bottom, 22)

            ForEach(Page.allCases) { item in
                SidebarRow(item: item, selected: router.page == item, ns: ns) { router.go(item) }
            }

            Spacer(minLength: 20)

            account
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 14)
    }

    private var account: some View {
        let name = accounts.current?.name ?? (library.enabled ? library.player?.displayName : nil)
        return Button { showAccounts.toggle() } label: {
            HStack(spacing: 10) {
                AccountAvatar(url: accounts.avatar(for: accounts.current?.userId) ?? (library.enabled ? library.player?.avatarURL : nil),
                              size: 34, ring: accountHover || showAccounts ? model.theme.accent : .white.opacity(0.3))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name ?? "Accounts")
                        .font(.ui(13.5, .bold))
                        .lineLimit(1)
                    Text("Switch account")
                        .font(.ui(11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.white.opacity(accountHover || showAccounts ? 0.1 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.96))
        .onHover { h in withAnimation(.snappy) { accountHover = h } }
        .help(accounts.current.map { "Signed in as \($0.name) · switch accounts" } ?? "Accounts")
        .popover(isPresented: $showAccounts, arrowEdge: .trailing) {
            AccountSwitcher(isPresented: $showAccounts)
                .environmentObject(model)
                .environmentObject(router)
                .environmentObject(accounts)
        }
    }
}

private struct SidebarRow: View {
    @EnvironmentObject var model: LauncherModel
    let item: Page
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? model.theme.accent.mixed(with: .white, by: 0.35) : .white.opacity(0.8))
                    .frame(width: 24)
                Text(item.title)
                    .font(.ui(15, .semibold))
                Spacer()
                Text("⌘" + String(item.shortcut))
                    .font(.ui(11, .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .opacity(hovering ? 1 : 0)
            }
            .foregroundStyle(.white.opacity(selected ? 1 : 0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.1)))
                        .matchedGeometryEffect(id: "selection", in: ns)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06))
                }
            }
            .offset(x: hovering && !selected ? 3 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.96))
        .onHover { h in withAnimation(.snappy) { hovering = h } }
        // Hover-exit events can get lost while the page animates; the pointer
        // is on the clicked row anyway, so clear stale highlights elsewhere.
        .onChange(of: selected) { _ in if !selected { hovering = false } }
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
            AnimatedBackground(theme: model.theme, animated: model.animatedBackground, studs: model.showStuds,
                               image: model.backgroundImage, dim: model.backgroundDim)
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

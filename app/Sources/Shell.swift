import AppKit
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case home, presets, cursor, font, gameSettings, mods, appearance, settings, help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .presets: return "Presets"
        case .cursor: return "Cursor"
        case .font: return "Font"
        case .gameSettings: return "Game settings"
        case .mods: return "Mods"
        case .appearance: return "Appearance"
        case .settings: return "Settings"
        case .help: return "Help"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .presets: return "square.3.layers.3d"
        case .cursor: return "cursorarrow.rays"
        case .font: return "textformat"
        case .gameSettings: return "slider.horizontal.3"
        case .mods: return "puzzlepiece.extension"
        case .appearance: return "paintpalette"
        case .settings: return "gearshape"
        case .help: return "lifepreserver"
        }
    }

    static let groups: [(title: String, pages: [Page])] = [
        ("Play", [.home, .presets]),
        ("Roblox", [.cursor, .font, .gameSettings, .mods]),
        ("Launcher", [.appearance, .settings]),
    ]
}

struct RootView: View {
    @EnvironmentObject var model: LauncherModel
    @AppStorage("page") private var savedPage = Page.home.rawValue
    @State private var page: Page = .home
    @State private var forward = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AnimatedBackground(theme: model.theme, animated: model.animatedBackground)

            HStack(spacing: 0) {
                Sidebar(page: Binding(get: { page }, set: go))
                    .frame(width: 232)

                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.black.opacity(0.42))
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.07))

                    content
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .offset(y: forward ? 28 : -28).combined(with: .opacity),
                            removal: .opacity.animation(.easeOut(duration: 0.12))))
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
                .padding(.top, 56)
                .padding([.trailing, .bottom], 20)
            }

            StatusPill(state: model.state)
                .padding(.top, 14)
                .padding(.trailing, 24)
        }
        .environment(\.colorScheme, .dark)
        .tint(model.theme.accent)
        .frame(minWidth: 980, minHeight: 660)
        .onAppear {
            page = Page(rawValue: savedPage) ?? .home
            model.refreshStatus()
            clearFocus()
        }
        .onChange(of: page) { _ in clearFocus() }
    }

    /// Stops the first text field on a page from grabbing keyboard focus.
    private func clearFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func go(_ next: Page) {
        guard next != page else { return }
        let order = Page.allCases
        forward = (order.firstIndex(of: next) ?? 0) > (order.firstIndex(of: page) ?? 0)
        withAnimation(.bounce) { page = next }
        savedPage = next.rawValue
    }

    @ViewBuilder private var content: some View {
        let navigate: (Page) -> Void = go
        ScrollView {
            Group {
                switch page {
                case .home: HomeView(navigate: navigate)
                case .presets: PresetsView(navigate: navigate)
                case .cursor: CursorView()
                case .font: FontView()
                case .gameSettings: GameSettingsView()
                case .mods: ModsView()
                case .appearance: AppearanceView()
                case .settings: SettingsView()
                case .help: HelpView()
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: LauncherModel
    @Binding var page: Page
    @Namespace private var ns

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                RobloxIcon(size: 38)
                    .shadow(color: model.theme.accent.opacity(0.5), radius: 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bootstrapper")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("for Roblox on Mac")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.leading, 10)
            .padding(.top, 58)
            .padding(.bottom, 10)

            ForEach(Page.groups, id: \.title) { group in
                Text(group.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 14)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                ForEach(group.pages) { item in
                    SidebarRow(item: item, selected: page == item, ns: ns) { page = item }
                }
            }

            Spacer()

            SidebarRow(item: .help, selected: page == .help, ns: ns) { page = .help }
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 14)
    }
}

private struct SidebarRow: View {
    let item: Page
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @State private var iconScale: CGFloat = 1

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24)
                    .scaleEffect(iconScale)
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
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
        .buttonStyle(PressableStyle(pressedScale: 0.95))
        .onHover { h in withAnimation(.snappy) { hovering = h } }
        .onChange(of: selected) { isSelected in
            guard isSelected else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { iconScale = 1.35 }
            DispatchQueue.main.async { withAnimation(.wobble) { iconScale = 1 } }
        }
    }
}

// MARK: - Link launch window

/// The compact window shown when a roblox:// link opens the launcher.
struct LinkLaunchView: View {
    @EnvironmentObject var model: LauncherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 0.6

    var body: some View {
        ZStack {
            AnimatedBackground(theme: model.theme, animated: model.animatedBackground)
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    BobbingImage(image: bundleIcon(model.robloxAppURL) ?? NSApp.applicationIconImage ?? NSImage(),
                                 glow: model.theme.accent, amplitude: 3, period: 1.4, animated: !reduceMotion)
                        .frame(width: 64, height: 64)
                        .scaleEffect(pop)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.errorMessage == nil ? "Joining game" : "Couldn't start Roblox")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(model.errorMessage == nil ? model.stage : "See the details below.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                    HStack {
                        Spacer()
                        Button("Close") { NSApp.terminate(nil) }
                            .buttonStyle(SecondaryButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    }
                } else {
                    GlowProgressBar(value: model.progress, accent: model.theme.accent)
                    HStack {
                        if let progress = model.progress {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Button("Cancel") {
                            model.cancel()
                            NSApp.terminate(nil)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(22)
            .padding(.top, 18)
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 420)
        .onAppear {
            withAnimation(.wobble) { pop = 1 }
        }
    }
}

import AppKit
import SwiftUI

struct LauncherPage: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var router: Router
    @State private var forward = true

    private var tab: Binding<LauncherTab> {
        Binding(
            get: { router.launcherTab },
            set: { next in
                let order = LauncherTab.allCases
                forward = (order.firstIndex(of: next) ?? 0) > (order.firstIndex(of: router.launcherTab) ?? 0)
                withAnimation(.bounce) { router.launcherTab = next }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Launcher", subtitle: "How this app looks and behaves.") {
                SegmentedTabs(items: [
                    ("Look", "paintpalette.fill", LauncherTab.look),
                    ("General", "switch.2", .general),
                    ("Help", "lifepreserver.fill", .help),
                ], selection: tab, accent: model.theme.accent)
            }
            if let error = model.errorMessage {
                ErrorBanner(message: error) { withAnimation(.bounce) { model.errorMessage = nil } }
            }

            TabContent(tab: router.launcherTab, forward: forward) {
                switch router.launcherTab {
                case .look: LookTab()
                case .general: GeneralTab()
                case .help: HelpTab()
                }
            }
        }
    }
}

// MARK: - Look

private struct LookTab: View {
    @EnvironmentObject var model: LauncherModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(LauncherTheme.allCases.enumerated()), id: \.element) { i, theme in
                    ChoiceTile(selected: model.theme == theme, index: i + 1) {
                        withAnimation(.bounce) { model.theme = theme }
                    } content: {
                        VStack(alignment: .leading, spacing: 10) {
                            ZStack {
                                LinearGradient(colors: theme.glows, startPoint: .topLeading, endPoint: .bottomTrailing)
                                StudPattern(spacing: 14).opacity(0.5)
                                Circle().fill(theme.accent).frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
                                    .shadow(color: theme.accent, radius: 6)
                            }
                            .frame(height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            Text(theme.name).font(.system(size: 15, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.white)
                    }
                }
            }

            GlassGroup {
                SettingRow(title: "Moving background", detail: "Drifting colours and studs behind everything") {
                    AccentToggle(isOn: $model.animatedBackground, accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Studs", detail: "The grid of Roblox-style studs in the background") {
                    AccentToggle(isOn: $model.showStuds, accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Celebrate launches", detail: "A burst of confetti when Roblox starts") {
                    AccentToggle(isOn: $model.celebrateLaunches, accent: model.theme.accent)
                }
            }
            .appearIn(6)

            Text("Motion follows Reduce Motion in System Settings › Accessibility › Display.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var library: GameLibrary
    @State private var channel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GlassGroup {
                SettingRow(title: "Close when Roblox starts", detail: "Get out of the way once the game is running") {
                    AccentToggle(isOn: $model.closeOnLaunch, accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Handle website links", detail: "Play buttons on roblox.com go through the launcher, so updates, mods and settings always apply") {
                    AccentToggle(isOn: Binding(get: { model.isLinkHandler }, set: { model.setLinkHandler($0) }),
                                 accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Show recently played games",
                           detail: "Reads Roblox's logs on this Mac and fetches names, pictures and player counts from Roblox") {
                    AccentToggle(isOn: $library.enabled, accent: model.theme.accent)
                }
            }
            .appearIn(1)

            SectionLabel(text: "Roblox", trailing: model.status.map { "Version \($0.installed ?? "not installed")" })
                .appearIn(2)
            GlassGroup {
                SettingRow(title: "Channel", detail: "LIVE for everyone; others usually need an account with access") {
                    TextField("LIVE", text: $channel)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.28)))
                        .frame(width: 140)
                        .onSubmit { model.setConfig("CHANNEL", channel.isEmpty ? "LIVE" : channel) }
                }
                RowDivider()
                SettingRow(title: "Install location", detail: model.status?.installPath) {
                    ChipPicker(options: [("All users", "/Applications"), ("Just me", NSHomeDirectory() + "/Applications")],
                               selection: Binding(get: { model.status?.installDir ?? "/Applications" },
                                                  set: { model.setConfig("INSTALL_DIR", $0) }),
                               accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Build", detail: "Automatic picks the native build for this Mac") {
                    ChipPicker(options: [("Automatic", "auto"), ("Apple silicon", "arm64"), ("Intel", "x86_64")],
                               selection: Binding(get: { model.status?.archSetting ?? "auto" },
                                                  set: { model.setConfig("ARCH", $0) }),
                               accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Reinstall Roblox", detail: "Downloads a fresh copy. Needed to switch channel, location or build right away") {
                    Button { model.reinstall() } label: { Label("Reinstall", systemImage: "arrow.down.circle") }
                        .buttonStyle(.chunkyGlass(size: .small))
                        .disabled(model.busy || model.robloxRunning)
                }
                if model.busy {
                    GlowProgressBar(value: model.progress, accent: model.theme.accent)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                }
            }
            .appearIn(3)

            HStack(spacing: 10) {
                Button { NSWorkspace.shared.open(model.supportURL) } label: { Label("Data Folder", systemImage: "folder") }
                Button { NSWorkspace.shared.open(model.logURL) } label: { Label("Log", systemImage: "doc.text") }
                Button { NSWorkspace.shared.activateFileViewerSelecting([model.robloxAppURL]) } label: {
                    Label("Show Roblox", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.chunkyGlass(size: .small))
            .appearIn(4)
        }
        .onAppear {
            channel = model.status?.channel ?? "LIVE"
            model.refreshLinkHandler()
        }
        .onChange(of: model.status?.channel) { channel = $0 ?? "LIVE" }
    }
}

// MARK: - Help

private struct HelpTab: View {
    @EnvironmentObject var model: LauncherModel

    private let faqs: [(String, String)] = [
        ("How do I join a game from the website?",
         "Turn on Handle website links in General, then press Play on roblox.com. The launcher updates Roblox, applies your loadout, then joins the game."),
        ("I changed a setting but nothing happened.",
         "Changes load when Roblox starts. If Roblox is open, use Restart. Some FastFlags do nothing because Roblox only honours flags on its allowlist."),
        ("Where do my recent games come from?",
         "From Roblox's own log files on this Mac. Game names, pictures and player counts come from Roblox's public web APIs. Turn it off in General to stop both."),
        ("Do mods survive Roblox updates?",
         "Yes. Updates replace Roblox's files, and the launcher puts your mods and FastFlags back before the game starts."),
        ("macOS says Roblox is damaged or modified.",
         "Mods and FastFlags change files inside Roblox.app, which macOS notices. Roblox still runs. Reinstall from General to get an untouched copy."),
        ("How do I uninstall everything?",
         "Run roblox-bootstrapper uninstall --purge in Terminal. It removes Roblox, this launcher and all settings."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                ForEach(Array(faqs.enumerated()), id: \.offset) { i, faq in
                    FAQRow(question: faq.0, answer: faq.1).appearIn(i + 1)
                }
            }

            HStack(spacing: 16) {
                AppLogo(size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bootstrapper \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                    Text("Inspired by Bloxstrap and Fishstrap. Not affiliated with Roblox Corporation.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button { NSWorkspace.shared.open(model.logURL) } label: { Label("Log", systemImage: "doc.text") }
                    .buttonStyle(.chunkyGlass(size: .small))
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/kirosthepuppy/macOS-bootstrapper/issues")!)
                } label: { Label("Report a Problem", systemImage: "exclamationmark.bubble") }
                    .buttonStyle(.chunky(model.theme.accent, size: .small))
            }
            .padding(18)
            .glass(corner: 20)
            .appearIn(8)
        }
    }
}

private struct FAQRow: View {
    let question: String
    let answer: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.bounce) { open.toggle() }
            } label: {
                HStack {
                    Text(question).font(.system(size: 14.5, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .heavy))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 0.98))
            if open {
                Text(answer)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glass(corner: 16, highlighted: open, tint: .white.opacity(0.25))
        .clipped()
    }
}

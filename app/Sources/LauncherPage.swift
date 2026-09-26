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
                    ("Accounts", "person.2.fill", .accounts),
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
                case .accounts: AccountsTab()
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
    private let themeColumns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 4)
    private let fontColumns = [GridItem(.adaptive(minimum: 140), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "Theme").appearIn(1)
            LazyVGrid(columns: themeColumns, spacing: 14) {
                ForEach(Array(ThemeID.allCases.enumerated()), id: \.element) { i, id in
                    ChoiceTile(selected: model.themeID == id, index: i + 1) {
                        withAnimation(.bounce) { model.themeID = id }
                    } content: {
                        VStack(alignment: .leading, spacing: 10) {
                            ThemePreview(theme: id == .custom ? model.customTheme : .preset(id),
                                         image: id == .custom ? model.backgroundImage : nil)
                                .frame(height: 74)
                            HStack(spacing: 6) {
                                Text(id.name).font(.ui(15, .heavy))
                                if id == .custom {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }

            if model.themeID == .custom {
                CustomThemeEditor()
                    .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
            }

            SectionLabel(text: "Font").appearIn(10)
            LazyVGrid(columns: fontColumns, spacing: 12) {
                ForEach(Array(LauncherFont.allCases.enumerated()), id: \.element) { i, font in
                    ChoiceTile(selected: model.launcherFont == font, index: i + 11) {
                        model.launcherFont = font
                    } content: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aa").font(font.font(size: 30, weight: .heavy))
                            Text(font.name)
                                .font(font.font(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .foregroundStyle(.white)
                    }
                }
            }

            SectionLabel(text: "Size").appearIn(18)
            GlassGroup { ScaleControl() }.appearIn(19)

            SectionLabel(text: "Motion").appearIn(20)
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
            .appearIn(21)

            Text("Motion follows Reduce Motion in System Settings › Accessibility › Display.")
                .font(.ui(12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .animation(.bounce, value: model.themeID)
    }
}

/// A little swatch of a theme for its tile.
private struct ThemePreview: View {
    let theme: Theme
    var image: NSImage?

    var body: some View {
        ZStack {
            if theme.isGlass {
                // A pretend desktop seen through frosted glass.
                LinearGradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.3), Color(red: 0.32, green: 0.52, blue: 0.98),
                                        Color(red: 0.62, green: 0.32, blue: 0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.8)).frame(width: 30).offset(x: -34, y: -12)
                VisualEffectBlur(material: .hudWindow, blending: .withinWindow)
                LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
            } else if let image {
                // Overlaid on a colour so the cropped picture can't widen the tile.
                Color.black.overlay(Image(nsImage: image).resizable().aspectRatio(contentMode: .fill))
                StudPattern(spacing: 14).opacity(0.3)
            } else {
                theme.base
                LinearGradient(colors: theme.glows, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.9)
                StudPattern(spacing: 14).opacity(0.45)
            }
            Circle()
                .fill(theme.accent)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: 2))
                .shadow(color: theme.accent, radius: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

private struct CustomThemeEditor: View {
    @EnvironmentObject var model: LauncherModel

    private var accent: Binding<Color> {
        Binding(get: { model.customTheme.accent },
                set: {
                    model.customTheme.accent = $0
                    model.customTheme.heroGlow = $0.mixed(with: .black, by: 0.55)
                })
    }

    private var base: Binding<Color> {
        Binding(get: { model.customTheme.base }, set: { model.customTheme.base = $0 })
    }

    private func glow(_ i: Int) -> Binding<Color> {
        Binding(get: { model.customTheme.glows[i] }, set: { model.customTheme.glows[i] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your colours").font(.ui(16, .heavy))
                    Text("Click a swatch to pick any colour.").font(.ui(12)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Menu {
                    ForEach(ThemeID.allCases.filter { $0 != .custom }) { id in
                        Button(id.name) {
                            var theme = Theme.preset(id)
                            theme.id = .custom
                            if theme.isGlass || theme.base == .clear { theme.base = Color(white: 0.05) }
                            withAnimation(.bounce) { model.customTheme = theme }
                        }
                    }
                } label: {
                    Label("Start From", systemImage: "square.on.square")
                        .font(.ui(12.5, .bold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .fixedSize()
                Button { withAnimation(.wobble) { model.customTheme = .surprise() } } label: {
                    Label("Surprise Me", systemImage: "dice.fill")
                }
                .buttonStyle(.chunky(model.theme.accent, size: .small))
            }
            HStack(spacing: 10) {
                Swatch(title: "Accent", color: accent)
                Swatch(title: "Glow 1", color: glow(0))
                Swatch(title: "Glow 2", color: glow(1))
                Swatch(title: "Glow 3", color: glow(2))
                Swatch(title: "Background", color: base)
            }
            BackgroundPicker()
        }
        .padding(18)
        .glass(corner: 20, highlighted: true, tint: model.theme.accent.opacity(0.6))
    }
}

/// Picks a picture to show behind the launcher, with dim and blur controls.
private struct BackgroundPicker: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        let image = model.backgroundImage
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.3))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay(Color.black.opacity(model.backgroundDim))
                } else {
                    Image(systemName: "photo").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 76, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.15)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Background picture").font(.ui(14, .semibold))
                Text(image == nil ? "Show any picture behind the launcher." : "Shown behind everything while Custom is on.")
                    .font(.ui(12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 8)

            if image != nil {
                HStack(spacing: 8) {
                    Text("Dim").font(.ui(12, .semibold)).foregroundStyle(.white.opacity(0.7))
                    Slider(value: $model.backgroundDim, in: 0...0.8).labelsHidden().frame(width: 90)
                }
                HStack(spacing: 8) {
                    Text("Blur").font(.ui(12, .semibold)).foregroundStyle(.white.opacity(0.7))
                    AccentToggle(isOn: $model.backgroundBlur, accent: model.theme.accent)
                }
            }
            Button(image == nil ? "Choose…" : "Change…") {
                if let file = chooseFile(types: [.image], message: "Choose a picture for the launcher's background") {
                    model.setBackgroundImage(file)
                }
            }
            .buttonStyle(.chunky(model.theme.accent, size: .small))
            if image != nil {
                Button { model.setBackgroundImage(nil) } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.chunkyGlass(size: .small))
                .help("Remove the picture")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.2)))
        .animation(.snappy, value: image != nil)
    }
}

private struct Swatch: View {
    let title: String
    @Binding var color: Color

    var body: some View {
        VStack(spacing: 7) {
            ColorPicker(title, selection: $color, supportsOpacity: false)
                .labelsHidden()
            Text(title).font(.ui(11.5, .semibold)).foregroundStyle(.white.opacity(0.7))
            Text(color.hex).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.2)))
    }
}

/// Zooms the whole launcher. The new size is applied when you let go of the
/// slider, so the control doesn't move under the pointer while dragging.
private struct ScaleControl: View {
    @EnvironmentObject var model: LauncherModel
    @State private var draft: Double = 1
    @State private var dragging = false

    var body: some View {
        SettingRow(title: "Interface size", detail: "Zoom the whole launcher. ⌘+ and ⌘− work too.") {
            HStack(spacing: 10) {
                Button { model.zoom(by: -0.05) } label: {
                    Image(systemName: "minus").font(.system(size: 11, weight: .heavy))
                }
                .buttonStyle(.chunkyGlass(size: .small))
                .disabled(model.uiScale <= LauncherModel.scaleRange.lowerBound)

                Slider(value: $draft, in: LauncherModel.scaleRange, step: 0.05) {
                    Text("Interface size")
                } onEditingChanged: { editing in
                    dragging = editing
                    if !editing { model.uiScale = draft }
                }
                .labelsHidden()
                .frame(width: 150)

                Button { model.zoom(by: 0.05) } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .heavy))
                }
                .buttonStyle(.chunkyGlass(size: .small))
                .disabled(model.uiScale >= LauncherModel.scaleRange.upperBound)

                Text("\(Int(((dragging ? draft : model.uiScale) * 100).rounded()))%")
                    .font(.ui(13, .bold).monospacedDigit())
                    .frame(width: 46, alignment: .trailing)

                Button("Reset") { model.uiScale = 1 }
                    .buttonStyle(.chunkyGlass(size: .small))
                    .disabled(abs(model.uiScale - 1) < 0.001)
            }
            .fixedSize()
        }
        .onAppear { draft = model.uiScale }
        .onChange(of: model.uiScale) { if !dragging { draft = $0 } }
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
                SettingRow(title: "Close when Roblox starts", detail: "Off: the launcher stays open while you play") {
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
        ("How does account switching work?",
         "Saving an account keeps a copy of the Roblox app's own sign-in on this Mac. Switching swaps it in while Roblox is closed. The launcher never sees your password; remove an account here to forget it."),
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
                    Text("Apple Labs \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.ui(17, .heavy))
                    Text("Inspired by Bloxstrap and Fishstrap. Not affiliated with Roblox Corporation.")
                        .font(.ui(12))
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
                    Text(question).font(.ui(14.5, .bold))
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
                    .font(.ui(13))
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

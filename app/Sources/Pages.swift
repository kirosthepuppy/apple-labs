import AppKit
import SwiftUI
import UniformTypeIdentifiers

func chooseFile(types: [UTType], message: String) -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = types
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message = message
    return panel.runModal() == .OK ? panel.url : nil
}

/// A selectable tile used for presets, cursors, sounds and themes.
struct ChoiceTile<Content: View>: View {
    @EnvironmentObject var model: LauncherModel
    let selected: Bool
    let index: Int
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false
    @State private var bump: CGFloat = 1

    var body: some View {
        Button {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { bump = 0.94 }
            DispatchQueue.main.async { withAnimation(.wobble) { bump = 1 } }
            action()
        } label: {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(18)
                .glass(corner: 20, highlighted: selected || hovering,
                       tint: selected ? model.theme.accent : .white.opacity(0.25))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, model.theme.accent)
                            .padding(12)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .shadow(color: selected ? model.theme.accent.opacity(0.35) : .clear, radius: 16)
                .scaleEffect((hovering ? 1.02 : 1) * bump)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.96))
        .onHover { h in withAnimation(.bounce) { hovering = h } }
        .animation(.bounce, value: selected)
        .appearIn(index)
    }
}

private struct RestartHint: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        if model.needsRestart && model.robloxRunning {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(model.theme.accent)
                Text("Roblox is open. Restart it to use your changes.")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Restart Roblox") { model.restartRoblox() }
                    .buttonStyle(PrimaryButtonStyle(accent: model.theme.accent, large: false))
                    .disabled(model.busy)
            }
            .padding(14)
            .glass(corner: 16, highlighted: true, tint: model.theme.accent.opacity(0.6))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Presets

struct PresetsView: View {
    @EnvironmentObject var model: LauncherModel
    let navigate: (Page) -> Void
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Presets", subtitle: "One click to set frame rate, anti-aliasing, textures and effects together.")
            RestartHint()

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(LauncherModel.presets.enumerated()), id: \.element.id) { i, preset in
                    ChoiceTile(selected: model.activePreset?.id == preset.id, index: i + 1) {
                        model.applyPreset(preset)
                    } content: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 46, height: 46)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(model.theme.accent.opacity(0.32)))
                            Text(preset.name).font(.system(size: 19, weight: .bold, design: .rounded))
                            Text(preset.blurb).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                            FlowChips(items: preset.highlights)
                        }
                        .foregroundStyle(.white)
                    }
                }
            }

            HStack {
                Image(systemName: "info.circle")
                Text(model.activePreset == nil
                     ? "You're using a custom mix. Pick a preset to reset the engine settings, or fine-tune them in Game settings."
                     : "Fine-tune any of these in Game settings. Roblox only honours FastFlags on its allowlist.")
                Spacer()
                Button("Game settings") { navigate(.gameSettings) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.white.opacity(0.65))
            .appearIn(7)
        }
    }
}

/// Small capsules that wrap onto new lines.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.1)))
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                rows.append((y, x - spacing, rowHeight))
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if x > 0 { rows.append((y, x - spacing, rowHeight)) }
        return rows
    }
}

// MARK: - Cursor

struct CursorView: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Cursor", subtitle: "Pick the mouse pointer you see in game.")
            RestartHint()

            HStack(spacing: 16) {
                tile(.standard, title: "Default", detail: "Roblox's current pointer", index: 1,
                     image: NSImage(contentsOf: model.originalResource(LauncherModel.cursorPaths[0])))
                tile(.classic, title: "Classic arrow", detail: "The black arrow from classic Roblox", index: 2,
                     image: NSImage(contentsOf: model.robloxResource(LauncherModel.classicCursorSources[0])))
                tile(.custom, title: "Custom image", detail: "Any PNG or JPEG, scaled to 64×64", index: 3,
                     image: model.cursorStyle == .custom ? NSImage(contentsOf: model.modURL(LauncherModel.cursorPaths[0])) : nil)
            }
            .id(model.modsRevision)

            if model.cursorStyle == .custom {
                Button("Choose a different image…") { pickCustom() }
                    .buttonStyle(SecondaryButtonStyle())
                    .appearIn(4)
            }
        }
    }

    private func tile(_ style: CursorStyle, title: String, detail: String, index: Int, image: NSImage?) -> some View {
        ChoiceTile(selected: model.cursorStyle == style, index: index) {
            if style == .custom { pickCustom() } else { model.setCursor(style) }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(height: 110)
                Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2, reservesSpace: true)
            }
            .foregroundStyle(.white)
        }
    }

    private func pickCustom() {
        if let file = chooseFile(types: [.png, .jpeg, .tiff, .gif], message: "Choose a cursor image (square images look best)") {
            model.setCursor(.custom, image: file)
        }
    }
}

// MARK: - Font

struct FontView: View {
    @EnvironmentObject var model: LauncherModel
    @State private var search = ""

    private var filtered: [MacFont] {
        search.isEmpty ? model.macFonts : model.macFonts.filter { $0.family.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Font", subtitle: "Replace every font in Roblox with one you like.")
            RestartHint()

            VStack(alignment: .leading, spacing: 10) {
                Text(model.customFontName ?? "Roblox default")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("The quick brown fox jumps over the lazy dog")
                    .font(model.customFontPreview(size: 30) ?? .system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("ABCDEFGHIJKLM 0123456789 !?&")
                    .font(model.customFontPreview(size: 17) ?? .system(size: 17, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                HStack {
                    Button("Choose Font File…") {
                        let types = ["ttf", "otf"].compactMap { UTType(filenameExtension: $0) }
                        if let file = chooseFile(types: types, message: "Choose a .ttf or .otf font") {
                            withAnimation(.bounce) { model.setFont(file) }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if model.customFontName != nil {
                        Button("Reset to Default") { withAnimation(.bounce) { model.setFont(nil) } }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.top, 6)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(corner: 20)
            .id(model.modsRevision)
            .appearIn(1)

            SectionLabel(text: "Fonts on your Mac", trailing: model.macFonts.isEmpty ? nil : "\(model.macFonts.count) fonts")
                .appearIn(2)

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                    TextField("Search fonts", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(12)
                RowDivider()
                if model.macFonts.isEmpty {
                    ProgressView().controlSize(.small).padding(30)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { font in
                            FontRow(font: font, selected: model.customFontName == font.family) {
                                withAnimation(.bounce) { model.setFont(font.url, name: font.family) }
                            }
                        }
                    }
                }
            }
            .glass(corner: 18)
            .appearIn(3)
        }
        .onAppear { model.loadMacFonts() }
    }
}

private struct FontRow: View {
    @EnvironmentObject var model: LauncherModel
    let font: MacFont
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(font.family)
                    .font(.custom(font.postScriptName, size: 17))
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, model.theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering || selected ? 0.08 : 0)))
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.98))
        .onHover { h in withAnimation(.snappy) { hovering = h } }
    }
}

// MARK: - Game settings

struct GameSettingsView: View {
    @EnvironmentObject var model: LauncherModel
    @State private var newName = ""
    @State private var newValue = ""
    @State private var showImport = false
    @State private var importText = ""
    @State private var importError: String?
    @State private var confirmClear = false

    private static let grassKeys = ["FIntFRMMinGrassDistance", "FIntFRMMaxGrassDistance", "FIntRenderGrassDetailStrands"]

    private func intBinding(_ key: String) -> Binding<Int> {
        Binding(
            get: {
                if case .int(let n)? = model.flags[key] { return n }
                return -1
            },
            set: { model.setFlag(key, $0 == -1 ? nil : .int($0)) })
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { model.flags[key] == .bool(true) },
                set: { model.setFlag(key, $0 ? .bool(true) : nil) })
    }

    private var textureBinding: Binding<Int> {
        Binding(
            get: {
                guard model.flags["DFFlagTextureQualityOverrideEnabled"] == .bool(true),
                      case .int(let n)? = model.flags["DFIntTextureQualityOverride"] else { return -1 }
                return n
            },
            set: { level in
                model.setFlags([
                    "DFFlagTextureQualityOverrideEnabled": level == -1 ? nil : .bool(true),
                    "DFIntTextureQualityOverride": level == -1 ? nil : .int(level),
                ])
            })
    }

    private var grassBinding: Binding<Bool> {
        Binding(
            get: { Self.grassKeys.allSatisfy { model.flags[$0] == .int(0) } },
            set: { off in
                var changes: [String: FlagValue?] = [:]
                for key in Self.grassKeys { changes[key] = off ? .int(0) : .some(nil) }
                model.setFlags(changes)
            })
    }

    private var fpsOptions: [(label: String, value: Int)] {
        var options: [(label: String, value: Int)] = [("Default", -1), ("60", 60), ("120", 120), ("144", 144), ("240", 240), ("Unlimited", 9999)]
        if case .int(let n)? = model.flags["DFIntTaskSchedulerTargetFps"], !options.contains(where: { $0.value == n }) {
            options.append(("\(n)", n))
        }
        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Game settings", subtitle: "Engine tweaks written into Roblox as FastFlags every time you play.")
            RestartHint()
            if let error = model.flagsError { ErrorBanner(message: error) }

            GlassGroup {
                SettingRow(title: "Frame rate limit", detail: "Frames per second Roblox aims for") {
                    ChipPicker(options: fpsOptions, selection: intBinding("DFIntTaskSchedulerTargetFps"), accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Anti-aliasing", detail: "Smooths jagged edges; higher costs more") {
                    ChipPicker(options: [("Default", -1), ("Off", 1), ("2×", 2), ("4×", 4), ("8×", 8)],
                               selection: intBinding("FIntDebugForceMSAASamples"), accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Texture quality", detail: "Overrides Roblox's automatic choice") {
                    ChipPicker(options: [("Default", -1), ("Lowest", 0), ("Low", 1), ("Medium", 2), ("High", 3)],
                               selection: textureBinding, accent: model.theme.accent)
                }
            }
            .appearIn(1)

            GlassGroup {
                SettingRow(title: "Disable post-processing", detail: "Removes bloom, blur, sun rays and colour correction") {
                    AccentToggle(isOn: boolBinding("FFlagDisablePostFx"), accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Remove grass", detail: "Hides terrain grass for a cleaner, faster view") {
                    AccentToggle(isOn: grassBinding, accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Plain gray sky", detail: "Replaces the skybox with flat gray") {
                    AccentToggle(isOn: boolBinding("FFlagDebugSkyGray"), accent: model.theme.accent)
                }
            }
            .appearIn(2)

            HStack(spacing: 10) {
                SectionLabel(text: "All FastFlags")
                Button("Import…") { importText = ""; importError = nil; showImport = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Copy JSON") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.exportFlagsJSON(), forType: .string)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.flags.isEmpty)
                Button("Clear All…") { confirmClear = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.flags.isEmpty)
            }
            .padding(.top, 6)
            .appearIn(3)

            GlassGroup {
                if model.flags.isEmpty {
                    Text("No FastFlags set yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
                ForEach(model.flags.keys.sorted(), id: \.self) { name in
                    FlagRow(name: name, value: model.flags[name] ?? .string(""))
                        .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity),
                                                removal: .opacity))
                    RowDivider()
                }
                HStack(spacing: 10) {
                    TextField("FlagName", text: $newName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.25)))
                    TextField("value", text: $newValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.25)))
                        .frame(width: 150)
                        .onSubmit(addFlag)
                    Button("Add", action: addFlag)
                        .buttonStyle(PrimaryButtonStyle(accent: model.theme.accent, large: false))
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(14)
            }
            .animation(.bounce, value: model.flags.keys.sorted())
            .appearIn(4)

            Text("true/false and whole numbers are saved as booleans and integers; anything else as text. Roblox only honours FastFlags on its allowlist and ignores the rest.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .onAppear { model.loadFlags() }
        .confirmationDialog("Remove all FastFlags?", isPresented: $confirmClear) {
            Button("Remove All", role: .destructive) { withAnimation(.bounce) { model.replaceFlags([:]) } }
        }
        .sheet(isPresented: $showImport) { importSheet }
    }

    private var importSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import FastFlags").font(.headline)
            Text("Paste a JSON object of flags, such as an export from Bloxstrap or Fishstrap. Flags with the same name are replaced.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $importText)
                .font(.body.monospaced())
                .frame(minHeight: 200)
                .border(.quaternary)
            if let importError {
                Text(importError).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Choose File…") {
                    if let file = chooseFile(types: [.json], message: "Choose a FastFlags JSON file"),
                       let text = try? String(contentsOf: file, encoding: .utf8) {
                        importText = text
                    }
                }
                Spacer()
                Button("Cancel") { showImport = false }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    importError = model.importFlags(json: importText)
                    if importError == nil { showImport = false }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func addFlag() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(.bounce) { model.setFlag(name, FlagValue(parsing: newValue)) }
        newName = ""
        newValue = ""
    }
}

private struct FlagRow: View {
    @EnvironmentObject var model: LauncherModel
    let name: String
    let value: FlagValue
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            if case .bool(let b) = value {
                AccentToggle(isOn: Binding(get: { b }, set: { model.setFlag(name, .bool($0)) }), accent: model.theme.accent)
            } else {
                TextField("Value", text: $draft)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(focused ? 0.35 : 0.2)))
                    .frame(width: 140)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { isFocused in if !isFocused { commit() } }
            }
            Button {
                withAnimation(.bounce) { model.setFlag(name, nil) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(PressableStyle(pressedScale: 0.8))
            .help("Remove \(name)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .onAppear { draft = value.text }
        .onChange(of: value) { draft = $0.text }
    }

    private func commit() {
        let parsed = FlagValue(parsing: draft)
        if parsed != value { model.setFlag(name, parsed) }
    }
}

// MARK: - Mods

struct ModsView: View {
    @EnvironmentObject var model: LauncherModel
    @State private var confirmReset = false
    @State private var sound: NSSound?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Mods", subtitle: "Swap Roblox's own sounds and files. Mods come back after every update.")
            RestartHint()
            if let error = model.errorMessage {
                ErrorBanner(message: error) { withAnimation(.bounce) { model.errorMessage = nil } }
            }

            SectionLabel(text: "Death sound").appearIn(1)
            HStack(spacing: 16) {
                soundTile(.standard, title: "Default", detail: "Roblox's current sound", symbol: "speaker.wave.2.fill", index: 2,
                          file: model.originalResource(LauncherModel.deathSoundPath))
                soundTile(.classic, title: "Classic \u{201C}oof\u{201D}", detail: "The one everyone remembers", symbol: "face.dashed.fill", index: 3,
                          file: model.robloxResource("content/sounds/oof.ogg"))
                soundTile(.custom, title: "Custom sound", detail: "Any .ogg, .mp3 or .wav", symbol: "waveform", index: 4,
                          file: model.deathSound == .custom ? model.modURL(LauncherModel.deathSoundPath) : nil)
            }
            .id(model.modsRevision)

            SectionLabel(text: "Your own mods").appearIn(5)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(model.theme.accent)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Modifications folder").font(.system(size: 15, weight: .semibold))
                        Text("\(model.modFileCount) file\(model.modFileCount == 1 ? "" : "s") · mirrors Roblox.app/Contents/Resources")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                Text("Drop files in with the same path as inside Roblox. For example, content/sounds/ouch.ogg replaces the death sound and content/textures/… replaces textures. Removing a file puts Roblox's original back.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Folder") { NSWorkspace.shared.open(model.modsURL) }
                        .buttonStyle(PrimaryButtonStyle(accent: model.theme.accent, large: false))
                    Button("Re-apply") { model.applyMods() }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("Remove All Mods…") { confirmReset = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.modFileCount == 0)
                }
            }
            .padding(20)
            .glass(corner: 20)
            .id(model.modsRevision)
            .appearIn(6)
        }
        .confirmationDialog("Remove all mods?", isPresented: $confirmReset) {
            Button("Remove All Mods", role: .destructive) { model.clearMods() }
        } message: {
            Text("This deletes everything in the mods folder and restores Roblox's original files, including your cursor and font.")
        }
    }

    private func soundTile(_ choice: DeathSound, title: String, detail: String, symbol: String, index: Int, file: URL?) -> some View {
        ChoiceTile(selected: model.deathSound == choice, index: index) {
            if choice == .custom {
                let types = ["ogg", "mp3", "wav"].compactMap { UTType(filenameExtension: $0) }
                if let picked = chooseFile(types: types, message: "Choose a sound to play when your character dies") {
                    model.setDeathSound(.custom, file: picked)
                }
            } else {
                model.setDeathSound(choice)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(model.theme.accent.opacity(0.32)))
                    Spacer()
                    if let file, let preview = NSSound(contentsOf: file, byReference: true) {
                        Button {
                            sound?.stop()
                            sound = preview
                            preview.play()
                        } label: {
                            Image(systemName: "play.circle.fill").font(.system(size: 22))
                        }
                        .buttonStyle(PressableStyle(pressedScale: 0.8))
                        .help("Preview")
                        .padding(.trailing, 26)
                    }
                }
                Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Appearance

struct AppearanceView: View {
    @EnvironmentObject var model: LauncherModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Appearance", subtitle: "Make the launcher yours.")

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(LauncherTheme.allCases.enumerated()), id: \.element) { i, theme in
                    ChoiceTile(selected: model.theme == theme, index: i + 1) {
                        withAnimation(.bounce) { model.theme = theme }
                    } content: {
                        VStack(alignment: .leading, spacing: 10) {
                            ZStack {
                                LinearGradient(colors: theme.glows, startPoint: .topLeading, endPoint: .bottomTrailing)
                                Circle().fill(theme.accent).frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
                                    .shadow(color: theme.accent, radius: 6)
                            }
                            .frame(height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(theme.name).font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                    }
                }
            }

            GlassGroup {
                SettingRow(title: "Animated background", detail: "Slowly drifting colours behind the window") {
                    AccentToggle(isOn: $model.animatedBackground, accent: model.theme.accent)
                }
            }
            .appearIn(7)

            Text("Animations follow Reduce Motion in System Settings › Accessibility › Display.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var model: LauncherModel
    @State private var channel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Settings", subtitle: "How the launcher and Roblox are set up.")
            if let error = model.errorMessage {
                ErrorBanner(message: error) { withAnimation(.bounce) { model.errorMessage = nil } }
            }

            SectionLabel(text: "Launcher").appearIn(1)
            GlassGroup {
                SettingRow(title: "Close when Roblox starts", detail: "Get out of the way once the game is running") {
                    AccentToggle(isOn: $model.closeOnLaunch, accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Handle website links", detail: "Play buttons on roblox.com go through the launcher, so updates, mods and settings always apply") {
                    AccentToggle(isOn: Binding(get: { model.isLinkHandler }, set: { model.setLinkHandler($0) }),
                                 accent: model.theme.accent)
                }
            }
            .appearIn(2)

            SectionLabel(text: "Roblox", trailing: model.status.map { "Version \($0.installed ?? "not installed")" }).appearIn(3)
            GlassGroup {
                SettingRow(title: "Channel", detail: "LIVE for everyone; others usually need an account with access") {
                    TextField("LIVE", text: $channel)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.25)))
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
                    Button("Reinstall") { model.reinstall() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.busy || model.robloxRunning)
                }
                if model.busy {
                    GlowProgressBar(value: model.progress, accent: model.theme.accent)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                }
            }
            .appearIn(4)

            SectionLabel(text: "Files").appearIn(5)
            HStack {
                Button("Open Data Folder") { NSWorkspace.shared.open(model.supportURL) }
                Button("Show Log") { NSWorkspace.shared.open(model.logURL) }
                Button("Show Roblox in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.robloxAppURL]) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .appearIn(6)
        }
        .onAppear {
            channel = model.status?.channel ?? "LIVE"
            model.refreshLinkHandler()
        }
        .onChange(of: model.status?.channel) { channel = $0 ?? "LIVE" }
    }
}

// MARK: - Help

struct HelpView: View {
    @EnvironmentObject var model: LauncherModel

    private let faqs: [(String, String)] = [
        ("How do I join a game from the website?",
         "Turn on Handle website links in Settings, then press Play on roblox.com. The launcher updates Roblox, applies your mods and settings, then joins the game."),
        ("I changed a setting but nothing happened.",
         "Changes load when Roblox starts. If Roblox is open, use Restart Roblox. Some FastFlags do nothing because Roblox only honours flags on its allowlist."),
        ("Do mods survive Roblox updates?",
         "Yes. Updates replace Roblox's files, and the launcher puts your mods and FastFlags back before the game starts."),
        ("macOS says Roblox is damaged or modified.",
         "Mods and FastFlags change files inside Roblox.app, which macOS notices. Roblox still runs. Reinstall from Settings to get an untouched copy."),
        ("How do I uninstall everything?",
         "Run roblox-bootstrapper uninstall --purge in Terminal. It removes Roblox, this launcher and all settings."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Help", subtitle: "Answers to common questions.")

            VStack(spacing: 12) {
                ForEach(Array(faqs.enumerated()), id: \.offset) { i, faq in
                    FAQRow(question: faq.0, answer: faq.1).appearIn(i + 1)
                }
            }

            HStack {
                Button("Show Log") { NSWorkspace.shared.open(model.logURL) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Report a Problem") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/kirosthepuppy/macOS-bootstrapper/issues")!)
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
            .appearIn(7)

            VStack(alignment: .leading, spacing: 4) {
                Text("Bootstrapper \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 13, weight: .semibold))
                Text("Inspired by Bloxstrap and Fishstrap. Not affiliated with Roblox Corporation.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
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
                    Text(question).font(.system(size: 14.5, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 0.98))
            if open {
                Text(answer)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glass(corner: 16, highlighted: open, tint: .white.opacity(0.2))
        .clipped()
    }
}

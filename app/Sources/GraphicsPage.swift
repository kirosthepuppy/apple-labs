import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GraphicsPage: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var router: Router
    @State private var forward = true

    private var tab: Binding<GraphicsTab> {
        Binding(
            get: { router.graphicsTab },
            set: { next in
                let order = GraphicsTab.allCases
                forward = (order.firstIndex(of: next) ?? 0) > (order.firstIndex(of: router.graphicsTab) ?? 0)
                withAnimation(.bounce) { router.graphicsTab = next }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Graphics", subtitle: "Tune how Roblox runs and looks. Applied every time you play.") {
                SegmentedTabs(items: [
                    ("Presets", "square.stack.3d.up.fill", GraphicsTab.presets),
                    ("Engine", "slider.horizontal.3", .engine),
                    ("FastFlags", "flag.fill", .flags),
                ], selection: tab, accent: model.theme.accent)
            }
            RestartHint()
            if let error = model.flagsError { ErrorBanner(message: error) }

            TabContent(tab: router.graphicsTab, forward: forward) {
                switch router.graphicsTab {
                case .presets: PresetsTab()
                case .engine: EngineTab()
                case .flags: FlagsTab()
                }
            }
        }
        .onAppear { model.loadFlags() }
    }
}

// MARK: - Presets

private struct PresetsTab: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var router: Router
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(LauncherModel.presets.enumerated()), id: \.element.id) { i, preset in
                    ChoiceTile(selected: model.activePreset?.id == preset.id, index: i + 1) {
                        model.applyPreset(preset)
                    } content: {
                        VStack(alignment: .leading, spacing: 11) {
                            IconBadge(symbol: preset.symbol)
                            Text(preset.name).font(.ui(19, .heavy))
                            Text(preset.blurb)
                                .font(.ui(12.5))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2, reservesSpace: true)
                            VStack(spacing: 6) {
                                Meter(label: "Speed", value: preset.speed, delay: Double(i) * 0.05)
                                Meter(label: "Looks", value: preset.looks, delay: Double(i) * 0.05 + 0.1)
                            }
                            .padding(.top, 2)
                            FlowChips(items: preset.highlights)
                        }
                        .foregroundStyle(.white)
                    }
                }
            }

            HStack(spacing: 12) {
                Image(systemName: model.activePreset == nil ? "wand.and.stars" : "info.circle.fill")
                    .foregroundStyle(model.theme.accent)
                Text(model.activePreset == nil
                     ? "You're running a custom mix. Pick a preset to reset the engine settings, or keep fine-tuning."
                     : "Presets only change the engine settings. Fine-tune them any time.")
                Spacer()
                Button("Fine-tune") { withAnimation(.bounce) { router.graphicsTab = .engine } }
                    .buttonStyle(.chunkyGlass(size: .small))
            }
            .font(.ui(12.5))
            .foregroundStyle(.white.opacity(0.7))
            .padding(14)
            .glass(corner: 16)
            .appearIn(7)
        }
    }
}

/// Five little blocks that fill up with a springy stagger.
private struct Meter: View {
    @EnvironmentObject var model: LauncherModel
    let label: String
    let value: Int
    let delay: Double
    @State private var shown = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.ui(11, .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 42, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(i < value ? model.theme.accent : .white.opacity(0.12))
                        .frame(height: 7)
                        .scaleEffect(x: 1, y: shown || i >= value ? 1 : 0.1, anchor: .bottom)
                        .animation(.wobble.delay(delay + Double(i) * 0.05), value: shown)
                }
            }
        }
        .onAppear { shown = true }
    }
}

// MARK: - Engine

private struct EngineTab: View {
    @EnvironmentObject var model: LauncherModel

    private static let grassKeys = ["FIntFRMMinGrassDistance", "FIntFRMMaxGrassDistance"]

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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassGroup {
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
                SettingRow(title: "Remove grass", detail: "Hides terrain grass for a cleaner, faster view") {
                    AccentToggle(isOn: grassBinding, accent: model.theme.accent)
                }
                RowDivider()
                SettingRow(title: "Plain gray sky", detail: "Replaces the skybox with flat gray") {
                    AccentToggle(isOn: boolBinding("FFlagDebugSkyGray"), accent: model.theme.accent)
                }
            }
            .appearIn(2)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frame rate").font(.ui(14, .bold))
                    Text("Roblox no longer lets launchers set the frame rate. Set it in Roblox itself: open the menu in any game, then Settings › Maximum Frame Rate.")
                        .font(.ui(12.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glass(corner: 16)
            .appearIn(3)

            Text("Roblox only reads the FastFlags on its allowlist and ignores the rest. Changes load the next time Roblox starts; if it's open, the launcher restarts it when you press Play.")
                .font(.ui(12))
                .foregroundStyle(.white.opacity(0.5))
                .appearIn(4)
        }
    }
}

// MARK: - FastFlags editor

private struct FlagsTab: View {
    @EnvironmentObject var model: LauncherModel
    @State private var newName = ""
    @State private var newValue = ""
    @State private var search = ""
    @State private var showImport = false
    @State private var importText = ""
    @State private var importError: String?
    @State private var confirmClear = false

    private var names: [String] {
        let all = model.flags.keys.sorted()
        return search.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                    TextField("Search \(model.flags.count) flags", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(.black.opacity(0.28)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1)))

                Button { importText = ""; importError = nil; showImport = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.chunkyGlass(size: .small))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.exportFlagsJSON(), forType: .string)
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.doc")
                }
                .buttonStyle(.chunkyGlass(size: .small))
                .disabled(model.flags.isEmpty)
                Button { confirmClear = true } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.chunkyGlass(size: .small))
                .disabled(model.flags.isEmpty)
            }
            .appearIn(1)

            GlassGroup {
                if names.isEmpty {
                    Text(model.flags.isEmpty ? "No FastFlags yet. Add one below or import a JSON file." : "No flags match \"\(search)\".")
                        .font(.ui(13))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                    RowDivider()
                }
                ForEach(names, id: \.self) { name in
                    FlagRow(name: name, value: model.flags[name] ?? .string(""))
                        .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                    RowDivider()
                }
                HStack(spacing: 10) {
                    TextField("FlagName", text: $newName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.28)))
                    TextField("value", text: $newValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.28)))
                        .frame(width: 150)
                        .onSubmit(addFlag)
                    Button(action: addFlag) { Label("Add", systemImage: "plus") }
                        .buttonStyle(.chunky(model.theme.accent, size: .small))
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(14)
            }
            .animation(.bounce, value: model.flags.keys.sorted())
            .appearIn(2)

            Text("true/false and whole numbers are saved as booleans and integers; anything else is saved as text. Works with flags exported from Bloxstrap and Fishstrap.")
                .font(.ui(12))
                .foregroundStyle(.white.opacity(0.5))
        }
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
            if !LauncherModel.allowedFlags.contains(name) {
                Text("Ignored by Roblox")
                    .font(.ui(10.5, .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.orange.opacity(0.15)))
                    .fixedSize()
                    .help("Not on Roblox's FastFlag allowlist, so Roblox skips it")
            }
            Spacer()
            if case .bool(let b) = value {
                AccentToggle(isOn: Binding(get: { b }, set: { model.setFlag(name, .bool($0)) }), accent: model.theme.accent)
            } else {
                TextField("Value", text: $draft)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(focused ? 0.38 : 0.22)))
                    .frame(width: 150)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { isFocused in if !isFocused { commit() } }
            }
            Button {
                withAnimation(.bounce) { model.setFlag(name, nil) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 17))
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

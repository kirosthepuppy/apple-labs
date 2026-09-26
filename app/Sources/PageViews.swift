import AppKit
import SwiftUI
import UniformTypeIdentifiers

private func chooseFile(types: [UTType], message: String) -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = types
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message = message
    return panel.runModal() == .OK ? panel.url : nil
}

// MARK: - Mods

struct ModsView: View {
    @EnvironmentObject var model: LauncherModel
    @State private var confirmReset = false

    var body: some View {
        Form {
            if model.needsRestart && model.robloxRunning {
                RestartBanner()
            }
            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }

            Section {
                Picker("Death sound", selection: Binding(
                    get: { model.deathSound },
                    set: { choice in
                        if choice == .custom {
                            let types = ["ogg", "mp3", "wav"].compactMap { UTType(filenameExtension: $0) }
                            if let file = chooseFile(types: types, message: "Choose a sound to play when your character dies") {
                                model.setDeathSound(.custom, file: file)
                            }
                        } else {
                            model.setDeathSound(choice)
                        }
                    })
                ) {
                    Text("Default").tag(DeathSound.standard)
                    Text("Classic \"oof\"").tag(DeathSound.classic)
                    Text("Custom sound…").tag(DeathSound.custom)
                }
            } header: {
                Text("Sounds")
            } footer: {
                Text("\"Classic oof\" uses the oof.ogg that ships inside Roblox.").foregroundStyle(.secondary)
            }

            Section {
                Picker("Mouse cursor", selection: Binding(
                    get: { model.cursorStyle },
                    set: { choice in
                        if choice == .custom {
                            if let file = chooseFile(types: [.png, .jpeg, .tiff, .gif], message: "Choose a cursor image (square images look best)") {
                                model.setCursor(.custom, image: file)
                            }
                        } else {
                            model.setCursor(choice)
                        }
                    })
                ) {
                    Text("Default").tag(CursorStyle.standard)
                    Text("Classic arrow").tag(CursorStyle.classic)
                    Text("Custom image…").tag(CursorStyle.custom)
                }

                LabeledContent("Font") {
                    HStack {
                        Text(model.customFontName ?? "Roblox default").foregroundStyle(.secondary)
                        Button("Choose…") {
                            let types = ["ttf", "otf"].compactMap { UTType(filenameExtension: $0) }
                            if let file = chooseFile(types: types, message: "Choose a font to use for all in-game text") {
                                model.setFont(file)
                            }
                        }
                        if model.customFontName != nil {
                            Button("Reset") { model.setFont(nil) }
                        }
                    }
                }
            } header: {
                Text("Look")
            } footer: {
                Text("Custom cursors are scaled to 64×64. A custom font replaces every font Roblox uses.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Mod files") {
                    Text("\(model.modFileCount)").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Mods Folder") { NSWorkspace.shared.open(model.modsURL) }
                    Button("Re-apply Mods") { model.applyMods() }
                    Spacer()
                    Button("Remove All Mods…", role: .destructive) { confirmReset = true }
                        .disabled(model.modFileCount == 0)
                }
            } header: {
                Text("Your own mods")
            } footer: {
                Text("Anything you put in the mods folder replaces the matching file inside Roblox.app/Contents/Resources. For example, Modifications/content/sounds/ouch.ogg replaces the death sound. Mods are re-applied after every Roblox update, and Roblox's original files are restored when you remove them.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .id(model.modsRevision)
        .navigationTitle("Mods")
        .confirmationDialog("Remove all mods?", isPresented: $confirmReset) {
            Button("Remove All Mods", role: .destructive) { model.clearMods() }
        } message: {
            Text("This deletes everything in the mods folder and restores Roblox's original files.")
        }
    }
}

// MARK: - FastFlags

private struct Choice: Hashable {
    let label: String
    let value: Int
}

struct FlagsView: View {
    @EnvironmentObject var model: LauncherModel
    @State private var newName = ""
    @State private var newValue = ""
    @State private var showImport = false
    @State private var importText = ""
    @State private var importError: String?
    @State private var search = ""
    @State private var confirmClear = false

    private static let fpsKey = "DFIntTaskSchedulerTargetFps"
    private static let msaaKey = "FIntDebugForceMSAASamples"
    private static let textureEnabledKey = "DFFlagTextureQualityOverrideEnabled"
    private static let textureKey = "DFIntTextureQualityOverride"
    private static let grassKeys = ["FIntFRMMinGrassDistance", "FIntFRMMaxGrassDistance", "FIntRenderGrassDetailStrands"]

    private func intPicker(_ title: String, key: String, choices: [Choice]) -> some View {
        Picker(title, selection: Binding<Int>(
            get: {
                if case .int(let n)? = model.flags[key] { return n }
                if case .string(let s)? = model.flags[key], let n = Int(s) { return n }
                return -1
            },
            set: { model.setFlag(key, $0 == -1 ? nil : .int($0)) })
        ) {
            Text("Default").tag(-1)
            ForEach(choices, id: \.self) { Text($0.label).tag($0.value) }
            if case .int(let n)? = model.flags[key], !choices.contains(where: { $0.value == n }) {
                Text("Custom (\(n))").tag(n)
            }
        }
    }

    private func boolToggle(_ title: String, key: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.flags[key] == .bool(true) },
            set: { model.setFlag(key, $0 ? .bool(true) : nil) }))
    }

    private var textureBinding: Binding<Int> {
        Binding(
            get: {
                guard model.flags[Self.textureEnabledKey] == .bool(true),
                      case .int(let n)? = model.flags[Self.textureKey] else { return -1 }
                return n
            },
            set: { level in
                model.setFlags([
                    Self.textureEnabledKey: level == -1 ? nil : .bool(true),
                    Self.textureKey: level == -1 ? nil : .int(level),
                ])
            })
    }

    private var grassBinding: Binding<Bool> {
        Binding(
            get: { Self.grassKeys.allSatisfy { model.flags[$0] == .int(0) } },
            set: { off in
                var changes: [String: FlagValue?] = [:]
                for key in Self.grassKeys { changes[key] = off ? .int(0) : nil }
                model.setFlags(changes)
            })
    }

    private var filteredNames: [String] {
        let names = model.flags.keys.sorted()
        guard !search.isEmpty else { return names }
        return names.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Form {
            if model.needsRestart && model.robloxRunning {
                RestartBanner()
            }
            if let error = model.flagsError {
                ErrorBanner(message: error)
            }

            Section {
                intPicker("Frame rate limit", key: Self.fpsKey, choices: [
                    Choice(label: "30 FPS", value: 30), Choice(label: "60 FPS", value: 60),
                    Choice(label: "120 FPS", value: 120), Choice(label: "144 FPS", value: 144),
                    Choice(label: "165 FPS", value: 165), Choice(label: "240 FPS", value: 240),
                    Choice(label: "Unlimited", value: 9999),
                ])
                intPicker("Anti-aliasing (MSAA)", key: Self.msaaKey, choices: [
                    Choice(label: "Off", value: 1), Choice(label: "2×", value: 2),
                    Choice(label: "4×", value: 4), Choice(label: "8×", value: 8),
                ])
                Picker("Texture quality", selection: textureBinding) {
                    Text("Default").tag(-1)
                    Text("Lowest").tag(0)
                    Text("Low").tag(1)
                    Text("Medium").tag(2)
                    Text("High").tag(3)
                }
                boolToggle("Disable post-processing effects", key: "FFlagDisablePostFx")
                Toggle("Remove grass", isOn: grassBinding)
                boolToggle("Plain gray sky", key: "FFlagDebugSkyGray")
            } header: {
                Text("Engine settings")
            } footer: {
                Text("Roblox only honours FastFlags on its allowlist; others are silently ignored. Changes apply the next time Roblox starts.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if model.flags.isEmpty {
                    Text("No FastFlags set.").foregroundStyle(.secondary)
                } else {
                    if model.flags.count > 8 {
                        TextField("Search", text: $search, prompt: Text("Search flags"))
                    }
                    ForEach(filteredNames, id: \.self) { name in
                        FlagRow(name: name, value: model.flags[name] ?? .string(""))
                    }
                }
                HStack {
                    TextField("Flag name", text: $newName, prompt: Text("FlagName"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                    TextField("Value", text: $newValue, prompt: Text("value"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(maxWidth: 140)
                        .onSubmit(addFlag)
                    Button("Add", action: addFlag)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                HStack {
                    Text("All FastFlags")
                    Spacer()
                    Button("Import JSON…") { importText = ""; importError = nil; showImport = true }
                        .buttonStyle(.borderless)
                    Button("Copy as JSON") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.exportFlagsJSON(), forType: .string)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.flags.isEmpty)
                    Button("Clear All…") { confirmClear = true }
                        .buttonStyle(.borderless)
                        .disabled(model.flags.isEmpty)
                }
            } footer: {
                Text("Values of true/false and whole numbers are saved as booleans and integers; anything else is saved as text.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("FastFlags")
        .onAppear { model.loadFlags() }
        .confirmationDialog("Remove all FastFlags?", isPresented: $confirmClear) {
            Button("Remove All", role: .destructive) { model.replaceFlags([:]) }
        }
        .sheet(isPresented: $showImport) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import FastFlags").font(.headline)
                Text("Paste a JSON object of flags, such as one exported from Bloxstrap or Fishstrap. Existing flags with the same name are replaced.")
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
    }

    private func addFlag() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.setFlag(name, FlagValue(parsing: newValue))
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
        HStack {
            Text(name)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            if case .bool(let b) = value {
                Toggle("", isOn: Binding(get: { b }, set: { model.setFlag(name, .bool($0)) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            } else {
                TextField("Value", text: $draft)
                    .labelsHidden()
                    .font(.body.monospaced())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { isFocused in if !isFocused { commit() } }
            }
            Button {
                model.setFlag(name, nil)
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove \(name)")
        }
        .onAppear { draft = value.text }
        .onChange(of: value) { draft = $0.text }
    }

    private func commit() {
        let parsed = FlagValue(parsing: draft)
        if parsed != value { model.setFlag(name, parsed) }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var model: LauncherModel
    @State private var channel = ""

    var body: some View {
        Form {
            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }

            Section("Launcher") {
                Toggle("Close the launcher once Roblox starts", isOn: $model.closeOnLaunch)
                Toggle("Open Roblox website links with this launcher", isOn: Binding(
                    get: { model.isLinkHandler },
                    set: { model.setLinkHandler($0) }))
            }

            Section {
                TextField("Channel", text: $channel, prompt: Text("LIVE"))
                    .multilineTextAlignment(.trailing)
                    .onSubmit { model.setConfig("CHANNEL", channel.isEmpty ? "LIVE" : channel) }
                Picker("Install location", selection: Binding(
                    get: { model.status?.installDir ?? "/Applications" },
                    set: { model.setConfig("INSTALL_DIR", $0) })
                ) {
                    Text("Applications (all users)").tag("/Applications")
                    Text("Applications in your home folder").tag(NSHomeDirectory() + "/Applications")
                    if let dir = model.status?.installDir,
                       dir != "/Applications", dir != NSHomeDirectory() + "/Applications" {
                        Text(dir).tag(dir)
                    }
                }
                Picker("Build", selection: Binding(
                    get: { model.status?.archSetting ?? "auto" },
                    set: { model.setConfig("ARCH", $0) })
                ) {
                    Text("Automatic").tag("auto")
                    Text("Apple silicon (arm64)").tag("arm64")
                    Text("Intel (x86_64)").tag("x86_64")
                }
                HStack {
                    Spacer()
                    Button("Reinstall Roblox") { model.reinstall() }
                        .disabled(model.busy || model.robloxRunning)
                }
                if model.busy {
                    TaskProgress()
                }
            } header: {
                Text("Roblox")
            } footer: {
                Text("Channel, location and build changes take effect on the next update. Reinstall to switch now. Non-LIVE channels usually need an account with access.")
                    .foregroundStyle(.secondary)
            }

            Section("Files") {
                HStack {
                    Button("Open Data Folder") { NSWorkspace.shared.open(model.supportURL) }
                    Button("Show Log") { NSWorkspace.shared.open(model.logURL) }
                    Button("Show Roblox in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.robloxAppURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            channel = model.status?.channel ?? "LIVE"
            model.refreshLinkHandler()
        }
        .onChange(of: model.status?.channel) { channel = $0 ?? "LIVE" }
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
            Text("Roblox Bootstrapper").font(.title.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .foregroundStyle(.secondary)
            Text("Keeps Roblox up to date and brings Bloxstrap-style FastFlags and mods to macOS.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Link("github.com/kirosthepuppy/macOS-bootstrapper",
                 destination: URL(string: "https://github.com/kirosthepuppy/macOS-bootstrapper")!)
            Spacer()
            Text("Inspired by Bloxstrap and Fishstrap. Not affiliated with Roblox Corporation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StylePage: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var router: Router
    @State private var forward = true

    private var tab: Binding<StyleTab> {
        Binding(
            get: { router.styleTab },
            set: { next in
                let order = StyleTab.allCases
                forward = (order.firstIndex(of: next) ?? 0) > (order.firstIndex(of: router.styleTab) ?? 0)
                withAnimation(.bounce) { router.styleTab = next }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Style", subtitle: "Make Roblox look and sound your way. Mods come back after every update.") {
                SegmentedTabs(items: [
                    ("Cursor", "cursorarrow.rays", StyleTab.cursor),
                    ("Font", "textformat", .font),
                    ("Sound", "speaker.wave.2.fill", .sound),
                    ("Files", "folder.fill", .files),
                ], selection: tab, accent: model.theme.accent)
            }
            RestartHint()
            if let error = model.errorMessage {
                ErrorBanner(message: error) { withAnimation(.bounce) { model.errorMessage = nil } }
            }

            TabContent(tab: router.styleTab, forward: forward) {
                switch router.styleTab {
                case .cursor: CursorTab()
                case .font: FontTab()
                case .sound: SoundTab()
                case .files: FilesTab()
                }
            }
        }
    }
}

// MARK: - Cursor

private struct CursorTab: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                tile(.standard, title: "Default", detail: "Roblox's current pointer", index: 1,
                     image: NSImage(contentsOf: model.originalResource(LauncherModel.cursorPaths[0])))
                tile(.classic, title: "Classic arrow", detail: "The black arrow from classic Roblox", index: 2,
                     image: NSImage(contentsOf: model.robloxResource(LauncherModel.classicCursorSources[0])))
                tile(.custom, title: "Custom image", detail: "Any PNG or JPEG, scaled to 64×64", index: 3,
                     image: model.cursorStyle == .custom ? NSImage(contentsOf: model.modURL(LauncherModel.cursorPaths[0])) : nil)
            }
            if model.cursorStyle == .custom {
                Button { pickCustom() } label: { Label("Choose a different image", systemImage: "photo") }
                    .buttonStyle(.chunkyGlass(size: .small))
                    .appearIn(4)
            }
        }
        .id(model.modsRevision)
    }

    private func tile(_ style: CursorStyle, title: String, detail: String, index: Int, image: NSImage?) -> some View {
        ChoiceTile(selected: model.cursorStyle == style, index: index) {
            if style == .custom { pickCustom() } else { model.setCursor(style) }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                CursorPreview(image: image)
                    .frame(height: 124)
                Text(title).font(.system(size: 17, weight: .heavy, design: .rounded))
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

/// A little "screen" with the cursor hovering over a stud grid; the cursor
/// follows the pointer while you hover the preview.
private struct CursorPreview: View {
    let image: NSImage?
    @State private var point = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.55, green: 0.8, blue: 0.45)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(0.55)
                StudPattern().opacity(0.6)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                        .position(x: geo.size.width * point.x, y: geo.size.height * point.y)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    withAnimation(.snappy) {
                        point = CGPoint(x: min(max(p.x / geo.size.width, 0.15), 0.85),
                                        y: min(max(p.y / geo.size.height, 0.2), 0.8))
                    }
                case .ended:
                    withAnimation(.wobble) { point = CGPoint(x: 0.5, y: 0.5) }
                }
            }
        }
    }
}

/// A static grid of studs, like the top of a Roblox brick.
struct StudPattern: View {
    var spacing: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 3, width: 8, height: 8)), with: .color(.black.opacity(0.15)))
                    context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(.white.opacity(0.18)))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

// MARK: - Font

private struct FontTab: View {
    @EnvironmentObject var model: LauncherModel
    @State private var search = ""

    private var filtered: [MacFont] {
        search.isEmpty ? model.macFonts : model.macFonts.filter { $0.family.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text((model.customFontName ?? "Roblox default").uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button {
                        let types = ["ttf", "otf"].compactMap { UTType(filenameExtension: $0) }
                        if let file = chooseFile(types: types, message: "Choose a .ttf or .otf font") {
                            withAnimation(.bounce) { model.setFont(file) }
                        }
                    } label: { Label("Font File…", systemImage: "doc.badge.plus") }
                        .buttonStyle(.chunkyGlass(size: .small))
                    if model.customFontName != nil {
                        Button { withAnimation(.bounce) { model.setFont(nil) } } label: {
                            Label("Reset", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.chunkyGlass(size: .small))
                    }
                }
                Text("The quick brown fox jumps over the lazy dog")
                    .font(model.customFontPreview(size: 34) ?? .system(size: 34, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("ABCDEFGHIJKLM  0123456789  !?&")
                    .font(model.customFontPreview(size: 18) ?? .system(size: 18, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(22)
            .glass(corner: 22)
            .id(model.modsRevision)
            .appearIn(1)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Search \(model.macFonts.count) fonts on your Mac", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(.black.opacity(0.28)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
            .appearIn(2)

            if model.macFonts.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(30)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(filtered) { font in
                        FontCard(font: font, selected: model.customFontName == font.family) {
                            withAnimation(.bounce) { model.setFont(font.url, name: font.family) }
                        }
                    }
                }
                .appearIn(3)
            }
        }
        .onAppear { model.loadMacFonts() }
    }
}

private struct FontCard: View {
    @EnvironmentObject var model: LauncherModel
    let font: MacFont
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Aa")
                    .font(.custom(font.postScriptName, size: 30))
                    .lineLimit(1)
                    .frame(height: 40, alignment: .leading)
                Text(font.family)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glass(corner: 16, highlighted: selected || hovering, tint: selected ? model.theme.accent : .white.opacity(0.3))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, model.theme.accent)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.94))
        .onHover { h in withAnimation(.bounce) { hovering = h } }
        .help(font.family)
    }
}

// MARK: - Sound

/// Plays sound previews and remembers which one is playing.
final class SoundPreview: NSObject, ObservableObject, NSSoundDelegate {
    @Published private(set) var playing: URL?
    private var sound: NSSound?

    func toggle(_ url: URL) {
        let wasPlaying = playing == url
        sound?.stop()
        sound = nil
        playing = nil
        guard !wasPlaying, let next = NSSound(contentsOf: url, byReference: true) else { return }
        next.delegate = self
        sound = next
        playing = url
        next.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        DispatchQueue.main.async {
            if self.sound === sound {
                self.sound = nil
                self.playing = nil
            }
        }
    }
}

private struct SoundTab: View {
    @EnvironmentObject var model: LauncherModel
    @StateObject private var preview = SoundPreview()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What you hear when your character resets.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .appearIn(1)
            HStack(spacing: 16) {
                soundTile(.standard, title: "Default", detail: "Roblox's current sound", symbol: "speaker.wave.2.fill", index: 2,
                          file: model.originalResource(LauncherModel.deathSoundPath))
                soundTile(.classic, title: "Classic \u{201C}oof\u{201D}", detail: "The one everyone remembers", symbol: "face.dashed.fill", index: 3,
                          file: model.robloxResource("content/sounds/oof.ogg"))
                soundTile(.custom, title: "Custom sound", detail: "Any .ogg, .mp3 or .wav", symbol: "waveform", index: 4,
                          file: model.deathSound == .custom ? model.modURL(LauncherModel.deathSoundPath) : nil)
            }
        }
        .id(model.modsRevision)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    IconBadge(symbol: symbol)
                    Spacer()
                    if let file, FileManager.default.fileExists(atPath: file.path) {
                        Button { preview.toggle(file) } label: {
                            Group {
                                if preview.playing == file {
                                    Equalizer(color: .white)
                                } else {
                                    Image(systemName: "play.fill").font(.system(size: 13, weight: .heavy))
                                }
                            }
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(model.theme.accent))
                            .overlay(Circle().strokeBorder(.white.opacity(0.35)))
                            .shadow(color: model.theme.accent.opacity(0.6), radius: 6)
                        }
                        .buttonStyle(PressableStyle(pressedScale: 0.8))
                        .help(preview.playing == file ? "Stop" : "Preview")
                        .padding(.trailing, 30)
                    }
                }
                Text(title).font(.system(size: 17, weight: .heavy, design: .rounded))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)
        }
    }
}

/// Three bouncing bars, shown while a sound preview plays.
private struct Equalizer: View {
    let color: Color
    @State private var up = false
    private let high: [CGFloat] = [14, 8, 12]
    private let low: [CGFloat] = [5, 13, 6]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 3.5, height: up ? high[i] : low[i])
                    .animation(.easeInOut(duration: 0.28 + Double(i) * 0.07).repeatForever(autoreverses: true), value: up)
            }
        }
        .frame(height: 14)
        .onAppear { up = true }
    }
}

// MARK: - Files

private struct FilesTab: View {
    @EnvironmentObject var model: LauncherModel
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    IconBadge(symbol: "folder.fill", size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Modifications folder").font(.system(size: 17, weight: .heavy, design: .rounded))
                        Text("\(model.modFileCount) file\(model.modFileCount == 1 ? "" : "s") · mirrors Roblox.app/Contents/Resources")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                Text("Drop files in with the same path they have inside Roblox. For example, content/sounds/ouch.ogg replaces the death sound and content/textures/… replaces textures. Removing a file puts Roblox's original back.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { NSWorkspace.shared.open(model.modsURL) } label: { Label("Open Folder", systemImage: "folder") }
                        .buttonStyle(.chunky(model.theme.accent))
                    Button { model.applyMods() } label: { Label("Re-apply", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.chunkyGlass())
                    Spacer()
                    Button { confirmReset = true } label: { Label("Remove All", systemImage: "trash") }
                        .buttonStyle(.chunkyGlass())
                        .disabled(model.modFileCount == 0)
                }
            }
            .padding(22)
            .glass(corner: 22)
            .appearIn(1)
        }
        .id(model.modsRevision)
        .confirmationDialog("Remove all mods?", isPresented: $confirmReset) {
            Button("Remove All Mods", role: .destructive) { model.clearMods() }
        } message: {
            Text("This deletes everything in the mods folder and restores Roblox's original files, including your cursor, font and death sound.")
        }
    }
}

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

/// A selectable card used for presets, cursors, sounds and themes. It
/// squishes when clicked and its check mark springs in.
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
            withTransaction(t) { bump = 0.93 }
            DispatchQueue.main.async { withAnimation(.wobble) { bump = 1 } }
            action()
        } label: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(18)
                .glass(corner: 22, highlighted: selected || hovering,
                       tint: selected ? model.theme.accent : .white.opacity(0.3))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(model.theme.accent))
                            .overlay(Circle().strokeBorder(.white.opacity(0.4)))
                            .shadow(color: model.theme.accent.opacity(0.7), radius: 6)
                            .padding(12)
                            .transition(.scale(scale: 0.1).combined(with: .opacity))
                    }
                }
                .shadow(color: selected ? model.theme.accent.opacity(0.4) : .black.opacity(hovering ? 0.25 : 0),
                        radius: 16, y: selected ? 0 : 8)
                .scaleEffect((hovering ? 1.025 : 1) * bump)
                .offset(y: hovering ? -3 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.96))
        .onHover { h in withAnimation(.bounce) { hovering = h } }
        .animation(.wobble, value: selected)
        .appearIn(index)
    }
}

/// A rounded icon tile in the theme accent.
struct IconBadge: View {
    @EnvironmentObject var model: LauncherModel
    let symbol: String
    var size: CGFloat = 46

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [model.theme.accent.mixed(with: .white, by: 0.2), model.theme.accent.opacity(0.75)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(0.25)))
    }
}

/// Shown on settings pages when a change needs Roblox to restart.
struct RestartHint: View {
    @EnvironmentObject var model: LauncherModel

    var body: some View {
        if model.needsRestart && model.robloxRunning {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(model.theme.accent)
                Text("Roblox is open. Restart it to use your changes.")
                    .font(.ui(13.5, .semibold))
                Spacer()
                Button("Restart Roblox") { model.restartRoblox() }
                    .buttonStyle(.chunky(model.theme.accent, size: .small))
                    .disabled(model.busy)
            }
            .padding(14)
            .glass(corner: 18, highlighted: true, tint: model.theme.accent.opacity(0.7))
            .transition(.move(edge: .top).combined(with: .opacity))
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
                    .font(.ui(11.5, .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.1)))
            }
        }
    }
}

/// Wraps a page's sub-tab content so switching tabs slides in from the side
/// the new tab is on.
struct TabContent<Tab: Hashable, Content: View>: View {
    let tab: Tab
    let forward: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .id(tab)
            .transition(.asymmetric(
                insertion: .offset(x: forward ? 44 : -44).combined(with: .opacity),
                removal: .opacity.animation(.easeOut(duration: 0.1))))
    }
}

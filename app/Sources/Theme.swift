import AppKit
import SwiftUI

// MARK: - Themes

enum LauncherTheme: String, CaseIterable, Identifiable {
    case sunset, ocean, aurora, candy, midnight

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .aurora: return "Aurora"
        case .candy: return "Candy"
        case .midnight: return "Midnight"
        }
    }

    /// Three glow colours drifting behind the window content.
    var glows: [Color] {
        switch self {
        case .sunset: return [rgb(0.93, 0.50, 0.16), rgb(0.42, 0.22, 0.45), rgb(0.12, 0.34, 0.78)]
        case .ocean: return [rgb(0.05, 0.60, 0.75), rgb(0.10, 0.25, 0.70), rgb(0.30, 0.15, 0.60)]
        case .aurora: return [rgb(0.10, 0.75, 0.50), rgb(0.08, 0.45, 0.55), rgb(0.45, 0.20, 0.70)]
        case .candy: return [rgb(0.95, 0.35, 0.60), rgb(0.55, 0.25, 0.85), rgb(0.98, 0.60, 0.30)]
        case .midnight: return [rgb(0.25, 0.28, 0.45), rgb(0.12, 0.14, 0.28), rgb(0.30, 0.22, 0.40)]
        }
    }

    var accent: Color {
        switch self {
        case .sunset, .ocean, .midnight: return rgb(0.20, 0.47, 1.00)
        case .aurora: return rgb(0.12, 0.74, 0.52)
        case .candy: return rgb(0.93, 0.33, 0.62)
        }
    }

    var base: Color { rgb(0.06, 0.07, 0.10) }

    /// The deep end of the hero card gradient.
    var heroGlow: Color {
        switch self {
        case .sunset, .ocean, .midnight: return rgb(0.05, 0.12, 0.55)
        case .aurora: return rgb(0.03, 0.35, 0.30)
        case .candy: return rgb(0.40, 0.08, 0.40)
        }
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

extension Animation {
    /// The launcher's signature springy motion.
    static let bounce = Animation.spring(response: 0.45, dampingFraction: 0.62)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.78)
    static let wobble = Animation.spring(response: 0.5, dampingFraction: 0.42)
}

// MARK: - Background

struct AnimatedBackground: View {
    let theme: LauncherTheme
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            GlowLayers(colors: theme.glows, base: theme.base, animated: animated && !reduceMotion)
            // A soft vignette keeps the edges from getting too bright.
            GeometryReader { geo in
                RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center,
                               startRadius: geo.size.width * 0.2, endRadius: geo.size.width * 0.8)
            }
        }
        .ignoresSafeArea()
    }
}

/// Soft colour glows drawn and animated by Core Animation, so the drifting
/// background costs the app no redraws.
private struct GlowLayers: NSViewRepresentable {
    let colors: [Color]
    let base: Color
    let animated: Bool

    func makeNSView(context: Context) -> GlowView { GlowView() }

    func updateNSView(_ view: GlowView, context: Context) {
        view.update(colors: colors.map { NSColor($0) }, base: NSColor(base), animated: animated)
    }

    final class GlowView: NSView {
        private let glows = (0..<3).map { _ in CAGradientLayer() }
        private var animated = false
        private var colors: [NSColor] = []

        // Positions (as fractions of the view) each glow drifts between, and its size.
        private let paths: [(from: CGPoint, to: CGPoint, size: CGFloat)] = [
            (CGPoint(x: 0.10, y: 0.85), CGPoint(x: 0.25, y: 0.65), 1.10),
            (CGPoint(x: 0.45, y: 0.70), CGPoint(x: 0.58, y: 0.52), 0.90),
            (CGPoint(x: 0.85, y: 0.15), CGPoint(x: 0.70, y: 0.30), 1.20),
        ]

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for glow in glows {
                glow.type = .radial
                glow.startPoint = CGPoint(x: 0.5, y: 0.5)
                glow.endPoint = CGPoint(x: 1, y: 1)
                glow.locations = [0, 0.55, 1]
                layer?.addSublayer(glow)
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(colors: [NSColor], base: NSColor, animated: Bool) {
            let changed = colors != self.colors
            CATransaction.begin()
            CATransaction.setAnimationDuration(changed && !self.colors.isEmpty ? 1.2 : 0)
            layer?.backgroundColor = base.cgColor
            for (glow, color) in zip(glows, colors) {
                glow.colors = [color.withAlphaComponent(0.85).cgColor,
                               color.withAlphaComponent(0.35).cgColor,
                               color.withAlphaComponent(0).cgColor]
            }
            CATransaction.commit()
            self.colors = colors
            if animated != self.animated {
                self.animated = animated
                restartDrift()
            }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (glow, path) in zip(glows, paths) {
                let side = max(bounds.width, bounds.height) * path.size
                glow.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                glow.position = point(path.from)
            }
            CATransaction.commit()
            restartDrift()
        }

        private func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: bounds.width * p.x, y: bounds.height * p.y)
        }

        private func restartDrift() {
            for (i, (glow, path)) in zip(glows, paths).enumerated() {
                glow.removeAnimation(forKey: "drift")
                guard animated else { continue }
                let drift = CABasicAnimation(keyPath: "position")
                drift.fromValue = NSValue(point: point(path.from))
                drift.toValue = NSValue(point: point(path.to))
                drift.duration = 12 + Double(i) * 3
                drift.autoreverses = true
                drift.repeatCount = .infinity
                drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glow.add(drift, forKey: "drift")
            }
        }
    }
}

// MARK: - Surfaces

struct GlassBackground: ViewModifier {
    var corner: CGFloat = 18
    var highlighted = false
    var tint: Color = .white

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.white.opacity(highlighted ? 0.10 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(highlighted ? tint.opacity(0.9) : Color.white.opacity(0.08), lineWidth: highlighted ? 2 : 1)
            )
    }
}

extension View {
    func glass(corner: CGFloat = 18, highlighted: Bool = false, tint: Color = .white) -> some View {
        modifier(GlassBackground(corner: corner, highlighted: highlighted, tint: tint))
    }

    /// Springs the view in when it first appears, staggered by `index`.
    func appearIn(_ index: Int = 0) -> some View { modifier(AppearIn(index: index)) }
}

struct AppearIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 22)
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .onAppear {
                if reduceMotion { shown = true; return }
                withAnimation(.bounce.delay(Double(index) * 0.045)) { shown = true }
            }
    }
}

// MARK: - Buttons

/// Squishes on press and springs back.
struct PressableStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.wobble, value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var accent: Color
    var large = true

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration, accent: accent, large: large)
    }

    private struct PrimaryButton: View {
        let configuration: Configuration
        let accent: Color
        let large: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: large ? 18 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, large ? 30 : 16)
                .padding(.vertical, large ? 13 : 8)
                .background(
                    RoundedRectangle(cornerRadius: large ? 13 : 10, style: .continuous)
                        .fill(LinearGradient(colors: [accent.opacity(hovering ? 1 : 0.95), accent.opacity(0.78)],
                                             startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: large ? 13 : 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: accent.opacity(isEnabled ? (hovering ? 0.65 : 0.4) : 0), radius: hovering ? 20 : 12, y: 5)
                .scaleEffect(configuration.isPressed ? 0.92 : (hovering && isEnabled ? 1.045 : 1))
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.wobble, value: configuration.isPressed)
                .animation(.bounce, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButton(configuration: configuration)
    }

    private struct SecondaryButton: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(isEnabled ? 0.92 : 0.4))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(hovering && isEnabled ? 0.16 : 0.09))
                )
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1)))
                .scaleEffect(configuration.isPressed ? 0.93 : 1)
                .animation(.wobble, value: configuration.isPressed)
                .animation(.snappy, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Status

struct StatusPill: View {
    let state: LauncherState
    var text: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            PulseDot(color: state.color, pulsing: state.pulses && !reduceMotion)
                .frame(width: 8, height: 8)
            Text(text ?? state.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Capsule().fill(.black.opacity(0.3)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        .animation(.bounce, value: state)
    }
}

struct GlowProgressBar: View {
    let value: Double?
    let accent: Color
    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                if let value {
                    Capsule()
                        .fill(LinearGradient(colors: [accent.opacity(0.8), accent, .white.opacity(0.9)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, geo.size.width * value))
                        .shadow(color: accent.opacity(0.8), radius: 8)
                        .animation(.snappy, value: value)
                } else {
                    Capsule()
                        .fill(LinearGradient(colors: [accent.opacity(0), accent, accent.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * 0.35)
                        .offset(x: sweep ? geo.size.width * 0.65 : 0)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { sweep = true }
                        }
                }
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Page chrome

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appearIn(0)
    }
}

struct SectionLabel: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text).font(.system(size: 16, weight: .semibold, design: .rounded))
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

/// A row inside a glass group: title and optional detail on the left, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .glass()
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.leading, 18)
    }
}

/// A row of choices with a selection capsule that springs between them.
struct ChipPicker<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    let accent: Color
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let selected = option.value == selection
                Button {
                    withAnimation(.bounce) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                Capsule().fill(accent)
                                    .shadow(color: accent.opacity(0.6), radius: 6)
                                    .matchedGeometryEffect(id: "chip", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(pressedScale: 0.9))
            }
        }
        .padding(3)
        .background(Capsule().fill(.black.opacity(0.25)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }
}

/// A springy on/off switch in the theme accent: the knob stretches while
/// pressed and overshoots when it lands.
struct AccentToggle: View {
    @Binding var isOn: Bool
    let accent: Color
    @State private var pressing = false
    @State private var hovering = false

    var body: some View {
        let width: CGFloat = 46, height: CGFloat = 26, knob: CGFloat = 20
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? accent : Color.white.opacity(hovering ? 0.2 : 0.14))
                .overlay(Capsule().strokeBorder(.white.opacity(isOn ? 0.25 : 0.1)))
                .shadow(color: isOn ? accent.opacity(0.55) : .clear, radius: 8)
            Capsule()
                .fill(.white)
                .frame(width: pressing ? knob + 7 : knob, height: knob)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .padding(3)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule())
        .onHover { h in withAnimation(.snappy) { hovering = h } }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressing { withAnimation(.snappy) { pressing = true } } }
                .onEnded { _ in
                    withAnimation(.wobble) {
                        pressing = false
                        isOn.toggle()
                    }
                }
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAction { isOn.toggle() }
    }
}

// MARK: - Roblox icon

/// Loads an app's own .icns so newer macOS versions don't draw it on a gray
/// plate the way NSWorkspace icons for older-style icons are.
func bundleIcon(_ appURL: URL) -> NSImage? {
    let bundle = Bundle(url: appURL)
    let name = (bundle?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String) ?? "AppIcon"
    let file = appURL.appendingPathComponent("Contents/Resources")
        .appendingPathComponent(name.hasSuffix(".icns") ? name : name + ".icns")
    return NSImage(contentsOf: file)
}

struct RobloxIcon: View {
    @EnvironmentObject var model: LauncherModel
    var size: CGFloat

    var body: some View {
        let image = bundleIcon(model.robloxAppURL)
            ?? bundleIcon(Bundle.main.bundleURL)
            ?? NSApp.applicationIconImage ?? NSImage()
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct ErrorBanner: View {
    let message: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 13)).textSelection(.enabled)
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.orange.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.orange.opacity(0.3)))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

// MARK: - Core Animation loops
//
// Endless SwiftUI animations redraw the view every frame. These run on the
// render server instead, so an idle launcher uses almost no CPU.

/// The status dot, with a ring that ripples outward while `pulsing`.
struct PulseDot: NSViewRepresentable {
    let color: Color
    let pulsing: Bool

    func makeNSView(context: Context) -> DotView { DotView() }
    func updateNSView(_ view: DotView, context: Context) { view.update(color: NSColor(color), pulsing: pulsing) }

    final class DotView: NSView {
        private let dot = CALayer()
        private let ring = CALayer()
        private var pulsing: Bool?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            for l in [ring, dot] {
                l.cornerRadius = 4
                layer?.addSublayer(l)
            }
            dot.shadowOpacity = 0.9
            dot.shadowRadius = 4
            dot.shadowOffset = .zero
        }

        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize { NSSize(width: 8, height: 8) }

        override func layout() {
            super.layout()
            for l in [ring, dot] {
                l.frame = CGRect(x: (bounds.width - 8) / 2, y: (bounds.height - 8) / 2, width: 8, height: 8)
            }
        }

        func update(color: NSColor, pulsing: Bool) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            dot.backgroundColor = color.cgColor
            dot.shadowColor = color.cgColor
            ring.backgroundColor = color.withAlphaComponent(0.55).cgColor
            CATransaction.commit()
            guard pulsing != self.pulsing else { return }
            self.pulsing = pulsing
            ring.removeAllAnimations()
            ring.opacity = 0
            guard pulsing else { return }
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 2.6
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 1.3
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(group, forKey: "pulse")
        }
    }
}

/// An image that floats up and down with a coloured glow beneath it.
struct BobbingImage: NSViewRepresentable {
    let image: NSImage
    let glow: Color
    var amplitude: CGFloat = 9
    var period: Double = 2.8
    var animated = true

    func makeNSView(context: Context) -> BobView { BobView() }

    func updateNSView(_ view: BobView, context: Context) {
        view.update(image: image, glow: NSColor(glow), amplitude: amplitude, period: period, animated: animated)
    }

    final class BobView: NSView {
        private let imageLayer = CALayer()
        private var animated: Bool?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            imageLayer.contentsGravity = .resizeAspect
            imageLayer.shadowOpacity = 0.55
            imageLayer.shadowRadius = 30
            imageLayer.shadowOffset = CGSize(width: 0, height: -14)
            layer?.addSublayer(imageLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.frame = bounds
            imageLayer.contentsScale = window?.backingScaleFactor ?? 2
            CATransaction.commit()
        }

        func update(image: NSImage, glow: NSColor, amplitude: CGFloat, period: Double, animated: Bool) {
            imageLayer.contents = image
            imageLayer.shadowColor = glow.cgColor
            guard animated != self.animated else { return }
            self.animated = animated
            imageLayer.removeAnimation(forKey: "bob")
            guard animated else { return }
            let bob = CABasicAnimation(keyPath: "transform.translation.y")
            bob.fromValue = -amplitude
            bob.toValue = amplitude
            bob.duration = period
            bob.autoreverses = true
            bob.repeatCount = .infinity
            bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageLayer.add(bob, forKey: "bob")
        }
    }
}

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
        case .aurora: return rgb(0.12, 0.70, 0.48)
        case .candy: return rgb(0.90, 0.30, 0.60)
        }
    }

    var base: Color { rgb(0.06, 0.07, 0.10) }

    /// The deep end of the hero gradient when there is no game artwork.
    var heroGlow: Color {
        switch self {
        case .sunset, .ocean, .midnight: return rgb(0.05, 0.12, 0.55)
        case .aurora: return rgb(0.03, 0.35, 0.30)
        case .candy: return rgb(0.40, 0.08, 0.40)
        }
    }

    var confetti: [Color] { glows + [accent, .white, rgb(1.0, 0.82, 0.25)] }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

extension Color {
    /// Blends toward another colour, e.g. `.white` for a highlight or `.black` for a shadow.
    func mixed(with other: NSColor, by fraction: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return Color(nsColor: base.blended(withFraction: fraction, of: other) ?? base)
    }
}

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
    var studs = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BackdropLayers(colors: theme.glows, base: theme.base, animated: animated && !reduceMotion, studs: studs)
            // A soft vignette keeps the edges from getting too bright.
            GeometryReader { geo in
                RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center,
                               startRadius: geo.size.width * 0.2, endRadius: geo.size.width * 0.8)
            }
        }
        .ignoresSafeArea()
    }
}

/// Colour glows and a grid of Roblox-style studs, drawn and animated by Core
/// Animation so the moving background costs the app no redraws.
private struct BackdropLayers: NSViewRepresentable {
    let colors: [Color]
    let base: Color
    let animated: Bool
    let studs: Bool

    func makeNSView(context: Context) -> BackdropView { BackdropView() }

    func updateNSView(_ view: BackdropView, context: Context) {
        view.update(colors: colors.map { NSColor($0) }, base: NSColor(base), animated: animated, studs: studs)
    }

    final class BackdropView: NSView {
        private let glows = (0..<3).map { _ in CAGradientLayer() }
        private let studLayer = CALayer()
        private var animated: Bool?
        private var colors: [NSColor] = []
        private var studArea = CGSize.zero
        private static let tile: CGFloat = 30

        // Positions (as fractions of the view) each glow drifts between, and its size.
        private let paths: [(from: CGPoint, to: CGPoint, size: CGFloat)] = [
            (CGPoint(x: 0.10, y: 0.85), CGPoint(x: 0.25, y: 0.65), 1.10),
            (CGPoint(x: 0.45, y: 0.70), CGPoint(x: 0.58, y: 0.52), 0.90),
            (CGPoint(x: 0.85, y: 0.15), CGPoint(x: 0.70, y: 0.30), 1.20),
        ]

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            for glow in glows {
                glow.type = .radial
                glow.startPoint = CGPoint(x: 0.5, y: 0.5)
                glow.endPoint = CGPoint(x: 1, y: 1)
                glow.locations = [0, 0.55, 1]
                layer?.addSublayer(glow)
            }
            studLayer.anchorPoint = .zero
            layer?.addSublayer(studLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(colors: [NSColor], base: NSColor, animated: Bool, studs: Bool) {
            let changed = colors != self.colors
            CATransaction.begin()
            CATransaction.setAnimationDuration(changed && !self.colors.isEmpty ? 1.2 : 0)
            layer?.backgroundColor = base.cgColor
            for (glow, color) in zip(glows, colors) {
                glow.colors = [color.withAlphaComponent(0.85).cgColor,
                               color.withAlphaComponent(0.35).cgColor,
                               color.withAlphaComponent(0).cgColor]
            }
            studLayer.opacity = studs ? 1 : 0
            CATransaction.commit()
            self.colors = colors
            if animated != self.animated {
                self.animated = animated
                restartMotion()
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
            renderStudsIfNeeded()
            CATransaction.commit()
            restartMotion()
        }

        private func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: bounds.width * p.x, y: bounds.height * p.y)
        }

        /// Draws the stud grid once, a couple of tiles larger than the view so
        /// it can scroll by one tile and loop seamlessly.
        private func renderStudsIfNeeded() {
            let tile = Self.tile
            let needed = CGSize(width: bounds.width + tile * 2, height: bounds.height + tile * 2)
            guard needed.width > studArea.width || needed.height > studArea.height else { return }
            let size = CGSize(width: ceil(needed.width / tile + 4) * tile, height: ceil(needed.height / tile + 4) * tile)
            let image = NSImage(size: size, flipped: false) { _ in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                for y in stride(from: tile / 2, to: size.height, by: tile) {
                    for x in stride(from: tile / 2, to: size.width, by: tile) {
                        ctx.setFillColor(NSColor.black.withAlphaComponent(0.16).cgColor)
                        ctx.fillEllipse(in: CGRect(x: x - 3.4, y: y - 4.4, width: 7.6, height: 7.6))
                        ctx.setFillColor(NSColor.white.withAlphaComponent(0.075).cgColor)
                        ctx.fillEllipse(in: CGRect(x: x - 3.6, y: y - 3.6, width: 7.2, height: 7.2))
                        ctx.setFillColor(NSColor.white.withAlphaComponent(0.09).cgColor)
                        ctx.fillEllipse(in: CGRect(x: x - 2.2, y: y - 0.6, width: 3, height: 3))
                    }
                }
                return true
            }
            studLayer.contents = image
            studLayer.contentsScale = window?.backingScaleFactor ?? 2
            studLayer.frame = CGRect(origin: CGPoint(x: -tile, y: -tile), size: size)
            studArea = size
        }

        private func restartMotion() {
            for (i, (glow, path)) in zip(glows, paths).enumerated() {
                glow.removeAnimation(forKey: "drift")
                guard animated == true else { continue }
                let drift = CABasicAnimation(keyPath: "position")
                drift.fromValue = NSValue(point: point(path.from))
                drift.toValue = NSValue(point: point(path.to))
                drift.duration = 12 + Double(i) * 3
                drift.autoreverses = true
                drift.repeatCount = .infinity
                drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glow.add(drift, forKey: "drift")
            }
            studLayer.removeAnimation(forKey: "scroll")
            guard animated == true else { return }
            let scroll = CABasicAnimation(keyPath: "transform.translation")
            scroll.fromValue = NSValue(size: .zero)
            scroll.toValue = NSValue(size: CGSize(width: Self.tile, height: Self.tile))
            scroll.duration = 9
            scroll.repeatCount = .infinity
            studLayer.add(scroll, forKey: "scroll")
        }
    }
}

// MARK: - Surfaces

struct GlassBackground: ViewModifier {
    var corner: CGFloat = 20
    var highlighted = false
    var tint: Color = .white

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        content
            .background(
                shape.fill(LinearGradient(colors: [.white.opacity(highlighted ? 0.13 : 0.085), .white.opacity(highlighted ? 0.07 : 0.035)],
                                          startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                shape.strokeBorder(
                    highlighted
                        ? AnyShapeStyle(tint.opacity(0.95))
                        : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)),
                    lineWidth: highlighted ? 2 : 1)
            )
    }
}

extension View {
    func glass(corner: CGFloat = 20, highlighted: Bool = false, tint: Color = .white) -> some View {
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
            .offset(y: shown || reduceMotion ? 0 : 24)
            .scaleEffect(shown || reduceMotion ? 1 : 0.95, anchor: .top)
            .onAppear {
                if reduceMotion { shown = true; return }
                withAnimation(.bounce.delay(Double(index) * 0.05)) { shown = true }
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

/// A chunky key with a visible lip underneath. Pressing pushes the face down
/// into the lip and it springs back up with a little overshoot.
struct ChunkyButtonStyle: ButtonStyle {
    enum Size { case small, regular, large }

    var color: Color
    var size: Size = .regular
    var glassy = false

    func makeBody(configuration: Configuration) -> some View {
        ChunkyButton(configuration: configuration, color: color, size: size, glassy: glassy)
    }

    private struct ChunkyButton: View {
        let configuration: Configuration
        let color: Color
        let size: Size
        let glassy: Bool
        @State private var hovering = false
        @State private var shine: CGFloat = -1.3
        @Environment(\.isEnabled) private var isEnabled

        private var lip: CGFloat {
            switch size {
            case .large: return 6
            case .regular: return 4.5
            case .small: return 3.5
            }
        }

        private var corner: CGFloat {
            switch size {
            case .large: return 18
            case .regular: return 13
            case .small: return 10
            }
        }

        private var font: Font {
            switch size {
            case .large: return .system(size: 20, weight: .heavy, design: .rounded)
            case .regular: return .system(size: 14.5, weight: .bold, design: .rounded)
            case .small: return .system(size: 12.5, weight: .bold, design: .rounded)
            }
        }

        private var insets: EdgeInsets {
            switch size {
            case .large: return EdgeInsets(top: 15, leading: 34, bottom: 15, trailing: 34)
            case .regular: return EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
            case .small: return EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
            }
        }

        var body: some View {
            let active = isEnabled
            let pressed = configuration.isPressed && active
            let sink: CGFloat = pressed ? lip * 0.85 : (hovering && active ? -1.5 : 0)
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            let face: AnyShapeStyle = glassy
                ? AnyShapeStyle(LinearGradient(colors: [.white.opacity(hovering ? 0.22 : 0.16), .white.opacity(hovering ? 0.13 : 0.09)],
                                               startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(LinearGradient(colors: [color.mixed(with: .white, by: hovering ? 0.3 : 0.2), color],
                                               startPoint: .top, endPoint: .bottom))
            let lipColor: Color = glassy ? .black.opacity(0.4) : color.mixed(with: .black, by: 0.45)

            configuration.label
                .font(font)
                .foregroundStyle(.white.opacity(active ? 1 : 0.6))
                .shadow(color: .black.opacity(glassy ? 0 : 0.22), radius: 0, y: 1)
                .padding(insets)
                .offset(y: sink)
                .background {
                    ZStack {
                        shape.fill(lipColor).offset(y: lip)
                        shape.fill(face)
                            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06)],
                                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
                            .overlay { if size == .large { shineBand.clipShape(shape) } }
                            .offset(y: sink)
                    }
                }
                .padding(.bottom, lip)
                .shadow(color: glassy ? .clear : color.opacity(hovering && active ? 0.6 : 0.3), radius: hovering ? 20 : 10, y: 6)
                .opacity(active ? 1 : 0.55)
                .saturation(active ? 1 : 0.4)
                .animation(.wobble, value: pressed)
                .animation(.bounce, value: hovering)
                .onHover { h in
                    hovering = h
                    guard h, size == .large, active else { return }
                    DispatchQueue.main.async {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { shine = -1.3 }
                        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.8)) { shine = 1.3 } }
                    }
                }
        }

        private var shineBand: some View {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.3, height: geo.size.height * 2)
                    .rotationEffect(.degrees(20))
                    .offset(x: geo.size.width * shine, y: -geo.size.height * 0.5)
            }
            .allowsHitTesting(false)
        }
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    static func chunky(_ color: Color, size: ChunkyButtonStyle.Size = .regular) -> ChunkyButtonStyle {
        ChunkyButtonStyle(color: color, size: size)
    }

    static func chunkyGlass(size: ChunkyButtonStyle.Size = .regular) -> ChunkyButtonStyle {
        ChunkyButtonStyle(color: .white, size: size, glassy: true)
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
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
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
                Capsule().fill(.white.opacity(0.14))
                if let value {
                    Capsule()
                        .fill(LinearGradient(colors: [accent.opacity(0.85), accent, .white.opacity(0.95)],
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

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 34, weight: .heavy, design: .rounded))
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appearIn(0)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Big tabs with a chunky selection that slides between them.
struct SegmentedTabs<Value: Hashable>: View {
    let items: [(label: String, symbol: String, value: Value)]
    @Binding var selection: Value
    let accent: Color
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let selected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .bold))
                        Text(item.label).font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .fixedSize()
                    .foregroundStyle(selected ? .white : .white.opacity(0.65))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: [accent.mixed(with: .white, by: 0.22), accent],
                                                     startPoint: .top, endPoint: .bottom))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.3)))
                                .shadow(color: accent.opacity(0.6), radius: 8, y: 2)
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(pressedScale: 0.9))
            }
        }
        .padding(4)
        .background(Capsule().fill(.black.opacity(0.3)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
    }
}

struct SectionLabel: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text).font(.system(size: 18, weight: .heavy, design: .rounded))
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
                Text(title).font(.system(size: 14, weight: .semibold))
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
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                Capsule().fill(accent)
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
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
        .background(Capsule().fill(.black.opacity(0.28)))
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

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        // Report the widest row rather than the proposal so an unbounded
        // proposal never turns into an unbounded width.
        return CGSize(width: widest, height: y + rowHeight)
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
}

// MARK: - Icons & images

/// Loads an app's own .icns so newer macOS versions don't draw it on a gray
/// plate the way NSWorkspace icons for older-style icons are.
func bundleIcon(_ appURL: URL) -> NSImage? {
    let bundle = Bundle(url: appURL)
    let name = (bundle?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String) ?? "AppIcon"
    let file = appURL.appendingPathComponent("Contents/Resources")
        .appendingPathComponent(name.hasSuffix(".icns") ? name : name + ".icns")
    return NSImage(contentsOf: file)
}

/// Roblox's own icon.
struct RobloxIcon: View {
    @EnvironmentObject var model: LauncherModel
    var size: CGFloat

    var body: some View {
        Image(nsImage: bundleIcon(model.robloxAppURL) ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// The launcher's own icon.
struct AppLogo: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: bundleIcon(Bundle.main.bundleURL) ?? NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// A remote image that fades in, with a placeholder until it loads.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: Placeholder

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.35))) { phase in
            if let image = phase.image {
                image.resizable().interpolation(.high).transition(.opacity)
            } else {
                placeholder
            }
        }
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

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

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

/// A burst of little bricks and studs, fired each time `trigger` changes.
struct ConfettiBurst: NSViewRepresentable {
    let trigger: Int
    let colors: [Color]
    /// Where the burst starts, as a fraction of the view (origin bottom-left).
    var origin = CGPoint(x: 0.14, y: 0.2)

    func makeNSView(context: Context) -> BurstView { BurstView() }

    func updateNSView(_ view: BurstView, context: Context) {
        view.colors = colors.map { NSColor($0) }
        view.origin = origin
        view.needsLayout = true
        if let last = view.lastTrigger, last != trigger { view.burst() }
        view.lastTrigger = trigger
    }

    final class BurstView: NSView {
        var lastTrigger: Int?
        var colors: [NSColor] = []
        var origin = CGPoint(x: 0.14, y: 0.2)
        private let emitter = CAEmitterLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            emitter.birthRate = 0
            emitter.emitterShape = .point
            layer?.addSublayer(emitter)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            emitter.frame = bounds
            emitter.emitterPosition = CGPoint(x: bounds.width * origin.x, y: bounds.height * origin.y)
        }

        func burst() {
            emitter.emitterCells = colors.flatMap { [cell($0, image: Self.brick), cell($0, image: Self.stud)] }
            emitter.beginTime = CACurrentMediaTime()
            emitter.birthRate = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in self?.emitter.birthRate = 0 }
        }

        private func cell(_ color: NSColor, image: CGImage?) -> CAEmitterCell {
            let c = CAEmitterCell()
            c.contents = image
            c.color = color.cgColor
            c.birthRate = 40
            c.lifetime = 2.8
            c.velocity = 430
            c.velocityRange = 170
            c.emissionLongitude = .pi / 2
            c.emissionRange = .pi / 3
            c.yAcceleration = -760
            c.spin = 3
            c.spinRange = 7
            c.scale = 0.9
            c.scaleRange = 0.45
            c.alphaSpeed = -0.3
            return c
        }

        private static func shape(_ draw: (CGContext) -> Void) -> CGImage? {
            let size = 22
            guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            draw(ctx)
            return ctx.makeImage()
        }

        static let brick = shape { ctx in
            ctx.addPath(CGPath(roundedRect: CGRect(x: 2, y: 5, width: 18, height: 12), cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.fillPath()
        }

        static let stud = shape { ctx in
            ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 14))
        }
    }
}

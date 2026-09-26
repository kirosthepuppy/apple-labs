import AppKit
import SwiftUI

/// The typeface the launcher's own interface uses. All options ship with
/// macOS, so nothing needs downloading.
enum LauncherFont: String, CaseIterable, Identifiable {
    case avenir, sfPro, futura, gillSans, rounded, mono

    var id: String { rawValue }

    /// Read by `Font.ui`; the model keeps it in sync with the saved setting.
    static var current: LauncherFont = .avenir

    var name: String {
        switch self {
        case .avenir: return "Avenir Next"
        case .sfPro: return "SF Pro"
        case .futura: return "Futura"
        case .gillSans: return "Gill Sans"
        case .rounded: return "SF Rounded"
        case .mono: return "SF Mono"
        }
    }

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        switch self {
        case .sfPro: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .mono: return .system(size: size * 0.92, weight: weight, design: .monospaced)
        case .avenir:
            // Avenir Next runs a touch small next to SF, so nudge it up.
            return .custom(Self.face(weight, regular: "AvenirNext-Regular", medium: "AvenirNext-Medium",
                                     semibold: "AvenirNext-DemiBold", bold: "AvenirNext-Bold", heavy: "AvenirNext-Heavy"),
                           size: size * 1.04)
        case .futura:
            return .custom(Self.face(weight, regular: "Futura-Medium", medium: "Futura-Medium",
                                     semibold: "Futura-Medium", bold: "Futura-Bold", heavy: "Futura-Bold"),
                           size: size)
        case .gillSans:
            return .custom(Self.face(weight, regular: "GillSans", medium: "GillSans-SemiBold",
                                     semibold: "GillSans-SemiBold", bold: "GillSans-Bold", heavy: "GillSans-UltraBold"),
                           size: size * 1.08)
        }
    }

    private static func face(_ weight: Font.Weight, regular: String, medium: String, semibold: String,
                             bold: String, heavy: String) -> String {
        switch weight {
        case .black, .heavy: return heavy
        case .bold: return bold
        case .semibold: return semibold
        case .medium: return medium
        default: return regular
        }
    }
}

extension Font {
    /// A font in the launcher's chosen typeface.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        LauncherFont.current.font(size: size, weight: weight)
    }
}

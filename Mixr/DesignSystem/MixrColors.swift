import SwiftUI

// MARK: - Hex Initializer

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red, green, blue, alpha: Double
        switch sanitized.count {
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        default:
            red = 0
            green = 0
            blue = 0
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(hex: String, opacity: Double) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red, green, blue, alpha: Double
        switch sanitized.count {
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        default:
            red = 0
            green = 0
            blue = 0
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha * opacity)
    }
}

// MARK: - Semantic Colors

enum MixrColors {
    static let background = Color(hex: "050816")
    static let backgroundSecondary = Color(hex: "080B16")
    static let backgroundGradientTop = Color(hex: "0B0B16")
    static let surface = Color(hex: "111827")
    static let elevatedSurface = Color(hex: "171E2E")

    static let textPrimary = Color(hex: "FFFFFF")
    static let textSecondary = Color(hex: "9CA3AF")
    static let textTertiary = Color(hex: "6B7280")
    static let textMuted = Color(hex: "E5E7EB")

    static let divider = Color(hex: "2A3142")

    static let primaryPurple = Color(hex: "8B5CF6")
    static let secondaryPurple = Color(hex: "A78BFA")

    static let waveformPink = Color(hex: "FF5FA2")
    static let waveformPurple = Color(hex: "A855F7")
    static let waveformRed = Color(hex: "EF4444")
    static let waveformYellow = Color(hex: "EAB308")
    static let waveformBlue = Color(hex: "0EA5E9")

    static let glassBorderDefault = Color.white.opacity(0.08)
    static let glassBorderElevated = Color.white.opacity(0.10)
    static let glassBorderStrong = Color.white.opacity(0.12)
}

// MARK: - Waveform Colors

enum MixrWaveformColor: CaseIterable, Identifiable {
    case pink
    case purple
    case red
    case yellow
    case blue

    var id: Self { self }

    var color: Color {
        switch self {
        case .pink: MixrColors.waveformPink
        case .purple: MixrColors.waveformPurple
        case .red: MixrColors.waveformRed
        case .yellow: MixrColors.waveformYellow
        case .blue: MixrColors.waveformBlue
        }
    }

    var glowColor: Color {
        switch self {
        case .pink:
            MixrColors.waveformPink.opacity(0.20)
        default:
            color.opacity(0.20)
        }
    }

    var tintColor: Color {
        color.opacity(0.18)
    }
}

// MARK: - Gradients

enum MixrGradients {
    static let backgroundLinear = LinearGradient(
        colors: [MixrColors.backgroundGradientTop, MixrColors.background],
        startPoint: .top,
        endPoint: .bottom
    )

    static let backgroundRadial = RadialGradient(
        colors: [MixrColors.primaryPurple.opacity(0.15), .clear],
        center: UnitPoint(x: 0.2, y: -0.1),
        startRadius: 0,
        endRadius: 600
    )

    static let accentLinear = LinearGradient(
        colors: [MixrColors.secondaryPurple, MixrColors.primaryPurple],
        startPoint: UnitPoint(x: 0, y: 0),
        endPoint: UnitPoint(x: 1, y: 1)
    )

    static func waveformFade(for color: Color) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: color, location: 0),
                .init(color: color, location: 0.85),
                .init(color: color.opacity(0), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func waveformBarFill(for color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.75), color, color.opacity(0.75)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

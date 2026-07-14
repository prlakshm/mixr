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

    static let primaryPurple = Color(hex: "7C3AED")
    static let secondaryPurple = Color(hex: "8B5CF6")

    static let waveformPink = Color(hex: "FF5FA2")
    static let waveformPurple = Color(hex: "8B5CF6")
    static let waveformRed = Color(hex: "EF4444")
    static let waveformYellow = Color(hex: "EAB308")
    static let waveformBlue = Color(hex: "0EA5E9")

    /// Polished metallic SFX lane — highlight catch light.
    static let sfxHighlight = Color(hex: "F7F9FC")
    /// Metallic SFX primary (outlines, grips, ambient silver).
    static let sfxPrimary = Color(hex: "E7ECF3")
    /// Mid silver for bands, fills, softer geometry.
    static let sfxSecondary = Color(hex: "8A95A5")
    /// Dark silver for machined depth / lower edges.
    static let sfxShadow = Color(hex: "303741")
    /// Alias for the Sound Effects track color (`sfxPrimary`).
    static let waveformSilver = sfxPrimary

    static let glassBorderDefault = Color.white.opacity(0.06)
    static let glassBorderElevated = Color.white.opacity(0.08)
    static let glassBorderStrong = Color.white.opacity(0.10)

    // Dark navy glass tints — reference ~#0E1322, not gray-blue
    static let glassNavyDefault = Color(hex: "050810")
    static let glassNavyElevated = Color(hex: "0A0F1A")
    static let glassNavyStrong = Color(hex: "0E1322")
    static let glassClipNavy = Color(hex: "080C14")

    static let glassRimHighlight = Color.white.opacity(0.10)
    static let glassEdgeCool = Color(hex: "8B9DC2").opacity(0.08)
    static let glassAmbientPurple = Color(hex: "8B5CF6").opacity(0.04)
}

// MARK: - Waveform Colors

enum MixrWaveformColor: String, CaseIterable, Identifiable, Codable {
    case pink
    case purple
    case red
    case yellow
    case blue
    /// Reserved for the Sound Effects track — not part of the song color cycle.
    case silver

    var id: Self { self }

    var color: Color {
        switch self {
        case .pink: MixrColors.waveformPink
        case .purple: MixrColors.waveformPurple
        case .red: MixrColors.waveformRed
        case .yellow: MixrColors.waveformYellow
        case .blue: MixrColors.waveformBlue
        case .silver: MixrColors.sfxPrimary
        }
    }

    /// Softer companion — SFX uses blue-cast secondary for fills / transitions.
    var secondaryColor: Color {
        switch self {
        case .silver: MixrColors.sfxSecondary
        default: color
        }
    }

    var glowColor: Color {
        switch self {
        case .pink:
            MixrColors.waveformPink.opacity(0.20)
        default:
            // Match song-track resting glow affordance (including SFX).
            color.opacity(0.20)
        }
    }

    /// Clip body tint / track wash fill.
    var tintColor: Color {
        switch self {
        case .silver:
            MixrColors.sfxSecondary.opacity(0.18)
        default:
            color.opacity(0.18)
        }
    }

    /// Resting clip outline (flat fallback; SFX uses metallic gradient stroke).
    var outlineColor: Color {
        switch self {
        case .silver:
            MixrColors.sfxPrimary.opacity(0.72)
        default:
            color.opacity(0.45)
        }
    }

    /// Selected clip outline.
    var selectedOutlineColor: Color {
        switch self {
        case .silver:
            MixrColors.sfxHighlight.opacity(0.92)
        default:
            color.opacity(1.0)
        }
    }

    /// Brighter peak color for waveform silhouette — dominant over clip tint.
    var peakColor: Color {
        switch self {
        case .pink: Color(hex: "FF7FB8")
        case .purple: Color(hex: "C084FC")
        case .red: Color(hex: "F87171")
        case .yellow: Color(hex: "FACC15")
        case .blue: Color(hex: "38BDF8")
        case .silver: MixrColors.sfxHighlight
        }
    }

    /// Waveform silhouette opacity multiplier.
    var waveformOpacity: CGFloat {
        1.0
    }

    /// Metallic outline gradient for SFX clips (upper-left catches light).
    static var sfxMetallicOutline: LinearGradient {
        LinearGradient(
            colors: [
                MixrColors.sfxHighlight.opacity(0.88),
                MixrColors.sfxSecondary.opacity(0.52),
                MixrColors.sfxShadow.opacity(0.56),
                MixrColors.sfxPrimary.opacity(0.72),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Selected metallic outline — same structure, slightly brighter catch light.
    static var sfxMetallicOutlineSelected: LinearGradient {
        LinearGradient(
            colors: [
                MixrColors.sfxHighlight.opacity(0.96),
                MixrColors.sfxPrimary.opacity(0.78),
                MixrColors.sfxSecondary.opacity(0.58),
                MixrColors.sfxShadow.opacity(0.50),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

    // MARK: - Glass Surface Gradients

    /// Subtle top-lit depth gradient for layered glass panes.
    static func glassSurfaceDepth(highlightOpacity: Double) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(highlightOpacity), location: 0),
                .init(color: Color.white.opacity(highlightOpacity * 0.25), location: 0.22),
                .init(color: Color.clear, location: 0.52),
                .init(color: Color.black.opacity(0.14), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Restrained purple ambient wash — background integration without glow.
    static let glassAmbientWash = LinearGradient(
        colors: [
            MixrColors.glassAmbientPurple,
            MixrColors.primaryPurple.opacity(0.015),
            Color.clear,
        ],
        startPoint: UnitPoint(x: 0.15, y: 0),
        endPoint: UnitPoint(x: 0.85, y: 1)
    )

    /// Top-edge rim catch-light for glass borders.
    static let glassRimStroke = LinearGradient(
        colors: [
            MixrColors.glassRimHighlight,
            MixrColors.glassEdgeCool.opacity(0.5),
            Color.clear,
        ],
        startPoint: .top,
        endPoint: UnitPoint(x: 0.5, y: 0.35)
    )
}

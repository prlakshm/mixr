import SwiftUI

/// Scale-aware optical values for the shared SFX icon-box material.
struct SFXIconBoxRenderingProfile {
    let baseTopOpacity: Double
    let baseBottomOpacity: Double
    let materialOpacity: Double
    let navyWashColor: Color
    let navyWashOpacity: Double
    let luminanceWashColor: Color
    let luminanceWashOpacity: Double
    let radialPrimaryOpacity: Double
    let radialSecondaryColor: Color
    let radialSecondaryOpacity: Double
    let borderTint: Color
    let borderOpacity: Double
    /// Multiplier for specular / hairline rim layers (1 = full, 0.5 = 50% quieter).
    let rimStrength: Double
    let usesActiveColorwayBorder: Bool
    let iconBloomColor: Color
    let iconCoreGlowOpacity: Double
    let iconCoreGlowRadius: CGFloat
    let iconBloomRadius: CGFloat
    let outerGlowColor: Color
    let outerGlowRadius: CGFloat

    var borderColor: Color {
        usesActiveColorwayBorder
            ? SFXCard.iconTileBorderColor
            : borderTint.opacity(borderOpacity)
    }

    /// Menu / library icon tile — clear liquid glass, edge-weighted color.
    static let standard = Self(
        baseTopOpacity: 0.48,
        baseBottomOpacity: 0.56,
        materialOpacity: 0.035,
        navyWashColor: .clear,
        navyWashOpacity: 0,
        luminanceWashColor: SFXCard.pearlLavender,
        luminanceWashOpacity: 0,
        radialPrimaryOpacity: 0.10,
        radialSecondaryColor: SFXCard.pearlLavender,
        radialSecondaryOpacity: 0.05,
        borderTint: .white,
        borderOpacity: 0.14,
        rimStrength: 1,
        usesActiveColorwayBorder: true,
        iconBloomColor: SFXCard.iconBloomColor,
        iconCoreGlowOpacity: 0.56,
        iconCoreGlowRadius: SFXMetrics.cardIconCoreGlowRadius,
        iconBloomRadius: SFXMetrics.cardIconBloomRadius,
        outerGlowColor: .clear,
        outerGlowRadius: 0
    )

    /// Sidebar song chip — same color family, liquid-glass optics.
    static let compact = Self(
        baseTopOpacity: 0.46,
        baseBottomOpacity: 0.54,
        materialOpacity: 0.03,
        navyWashColor: Color(hex: "172238"),
        navyWashOpacity: 0.08,
        luminanceWashColor: Color(hex: "D88BC8"),
        luminanceWashOpacity: 0.045,
        radialPrimaryOpacity: 0.11,
        radialSecondaryColor: Color(hex: "A98BE8"),
        radialSecondaryOpacity: 0.06,
        borderTint: Color(hex: "D9B6EE"),
        // Prior 0.18, then −20% opacity for the small square chip only.
        borderOpacity: 0.144,
        rimStrength: 0.40,
        usesActiveColorwayBorder: false,
        iconBloomColor: SFXCard.iconBloomColor.opacity(0.35),
        iconCoreGlowOpacity: 0.34,
        iconCoreGlowRadius: 1.6,
        iconBloomRadius: 2.5,
        outerGlowColor: Color(hex: "D88BC8").opacity(0.08),
        outerGlowRadius: 3
    )
}

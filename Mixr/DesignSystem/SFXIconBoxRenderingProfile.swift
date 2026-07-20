import SwiftUI

/// Scale-aware optical values for the shared SFX icon-box material.
struct SFXIconBoxRenderingProfile {
    let navyWashColor: Color
    let navyWashOpacity: Double
    let luminanceWashColor: Color
    let luminanceWashOpacity: Double
    let radialPrimaryOpacity: Double
    let radialSecondaryColor: Color
    let radialSecondaryOpacity: Double
    let borderTint: Color
    let borderOpacity: Double
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

    static let standard = Self(
        navyWashColor: .clear,
        navyWashOpacity: 0,
        luminanceWashColor: SFXCard.pearlLavender,
        luminanceWashOpacity: 0,
        radialPrimaryOpacity: 0.13,
        radialSecondaryColor: SFXCard.pearlLavender,
        radialSecondaryOpacity: 0.07,
        borderTint: .white,
        borderOpacity: 0.14,
        usesActiveColorwayBorder: true,
        iconBloomColor: SFXCard.iconBloomColor,
        iconCoreGlowOpacity: 0.56,
        iconCoreGlowRadius: SFXMetrics.cardIconCoreGlowRadius,
        iconBloomRadius: SFXMetrics.cardIconBloomRadius,
        outerGlowColor: .clear,
        outerGlowRadius: 0
    )

    static let compact = Self(
        navyWashColor: Color(hex: "172238"),
        navyWashOpacity: 0.16,
        luminanceWashColor: Color(hex: "D88BC8"),
        luminanceWashOpacity: 0.12,
        radialPrimaryOpacity: 0.28,
        radialSecondaryColor: Color(hex: "A98BE8"),
        radialSecondaryOpacity: 0.16,
        borderTint: Color(hex: "D9B6EE"),
        borderOpacity: 0.32,
        usesActiveColorwayBorder: false,
        iconBloomColor: SFXCard.iconBloomColor.opacity(0.35),
        iconCoreGlowOpacity: 0.34,
        iconCoreGlowRadius: 1.6,
        iconBloomRadius: 2.5,
        outerGlowColor: Color(hex: "D88BC8").opacity(0.10),
        outerGlowRadius: 3.5
    )
}

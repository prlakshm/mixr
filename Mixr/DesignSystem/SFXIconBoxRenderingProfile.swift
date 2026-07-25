import SwiftUI

/// Scale-aware optical values for the shared SFX icon-box material.
struct SFXIconBoxRenderingProfile {
    let baseTopColor: Color
    let baseBottomColor: Color
    let baseTopOpacity: Double
    let baseBottomOpacity: Double
    let materialOpacity: Double
    let navyWashColor: Color
    let navyWashOpacity: Double
    let luminanceWashColor: Color
    let luminanceWashOpacity: Double
    let radialPrimaryColor: Color
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
        baseTopColor: Color(hex: "272337"),
        baseBottomColor: Color(hex: "161724"),
        baseTopOpacity: 0.48,
        baseBottomOpacity: 0.56,
        materialOpacity: 0.035,
        navyWashColor: .clear,
        navyWashOpacity: 0,
        luminanceWashColor: SFXCard.pearlLavender,
        luminanceWashOpacity: 0,
        radialPrimaryColor: Color(hex: "C78BC4"),
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

    /// Sidebar song chip — purple stops match `MixrTrackRowBackground` SFX row.
    static let compact = Self(
        baseTopColor: Color(hex: "241A39"),
        baseBottomColor: Color(hex: "162239"),
        baseTopOpacity: 0.52,
        baseBottomOpacity: 0.58,
        materialOpacity: 0.03,
        navyWashColor: Color(hex: "090B13"),
        navyWashOpacity: 0.22,
        luminanceWashColor: Color(hex: "A281BC"),
        luminanceWashOpacity: 0.06,
        radialPrimaryColor: Color(hex: "A281BC"),
        radialPrimaryOpacity: 0.12,
        radialSecondaryColor: Color(hex: "765A92"),
        radialSecondaryOpacity: 0.08,
        borderTint: Color(hex: "A281BC"),
        // Prior 0.18, then −20% opacity for the small square chip only.
        borderOpacity: 0.144,
        rimStrength: 0.40,
        usesActiveColorwayBorder: false,
        iconBloomColor: Color(hex: "A281BC").opacity(0.35),
        iconCoreGlowOpacity: 0.34,
        iconCoreGlowRadius: 1.6,
        iconBloomRadius: 2.5,
        outerGlowColor: Color(hex: "A281BC").opacity(0.08),
        outerGlowRadius: 3
    )
}

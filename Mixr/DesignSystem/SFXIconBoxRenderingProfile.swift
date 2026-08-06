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

    /// Sidebar song chip — an elevated pane resting on the SFX row.
    ///
    /// This used to reuse `MixrTrackRowBackground`'s purple stops verbatim
    /// (#241A39 / #090B13 / #162239 with #A281BC accents), which made the chip
    /// dissolve into the card behind it — same hues, and a rim weaker than the
    /// surface it sat on. It now takes the SFX library panel's glossy dark
    /// blue (#171927 → #0B0E19), carried at near-full opacity so it reads as a
    /// solid pane rather than a wash, with the rim at full strength so its
    /// edge is brighter than the row's.
    static let compact = Self(
        baseTopColor: Color(hex: "171927"),
        baseBottomColor: Color(hex: "0B0E19"),
        baseTopOpacity: 0.88,
        baseBottomOpacity: 0.94,
        materialOpacity: 0.16,
        navyWashColor: MixrColors.glassNavyDefault,
        navyWashOpacity: 0.10,
        luminanceWashColor: Color(hex: "8C7DAA"),
        luminanceWashOpacity: 0.05,
        // The panel's own cool bloom, not the row's warm purple.
        radialPrimaryColor: Color(hex: "8C7DAA"),
        radialPrimaryOpacity: 0.14,
        radialSecondaryColor: Color(hex: "6E7CA8"),
        radialSecondaryOpacity: 0.08,
        // Matches the SFX panel's own hairline.
        borderTint: .white,
        borderOpacity: 0.14,
        rimStrength: 1.0,
        usesActiveColorwayBorder: false,
        iconBloomColor: Color(hex: "A281BC").opacity(0.35),
        // Lifted slightly — the glyph now sits on a darker box.
        iconCoreGlowOpacity: 0.42,
        iconCoreGlowRadius: 1.6,
        iconBloomRadius: 2.5,
        outerGlowColor: Color(hex: "8C7DAA").opacity(0.10),
        outerGlowRadius: 4
    )
}

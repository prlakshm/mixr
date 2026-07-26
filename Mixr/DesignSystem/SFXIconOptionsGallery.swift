import SwiftUI

// MARK: - SFX Monogram Style (legacy A–F; production uses the connected stencil)

enum MixrSFXMarkStyle: String, CaseIterable, Identifiable {
    case a, b, c, d, e, f

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a: "A · Connected s–fx (tight join)"
        case .b: "B · Separated s + fx stencil"
        case .c: "C · Heavier / larger s"
        case .d: "D · Connected cursive stencil (shipped)"
        case .e: "E · Taller s optical match"
        case .f: "F · Soft rounded s"
        }
    }
}

// MARK: - Mark View (full connected sfx template)

/// Lowercase **sfx** mark from the connected cursive reference stencil.
/// Asset is template-rendered so `.foregroundStyle` tints hover / chip states.
struct MixrSFXMark: View {
    var style: MixrSFXMarkStyle = .d
    var width: CGFloat = 32
    var height: CGFloat = 22
    var color: Color = MixrColors.textMuted.opacity(0.92)
    /// Horizontal squeeze at constant height — chip + footer button share this.
    /// Cumulative: 5% × 5% × 7% narrower so the stencil doesn’t read stretched.
    var widthScale: CGFloat = 0.95 * 0.95 * 0.93

    var body: some View {
        Image("SFXMarkStencil")
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .foregroundStyle(color)
            // Same height; narrower frame so the stencil isn’t horizontally stretched.
            .frame(width: width * widthScale, height: height)
            .accessibilityLabel("SFX")
    }
}

/// Compact mark for song chips / tight slots.
/// Taller than before; width∶height matches the footer SFX button (22∶15).
struct MixrSFXMarkGlyph: View {
    var size: CGFloat = 14
    var color: Color = .white

    /// Same aspect as `MixrSFXOutlineButtonLabel` (`markWidth` 22 / `markHeight` 15).
    private static let buttonMarkAspect: CGFloat = 22.0 / 15.0

    var body: some View {
        // Raise height vs the old `size * 1.10`; width follows the button aspect.
        let height = size * 1.22
        let width = height * Self.buttonMarkAspect
        MixrSFXMark(
            style: .d,
            width: width,
            height: height,
            color: color
        )
    }
}

// MARK: - Import-styled SFX button chrome (shared mock + production)

struct MixrSFXOutlineButtonLabel: View {
    var style: MixrSFXMarkStyle = .d
    /// Layout slot — keeps the button chrome size stable.
    private let layoutMarkWidth: CGFloat = 22 * 0.95
    private let layoutMarkHeight: CGFloat = 15 * 0.95
    /// Drawn mark is 10% smaller than the original layout slot, then +5%.
    private var markWidth: CGFloat { layoutMarkWidth * 0.90 * 1.05 }
    private var markHeight: CGFloat { layoutMarkHeight * 0.90 * 1.05 }

    /// Total chrome width (mark slot + horizontal padding) — used to size
    /// the sibling Import Songs button in the tracks footer.
    static var chromeWidth: CGFloat {
        let layoutMarkWidth: CGFloat = 22 * 0.95
        return layoutMarkWidth * 1.10 + 5 * 2
    }

    var body: some View {
        MixrSFXMark(style: style, width: markWidth, height: markHeight)
            // Button chrome 10% wider; icon stays the same drawn size.
            .frame(width: layoutMarkWidth * 1.10, height: layoutMarkHeight)
            .padding(.horizontal, 5)
            .padding(.vertical, MixrLayout.buttonPaddingV)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MixrColors.divider, lineWidth: 0.5)
            }
            .partyModeBorder(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                role: .compactControl,
                lighting: .violetTrailing,
                glintOffset: .far
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
// MARK: - Gallery

/// Preview of the shipped connected **sfx** stencil in chip + footer chrome.
struct SFXIconOptionsGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SFX Icon")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                    Text("Connected cursive sfx stencil — template-tintable for footer and song chips.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(MixrColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                shippedRow
            }
            .padding(20)
        }
        .background {
            ZStack {
                MixrGradients.backgroundLinear
                MixrGradients.backgroundRadial
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private var shippedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MixrSFXMarkStyle.d.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MixrColors.textSecondary)

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "2D3136"))
                    MixrSFXMark(
                        style: .d,
                        width: 72,
                        height: 48,
                        color: Color(hex: "CCCCCC")
                    )
                }
                .frame(width: 100, height: 56)

                HStack(spacing: 7) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Import Songs")
                            .mixrFont(.button)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(MixrColors.textMuted.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, MixrSpacing.sm)
                    .padding(.vertical, MixrLayout.buttonPaddingV)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(MixrColors.divider, lineWidth: 0.5)
                    }

                    MixrSFXOutlineButtonLabel(style: .d)

                    MixrSongColorChip(color: .silver, usesSFXMark: true)
                }
                .frame(width: 240)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MixrColors.backgroundSecondary.opacity(0.85))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(MixrColors.divider.opacity(0.45), lineWidth: 0.5)
                    }
            }
        }
    }
}

#Preview("SFX Icon Options") {
    SFXIconOptionsGallery()
}

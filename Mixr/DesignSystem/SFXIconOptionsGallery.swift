import SwiftUI

// MARK: - SFX Monogram Style (mock options A–F)

enum MixrSFXMarkStyle: String, CaseIterable, Identifiable {
    case a, b, c, d, e, f

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a: "A · Connected s–fx (tight join)"
        case .b: "B · Separated s + fx stencil"
        case .c: "C · Heavier / larger s"
        case .d: "D · Tighter / compressed (shipped)"
        case .e: "E · Taller s optical match"
        case .f: "F · Soft rounded s"
        }
    }

    /// Gap between s and the fx stencil (negative = overlap).
    var sGap: CGFloat {
        switch self {
        case .a: -1.5
        case .b: 2.0
        case .c: 1.0
        case .d: 0.5
        case .e: 0.5
        case .f: 1.0
        }
    }

    /// Relative size of the leading s vs fx stencil height.
    var sScale: CGFloat {
        switch self {
        case .a, .b, .d: 0.78
        case .c: 0.92
        case .e: 0.88
        case .f: 0.80
        }
    }

    /// Overall horizontal compression (< 1 = tighter).
    var trackingScale: CGFloat {
        switch self {
        case .d: 0.88
        case .a: 0.94
        default: 1.0
        }
    }

    var sWeight: Font.Weight {
        switch self {
        case .c: .heavy
        case .f: .semibold
        default: .bold
        }
    }

    var sDesign: Font.Design {
        switch self {
        case .f: .rounded
        default: .default
        }
    }
}

// MARK: - Mark View (reference stencil + leading s)

/// Lowercase **sfx** mark. The **fx** portion is the After Effects reference
/// image used as a template stencil; a matching italic **s** is prefixed.
struct MixrSFXMark: View {
    var style: MixrSFXMarkStyle = .d
    var width: CGFloat = 36
    var height: CGFloat = 16
    var color: Color = MixrColors.textMuted.opacity(0.92)

    var body: some View {
        HStack(spacing: style.sGap) {
            Text("s")
                .font(.system(
                    size: height * style.sScale,
                    weight: style.sWeight,
                    design: style.sDesign
                ))
                .italic()
                .foregroundStyle(color)
                // Optical baseline match to the stencil’s italic stem.
                .offset(y: height * 0.02)

            Image("SFXFXStencil")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
                .frame(height: height)
        }
        .scaleEffect(x: style.trackingScale, y: 1, anchor: .center)
        .frame(width: width, height: height)
        .accessibilityLabel("SFX")
    }
}

/// Compact mark for song chips / tight slots — fills the given square.
struct MixrSFXMarkGlyph: View {
    var size: CGFloat = 14
    var color: Color = .white

    var body: some View {
        MixrSFXMark(
            style: .d,
            width: size * 1.85,
            height: size * 0.95,
            color: color
        )
    }
}

// MARK: - Import-styled SFX button chrome (shared mock + production)

struct MixrSFXOutlineButtonLabel: View {
    var style: MixrSFXMarkStyle = .d
    var markWidth: CGFloat = 28
    var markHeight: CGFloat = 13

    var body: some View {
        MixrSFXMark(style: style, width: markWidth, height: markHeight)
            .padding(.horizontal, 5)
            .padding(.vertical, MixrLayout.buttonPaddingV)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MixrColors.divider, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Gallery

/// Side-by-side mockups of AE-stencil **sfx** options (A–F).
struct SFXIconOptionsGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SFX Icon Options")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                    Text("fx is the After Effects reference stencil; s is prefixed to match. D is shipped.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(MixrColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(MixrSFXMarkStyle.allCases) { style in
                    optionRow(style: style)
                }
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

    private func optionRow(style: MixrSFXMarkStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(style.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MixrColors.textSecondary)

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "2D3136"))
                    MixrSFXMark(
                        style: style,
                        width: 64,
                        height: 28,
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

                    MixrSFXOutlineButtonLabel(style: style)
                }
                .frame(width: 200)
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

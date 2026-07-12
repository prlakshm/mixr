import SwiftUI

// MARK: - SFX Monogram Style (mock options A–F)

enum MixrSFXMarkStyle: String, CaseIterable, Identifiable {
    case a, b, c, d, e, f

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a: "A · Connected s–f–x"
        case .b: "B · Separated s, connected fx"
        case .c: "C · Heavier stroke"
        case .d: "D · Tighter / compressed"
        case .e: "E · Open counters, taller x"
        case .f: "F · Soft rounded terminals"
        }
    }

    /// Whether the s joins the f crossbar.
    var connectsS: Bool {
        switch self {
        case .a, .c, .d, .e, .f: true
        case .b: false
        }
    }

    var strokeWidthFactor: CGFloat {
        switch self {
        case .a, .b, .d, .e: 0.095
        case .c: 0.125
        case .f: 0.100
        }
    }

    /// Horizontal compression (< 1 = tighter).
    var trackingScale: CGFloat {
        switch self {
        case .a, .b, .c, .e, .f: 1.0
        case .d: 0.86
        }
    }

    /// Relative x-letter height.
    var xHeightScale: CGFloat {
        switch self {
        case .a, .b, .c, .d, .f: 1.0
        case .e: 1.14
        }
    }

    var lineCap: CGLineCap {
        switch self {
        case .f: .round
        default: .butt
        }
    }

    var lineJoin: CGLineJoin {
        switch self {
        case .f: .round
        default: .miter
        }
    }
}

// MARK: - Shape

/// After Effects–inspired lowercase **sfx** monogram: italic slant,
/// uniform stroke, f→x connection; optional s→f join.
struct MixrSFXMarkShape: Shape {
    var style: MixrSFXMarkStyle = .d

    func path(in rect: CGRect) -> Path {
        let shear: CGFloat = 0.22
        let track = style.trackingScale
        let xScale = style.xHeightScale

        // Design grid ~36×20, then fit into rect with shear.
        let gw: CGFloat = 36 * track
        let gh: CGFloat = 20

        func map(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            // Italic shear around vertical center, then fit to rect.
            let sx = (u + (v - gh / 2) * shear) / gw
            let sy = v / gh
            return CGPoint(
                x: rect.minX + sx * rect.width,
                y: rect.minY + sy * rect.height
            )
        }

        var p = Path()

        // ── s ──────────────────────────────────────────────
        // Top bowl → mid cross → bottom bowl (opening right then left).
        let sLead: CGFloat = style.connectsS ? 0.2 : 0.0
        p.move(to: map(2.2, 5.2))
        p.addCurve(
            to: map(7.4 + sLead, 4.0),
            control1: map(3.0, 2.4),
            control2: map(5.6, 2.2)
        )
        p.addCurve(
            to: map(4.0, 10.0),
            control1: map(9.0 + sLead, 5.6),
            control2: map(8.6, 8.4)
        )
        p.addCurve(
            to: map(8.2, 16.2),
            control1: map(0.6, 11.4),
            control2: map(1.4, 15.8)
        )
        p.addCurve(
            to: map(2.8, 15.0),
            control1: map(11.0, 16.5),
            control2: map(9.4, 18.4)
        )

        // Optional bridge from s into f crossbar.
        if style.connectsS {
            p.move(to: map(7.4 + sLead, 4.0))
            p.addLine(to: map(11.2, 9.6))
        }

        // ── f ──────────────────────────────────────────────
        // Stem (slightly curved top, long descender).
        let fStemX: CGFloat = 13.6
        p.move(to: map(fStemX + 1.6, 2.4))
        p.addQuadCurve(
            to: map(fStemX, 4.2),
            control: map(fStemX + 2.2, 2.6)
        )
        p.addLine(to: map(fStemX, 17.6))

        // Crossbar — extends into the x’s upper-left arm when connected.
        p.move(to: map(fStemX - 3.2, 9.6))
        p.addLine(to: map(fStemX + 5.4, 9.6))

        // ── x ──────────────────────────────────────────────
        let xMidX: CGFloat = 22.4
        let xMidY: CGFloat = 10.0
        let xArm: CGFloat = 4.6 * xScale
        let xVert: CGFloat = 5.4 * xScale

        // Upper-left arm continues from f crossbar tip.
        p.move(to: map(fStemX + 5.4, 9.6))
        p.addLine(to: map(xMidX - xArm * 0.15, xMidY - xVert * 0.15))
        p.addLine(to: map(xMidX - xArm, xMidY - xVert))

        // Upper-right
        p.move(to: map(xMidX, xMidY))
        p.addLine(to: map(xMidX + xArm, xMidY - xVert))

        // Lower-left
        p.move(to: map(xMidX, xMidY))
        p.addLine(to: map(xMidX - xArm, xMidY + xVert))

        // Lower-right
        p.move(to: map(xMidX, xMidY))
        p.addLine(to: map(xMidX + xArm, xMidY + xVert))

        return p
    }
}

// MARK: - Mark View

struct MixrSFXMark: View {
    var style: MixrSFXMarkStyle = .d
    var width: CGFloat = 36
    var height: CGFloat = 16
    var color: Color = MixrColors.textMuted.opacity(0.92)

    private var strokeWidth: CGFloat {
        max(1.4, min(width, height * 2) * style.strokeWidthFactor)
    }

    var body: some View {
        MixrSFXMarkShape(style: style)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: strokeWidth,
                    lineCap: style.lineCap,
                    lineJoin: style.lineJoin,
                    miterLimit: 4
                )
            )
            .frame(width: width, height: height)
            .accessibilityLabel("SFX")
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

/// Side-by-side mockups of AE-style lowercase **sfx** monogram options (A–F).
struct SFXIconOptionsGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SFX Icon Options")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MixrColors.textPrimary)
                    Text("After Effects–inspired lowercase sfx — italic, uniform stroke, connected fx. Pick a letter to ship.")
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
                // Glyph alone on dark plate
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "2D3136"))
                    MixrSFXMark(
                        style: style,
                        width: 52,
                        height: 22,
                        color: Color(hex: "CCCCCC")
                    )
                }
                .frame(width: 88, height: 52)

                // Footer context — Import Songs + SFX outline button
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

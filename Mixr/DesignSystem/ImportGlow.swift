import SwiftUI

// The still glow behind Import Songs on an empty project: a soft violet
// shadow around the glass, no outline and no motion, the way Play and the
// tour's Next carry their glow. It marks the one useful action on an empty
// screen without asking for attention.

/// Everything that shapes the glow. At Play's values (50%, 10 pt), so the
/// button reads as the primary action in the app's own language.
struct ImportGlowStyle {
    var color: Color = MixrColors.primaryPurple
    var opacity: Double = 0.5
    var radius: CGFloat = 10

    static let standard = ImportGlowStyle()
}

/// The glow, drawn behind the glass and masked to outside the button so it
/// never tints the glass itself.
struct ImportGlow: View {
    var style: ImportGlowStyle = .standard
    var cornerRadius: CGFloat = MixrRadius.button

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let reach = style.radius * 3
        shape
            .fill(Color.black)
            .shadow(color: style.color.opacity(style.opacity), radius: style.radius)
            .padding(reach)
            .mask {
                GeometryReader { proxy in
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: proxy.size))
                        p.addRoundedRect(
                            in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: reach, dy: reach),
                            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
                            style: .continuous
                        )
                    }
                    .fill(style: FillStyle(eoFill: true))
                }
            }
            .padding(-reach)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Canvas preview

#Preview("Import glow") {
    HStack(spacing: 7) {
        HStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
            Text("Import Songs").mixrFont(.button)
        }
        .foregroundStyle(MixrColors.textPrimary)
        .frame(width: 144)
        .padding(.vertical, MixrLayout.buttonPaddingV)
        .background { MixrGlassButtonChrome(isHighlighted: true) }

        MixrSFXOutlineButtonLabel(style: .d)
    }
    .padding(.horizontal, 10)
    .frame(width: 270, height: 46)
    .background(MixrColors.backgroundSecondary)
    .padding(40)
    .background(MixrColors.background)
    .preferredColorScheme(.dark)
}

import SwiftUI

// The sound-effects library: one glass panel over the dimmed timeline,
// six sounds per page (swipe for more), every tile in the same SFX lavender
// glass as the Import / Export buttons.

/// Library order, the way a DJ reaches for them: builds, drops, then hits.
/// Anything new in the library lands at the end.
enum SFXLibraryOrder {
    static let ids = [
        "riser", "sweepUp", "snareBuild", "airSweep", "reverseCymbal",
        "downlifter", "sweepDown", "bassDrop", "tapeStop",
        "impact", "crash", "clapFill",
    ]

    static var effects: [SoundEffectDefinition] {
        let front = ids.compactMap { SoundEffectLibrary.definition(for: $0) }
        let rest = SoundEffectLibrary.all.filter { !ids.contains($0.id) }
        return front + rest
    }
}

private func durationLabel(_ seconds: Double) -> String {
    seconds == seconds.rounded() ? "\(Int(seconds))s" : String(format: "%.1fs", seconds)
}

/// One glass container: system material plus a faint navy tint, hairline
/// rim and a soft shadow — the same family as the alerts and menus.
private struct SFXGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(MixrColors.glassNavyDefault.opacity(0.55)) }
                    .environment(\.colorScheme, .dark)
            }
            .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6) }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }
}

/// One glass tile per sound: the Import / Export glass with a light SFX
/// lavender tint, and the glyph in the SFX chip's pearl fill.
private struct SFXGlassWell: View {
    let icon: String
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
        ZStack {
            // Same glass as Import / Export, with a light SFX lavender tint.
            GlassBackground(level: .default, cornerRadius: 17)
                .clipShape(shape)
            shape.fill(MixrColors.sfxMenuLavender.opacity(0.10))
            shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
            SFXCard.pearlIconFill
                .mask {
                    Image(systemName: icon)
                        .font(.system(size: 27, weight: .semibold))
                }
                .shadow(color: SFXCard.iconBloomColor, radius: 4)
        }
        .frame(width: 68, height: 68)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

struct SFXLibraryPanel: View {
    var onSelect: (SoundEffectDefinition) -> Void = { _ in }
    var onClose: () -> Void = {}

    var body: some View {
        SFXGlassContainer {
            VStack(alignment: .leading, spacing: 14) {
                header
                grid
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
    }

    private var header: some View {
        HStack {
            Text("Sound Effects")
                .mixrScaledFont(size: 15, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(MixrColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MixrColors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MixrGlassPressStyle())
            .accessibilityLabel("Close")
        }
        .frame(height: 32)
    }

    // MARK: Grid (six per page, swipe for more)

    @State private var page: Int? = 0

    private var pages: [[SoundEffectDefinition]] {
        let all = SFXLibraryOrder.effects
        return stride(from: 0, to: all.count, by: 6).map { Array(all[$0..<min($0 + 6, all.count)]) }
    }

    private var grid: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, effects in
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                            spacing: 16
                        ) {
                            ForEach(effects) { effect in item(effect) }
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)

            MixrPageDots(count: pages.count, current: page ?? 0, accent: MixrColors.sfxMenuLavender)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \((page ?? 0) + 1) of \(pages.count)")
        }
    }

    private func item(_ effect: SoundEffectDefinition) -> some View {
        Button { onSelect(effect) } label: {
            VStack(spacing: 7) {
                SFXGlassWell(icon: effect.icon)
                Text(effect.title)
                    .mixrScaledFont(size: 13, weight: .medium, relativeTo: .subheadline)
                    .foregroundStyle(MixrColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(durationLabel(effect.durationSeconds))
                    .mixrScaledFont(size: 11, relativeTo: .caption)
                    .foregroundStyle(MixrColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(MixrGlassPressStyle())
        .accessibilityLabel("\(effect.title), \(durationLabel(effect.durationSeconds))")
    }
}

#Preview("SFX Library Panel") {
    ZStack {
        MixrGradients.backgroundLinear.ignoresSafeArea()
        SFXLibraryPanel()
            .frame(width: 456)
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(width: 932, height: 430)
    .preferredColorScheme(.dark)
}

import SwiftUI

// The breathing violet halo around Import Songs on an empty project.
// Tune it in the Xcode canvas: every value lives in `HaloPulseStyle`, and
// the previews at the bottom show it on the real button chrome at full
// speed and slowed down.

/// Everything that shapes the halo. One cycle is a two-step swell: the glow
/// pushes out, settles back a touch, surges out to full, then retracts all
/// the way in on one long, smooth exhale — and repeats forever.
struct HaloPulseStyle {
    /// Seconds for one full cycle.
    var period: Double = 3.6
    /// The swell, as (fraction of the cycle, how far out 0…1). Each segment
    /// eases in and out, so every turn is soft, never a jolt. The last key
    /// must return to 0 at 1.0 so the loop joins seamlessly.
    var keyframes: [(time: Double, extension: Double)] = [
        (0.00, 0.00),   // resting in
        (0.20, 0.60),   // first push out
        (0.31, 0.48),   // settles back a touch
        (0.52, 1.00),   // surges out to full
        (1.00, 0.00),   // one long, smooth retract
    ]
    /// How far past the button edge the glow sits when retracted / extended.
    var nearDistance: CGFloat = 1
    var farDistance: CGFloat = 7
    /// Sideways and vertical reach can differ: the footer leaves ~6 pt above
    /// and below the button, so vertical travel is capped.
    var maxVerticalDistance: CGFloat = 5
    /// Glow strength when retracted / extended. Kept close, so the only
    /// pulses you see are the two pushes outward — the return to rest is a
    /// quiet reset, not a flash.
    var nearIntensity: Double = 0.7
    var farIntensity: Double = 0.6
    var color: Color = MixrColors.secondaryPurple
    /// Stacked strokes that make the glow (width, opacity), from the crisp
    /// core outwards — a halo without a blur pass.
    var layers: [(width: CGFloat, opacity: Double)] = [(1, 0.55), (3.5, 0.22), (7, 0.08)]

    static let standard = HaloPulseStyle()

    /// 0 = retracted, 1 = fully out, at a moment in time: the keyframes,
    /// eased in and out (sine) between each pair.
    func extension_(at seconds: Double) -> Double {
        let p = (seconds / period).truncatingRemainder(dividingBy: 1)
        for (a, b) in zip(keyframes, keyframes.dropFirst()) where p <= b.time {
            let span = max(b.time - a.time, .ulpOfOne)
            let local = (p - a.time) / span
            let eased = (1 - cos(local * .pi)) / 2
            return a.extension + (b.extension - a.extension) * eased
        }
        return keyframes.last?.extension ?? 0
    }

    /// Room the drawing needs around the button (reach + widest stroke).
    var margin: CGSize {
        let stroke = (layers.map(\.width).max() ?? 1) / 2 + 2
        return CGSize(width: farDistance + stroke, height: maxVerticalDistance + stroke)
    }
}

/// The halo itself. Drawn into one Canvas per frame (a frame repaints, it
/// never re-lays out), driven by TimelineView so it stops completely when
/// removed and never keeps the app from going idle.
struct ImportHaloPulse: View {
    var style: HaloPulseStyle = .standard
    var cornerRadius: CGFloat = MixrRadius.button
    /// Multiplies time (DEBUG captures and the slowed preview use < 1).
    var timeScale: Double = 1

    var body: some View {
        let margin = style.margin
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let w = style.extension_(at: context.date.timeIntervalSinceReferenceDate * timeScale)
            Canvas { g, size in
                let button = CGRect(origin: .zero, size: size)
                    .insetBy(dx: margin.width, dy: margin.height)
                let distance = style.nearDistance + (style.farDistance - style.nearDistance) * CGFloat(w)
                let rise = min(distance, style.maxVerticalDistance)
                let path = Path(
                    roundedRect: button.insetBy(dx: -distance, dy: -rise),
                    cornerRadius: cornerRadius + rise,
                    style: .continuous
                )
                let intensity = style.nearIntensity + (style.farIntensity - style.nearIntensity) * w
                for layer in style.layers {
                    g.stroke(
                        path,
                        with: .color(style.color.opacity(intensity * layer.opacity)),
                        lineWidth: layer.width
                    )
                }
            }
        }
        .padding(.horizontal, -margin.width)
        .padding(.vertical, -margin.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Canvas previews

private struct HaloPulsePreviewButton: View {
    var timeScale: Double = 1

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                Text("Import Songs").mixrFont(.button)
            }
            .foregroundStyle(MixrColors.textPrimary)
            .frame(width: 144)
            .padding(.vertical, MixrLayout.buttonPaddingV)
            .background {
                GlassBackground(level: .default, cornerRadius: MixrRadius.button)
                    .clipShape(RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                    }
                    .overlay { ImportHaloPulse(timeScale: timeScale) }
            }

            MixrSFXOutlineButtonLabel(style: .d)
        }
        .padding(.horizontal, 10)
        .frame(width: 270, height: 46)
        .background(MixrColors.backgroundSecondary)
    }
}

#Preview("Halo pulse") {
    HaloPulsePreviewButton()
        .padding(40)
        .background(MixrColors.background)
        .preferredColorScheme(.dark)
}

#Preview("Halo pulse — quarter speed") {
    HaloPulsePreviewButton(timeScale: 0.25)
        .padding(40)
        .background(MixrColors.background)
        .preferredColorScheme(.dark)
}

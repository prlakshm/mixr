import SwiftUI

struct MixrPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .mixrFont(.button)
            .foregroundStyle(MixrColors.textPrimary)
            .padding(.horizontal, MixrLayout.buttonPaddingH)
            .padding(.vertical, MixrLayout.buttonPaddingV)
            .background(MixrGradients.accentLinear)
            .clipShape(RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
            }
            .shadow(color: MixrColors.primaryPurple.opacity(0.35), radius: 12, x: 0, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Frosted glass pill shared by Export, Import Songs and sfx, so the
/// editor's buttons are one family. `isPulsing` keeps a breathing
/// shockwave around the button to say "start here" (a held, brighter rim
/// under Reduce Motion). The wave is driven per frame, not by a repeating animation, so
/// it costs nothing when off and never keeps the app from going idle.
struct MixrGlassButtonChrome: View {
    var cornerRadius: CGFloat = MixrRadius.button
    var isPulsing: Bool = false
    var shockwave: MixrShockwaveStyle = .current

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GlassBackground(level: .default, cornerRadius: cornerRadius)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6) }
            .overlay {
                if isPulsing {
                    if reduceMotion {
                        shape.strokeBorder(Color.white.opacity(0.42), lineWidth: 0.8)
                            .transition(.opacity)
                    } else {
                        MixrShockwave(style: shockwave, cornerRadius: cornerRadius)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.25), value: isPulsing)
    }
}

/// How the always-on shockwave around a button moves (design review).
/// Something is always visible: rings grow out and settle back (or roll
/// outward over a resting rim), faintest at their widest.
enum MixrShockwaveStyle: String, CaseIterable {
    /// One crisp white ring that breathes out, back in, and rests.
    case breathe
    /// Two fine white rings on the same breath, half a cycle apart: one is
    /// always heading out while the other comes home.
    case sonar
    /// A soft violet halo breathing on the same rhythm.
    case halo
    /// Fine violet rings launched from a resting rim, a third of a cycle
    /// apart, decelerating and thinning as they spread.
    case soundRings

    static var current: MixrShockwaveStyle {
#if DEBUG
        if let style = UITestLaunchHooks.shockwaveStyle { return style }
#endif
        return .breathe
    }

    /// One ring at a moment: how far past the button it sits, how visible
    /// it is, and how thick its core line is.
    struct Ring {
        var distance: CGFloat
        var opacity: Double
        var lineWidth: CGFloat
    }

    /// Strong ease-in-out for on-screen movement (the breath).
    static let breathCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.77, y: 0),
        endControlPoint: UnitPoint(x: 0.175, y: 1)
    )
    /// Strong ease-out: a wave leaves fast and settles as it spreads.
    static let waveCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.23, y: 1),
        endControlPoint: UnitPoint(x: 0.32, y: 1)
    )

    /// 0 at rest … 1 fully out. Out 1.3 s, back 1.3 s, rest 0.4 s.
    static func breath(at t: Double) -> Double {
        let cycle = 3.0, out = 1.3, back = 1.3
        let p = t.truncatingRemainder(dividingBy: cycle)
        if p < out { return breathCurve.value(at: p / out) }
        if p < out + back { return 1 - breathCurve.value(at: (p - out) / back) }
        return 0
    }

    func rings(at t: Double) -> [Ring] {
        switch self {
        case .breathe:
            let w = Self.breath(at: t)
            return [Ring(
                distance: 1.5 + 7.5 * CGFloat(w),
                opacity: 0.6 - 0.45 * w,
                lineWidth: 1.25 - 0.5 * CGFloat(w)
            )]
        case .sonar:
            return [0.0, 1.5].map { offset in
                let w = Self.breath(at: t + offset)
                return Ring(
                    distance: 1.5 + 8.5 * CGFloat(w),
                    opacity: 0.5 - 0.38 * w,
                    lineWidth: 1.0 - 0.4 * CGFloat(w)
                )
            }
        case .halo:
            let w = Self.breath(at: t)
            return [Ring(
                distance: 1 + 6 * CGFloat(w),
                opacity: 1 - 0.55 * w,
                lineWidth: 1
            )]
        case .soundRings:
            let travel = 2.1
            // The resting rim: always there, right on the button.
            var rings = [Ring(distance: 1, opacity: 0.24, lineWidth: 1)]
            for k in 0..<3 {
                let p = (t / travel + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                let spread = Self.waveCurve.value(at: p)
                let appear = min(1, p / 0.12)
                rings.append(Ring(
                    distance: 1 + 11 * CGFloat(spread),
                    opacity: 0.6 * appear * pow(1 - p, 1.5),
                    lineWidth: 1.2 - 0.7 * CGFloat(p)
                ))
            }
            return rings
        }
    }

    var color: Color {
        self == .breathe || self == .sonar ? .white : MixrColors.secondaryPurple
    }

    /// Glow layers drawn around each ring's core line (width multiplier,
    /// opacity multiplier) — a halo from stacked strokes, no blur pass.
    var glowLayers: [(width: CGFloat, opacity: Double)] {
        switch self {
        case .breathe, .sonar, .soundRings: [(1, 1)]
        case .halo: [(1, 0.55), (3.5, 0.22), (7, 0.08)]
        }
    }
}

/// The always-on rings around a button. Drawn into one Canvas per frame:
/// a frame repaints but never re-lays out.
struct MixrShockwave: View {
    let style: MixrShockwaveStyle
    var cornerRadius: CGFloat = MixrRadius.button

    /// Furthest a ring travels sideways.
    static let reach: CGFloat = 13
    /// The footer leaves ~6pt above and below the button: rings spread fully
    /// sideways but stay inside vertically, so the panels never cut them.
    static let maxVerticalSpread: CGFloat = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let rings = style.rings(at: Self.clock(context.date))
            Canvas { g, size in
                let button = CGRect(origin: .zero, size: size)
                    .insetBy(dx: Self.reach, dy: Self.maxVerticalSpread + 4)
                for ring in rings where ring.opacity > 0.005 {
                    let rise = min(ring.distance, Self.maxVerticalSpread)
                    let rect = button.insetBy(dx: -ring.distance, dy: -rise)
                    let path = Path(
                        roundedRect: rect,
                        cornerRadius: cornerRadius + rise,
                        style: .continuous
                    )
                    for layer in style.glowLayers {
                        g.stroke(
                            path,
                            with: .color(style.color.opacity(ring.opacity * layer.opacity)),
                            lineWidth: ring.lineWidth * layer.width
                        )
                    }
                }
            }
        }
        // A fixed canvas larger than the button (room for the reach and the
        // halo's widest stroke); only its pixels change per frame.
        .padding(.horizontal, -Self.reach)
        .padding(.vertical, -(Self.maxVerticalSpread + 4))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Wall-clock seconds (DEBUG captures can slow it down).
    static func clock(_ date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
#if DEBUG
        return t * UITestLaunchHooks.animationTimeScale
#else
        return t
#endif
    }
}

/// The glass buttons' press: the same 0.85 dim Export uses, for buttons
/// that draw their own glass label (Import Songs, sfx).
struct MixrGlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MixrSecondaryGlassButtonStyle: ButtonStyle {
    var partyRole: PartyModeSurfaceRole = .button
    /// Toolbar chrome scale — 1.0 on a phone, larger on tablets and desktop.
    var scale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: MixrRadius.button, style: .continuous)
        configuration.label
            .mixrScaledFont(
                size: MixrTextStyle.button.size * scale,
                weight: MixrTextStyle.button.weight,
                design: MixrTextStyle.button.design,
                relativeTo: MixrTextStyle.button.relativeTextStyle
            )
            .foregroundStyle(MixrColors.textPrimary)
            .padding(.horizontal, MixrLayout.buttonPaddingH * scale)
            .padding(.vertical, MixrLayout.buttonPaddingV * scale)
            .background { MixrGlassButtonChrome() }
            .partyModeBorder(
                shape: shape,
                role: partyRole,
                lighting: partyRole == .export ? .violetTrailing : .coolLeading,
                glintOffset: .near
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MixrIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MixrColors.textPrimary)
            .frame(
                width: MixrLayout.iconButtonSize,
                height: MixrLayout.iconButtonSize
            )
            .background(MixrColors.primaryPurple)
            .clipShape(Circle())
            .shadow(color: MixrColors.primaryPurple.opacity(0.32), radius: 10, x: 0, y: 3)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MixrIconGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MixrColors.textPrimary)
            .frame(
                width: MixrLayout.iconButtonSize,
                height: MixrLayout.iconButtonSize
            )
            .background {
                GlassBackground(level: .default, cornerRadius: MixrRadius.icon)
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.55)
            }
            .partyModeBorder(
                shape: Circle(),
                role: .compactControl,
                lighting: .clockwise,
                glintOffset: .far
            )
            .shadow(color: .black.opacity(0.32), radius: 5, x: 0, y: 2)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MixrToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .mixrFont(.caption)
            .foregroundStyle(MixrColors.textPrimary)
            .frame(
                width: MixrLayout.toggleButtonWidth,
                height: MixrLayout.toggleButtonWidth
            )
            .background {
                GlassBackground(level: .default, cornerRadius: MixrLayout.toggleButtonWidth / 2)
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .partyModeBorder(
                shape: Circle(),
                role: .compactControl,
                lighting: .coolLeading,
                glintOffset: .far
            )
            .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 1.5)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == MixrPrimaryButtonStyle {
    static var mixrPrimary: MixrPrimaryButtonStyle { MixrPrimaryButtonStyle() }
}

extension ButtonStyle where Self == MixrSecondaryGlassButtonStyle {
    static var mixrSecondaryGlass: MixrSecondaryGlassButtonStyle { MixrSecondaryGlassButtonStyle() }
}

extension ButtonStyle where Self == MixrIconButtonStyle {
    static var mixrIcon: MixrIconButtonStyle { MixrIconButtonStyle() }
}

extension ButtonStyle where Self == MixrIconGlassButtonStyle {
    static var mixrIconGlass: MixrIconGlassButtonStyle { MixrIconGlassButtonStyle() }
}

struct MixrCompactTrackToggleButtonStyle: ButtonStyle {
    private let size = MixrLayout.trackToggleSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .mixrFont(.caption)
            .foregroundStyle(MixrColors.textPrimary.opacity(0.92))
            .frame(width: size, height: size)
            .background {
                GlassBackground(level: .default, cornerRadius: size / 2)
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .partyModeBorder(
                shape: Circle(),
                role: .compactControl,
                lighting: .violetTrailing,
                glintOffset: .far
            )
            .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 1.5)
            .opacity(configuration.isPressed ? 0.85 : 1)
            // Explicit touch area: the circle plus half the 5pt gap on each
            // side, 44pt tall. Decoration can't widen M over S, and the
            // small visual stays an easy target.
            .padding(.horizontal, 2.5)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .padding(.horizontal, -2.5)
            .padding(.vertical, -8)
    }
}

extension ButtonStyle where Self == MixrCompactTrackToggleButtonStyle {
    static var mixrCompactTrackToggle: MixrCompactTrackToggleButtonStyle { MixrCompactTrackToggleButtonStyle() }
}

extension ButtonStyle where Self == MixrToggleButtonStyle {
    static var mixrToggle: MixrToggleButtonStyle { MixrToggleButtonStyle() }
}

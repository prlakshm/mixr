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
/// A ring is always visible; it grows out and shrinks back, faintest at
/// its widest.
enum MixrShockwaveStyle: String, CaseIterable {
    /// One crisp ring breathing out and in.
    case breathe
    /// Two rings breathing half a cycle apart.
    case sonar
    /// A soft, blurred violet halo breathing.
    case halo
    /// Three fine rings rolling outward, staggered so one is always there.
    case soundRings
    /// Rests close, beats twice, rests.
    case heartbeat

    static var current: MixrShockwaveStyle {
#if DEBUG
        if let style = UITestLaunchHooks.shockwaveStyle { return style }
#endif
        return .breathe
    }

    /// One ring's look at time `t` (seconds): how far out it sits and how
    /// visible it is.
    struct Ring {
        var distance: CGFloat
        var opacity: Double
    }

    struct Look {
        var lineWidth: CGFloat
        var blur: CGFloat
        var color: Color
    }

    var look: Look {
        switch self {
        case .breathe, .sonar, .heartbeat: Look(lineWidth: 1.2, blur: 0, color: .white)
        case .halo: Look(lineWidth: 5, blur: 4, color: MixrColors.secondaryPurple)
        case .soundRings: Look(lineWidth: 1, blur: 0, color: MixrColors.secondaryPurple)
        }
    }

    func rings(at t: Double) -> [Ring] {
        /// 0…1…0 over `period`, eased (raised cosine).
        func breath(_ t: Double, period: Double, phase: Double = 0) -> Double {
            (1 - cos((t / period + phase) * 2 * .pi)) / 2
        }
        func ring(_ w: Double, near: CGFloat, far: CGFloat, nearOpacity: Double, farOpacity: Double) -> Ring {
            Ring(
                distance: near + (far - near) * CGFloat(w),
                opacity: nearOpacity + (farOpacity - nearOpacity) * w
            )
        }
        switch self {
        case .breathe:
            return [ring(breath(t, period: 2.4), near: 2, far: 9, nearOpacity: 0.55, farOpacity: 0.18)]
        case .sonar:
            return [0, 0.5].map {
                ring(breath(t, period: 2.6, phase: $0), near: 2, far: 11, nearOpacity: 0.5, farOpacity: 0.12)
            }
        case .halo:
            return [ring(breath(t, period: 2.4), near: 1, far: 9, nearOpacity: 0.6, farOpacity: 0.25)]
        case .soundRings:
            // Continuous outward travel; each ring fades in off the button
            // and out at the edge, a third of a cycle apart.
            return [0, 1.0 / 3, 2.0 / 3].map { offset in
                let p = (t / 1.8 + offset).truncatingRemainder(dividingBy: 1)
                let fade = sin(p * .pi)
                return Ring(distance: 1 + 9 * CGFloat(p), opacity: 0.55 * fade)
            }
        case .heartbeat:
            // Two quick beats in the first 0.6 s of every 1.8 s, then rest.
            let p = t.truncatingRemainder(dividingBy: 1.8)
            let beat: Double = p < 0.6
                ? pow(sin(p / 0.3 * .pi), 2) * (p < 0.3 ? 1 : 0.7)
                : 0
            return [ring(beat, near: 2, far: 7, nearOpacity: 0.4, farOpacity: 0.75)]
        }
    }
}

/// The always-on rings around a button, drawn per frame.
struct MixrShockwave: View {
    let style: MixrShockwaveStyle
    var cornerRadius: CGFloat = MixrRadius.button

    /// The footer leaves ~6pt above and below the button: rings spread fully
    /// sideways but stay inside vertically, so the panels never cut them.
    static let maxVerticalSpread: CGFloat = 5

    var body: some View {
        let look = style.look
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let rings = style.rings(at: Self.clock(context.date))
            ZStack {
                ForEach(rings.indices, id: \.self) { i in
                    let ring = rings[i]
                    let rise = min(ring.distance, Self.maxVerticalSpread)
                    RoundedRectangle(cornerRadius: cornerRadius + rise, style: .continuous)
                        .stroke(look.color, lineWidth: look.lineWidth)
                        .blur(radius: look.blur)
                        .padding(.horizontal, -ring.distance)
                        .padding(.vertical, -rise)
                        .opacity(ring.opacity)
                }
            }
        }
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

import SwiftUI

// MARK: - Effect Control Tray

enum EffectTrayMetrics {
    /// Fallback width for previews / compact contexts.
    static let sliderOnlyWidth: CGFloat = 190
    static let presetWidth: CGFloat = 236
    static let height: CGFloat = EffectCardMetrics.height
    static let cornerRadius: CGFloat = EffectCardMetrics.cornerRadius
    /// Expanded tray fills remaining panel width after the focused card.
    /// (Legacy fraction kept only as documentation — tray uses leftover space.)
    static let expandedSectionWidthFraction: CGFloat = 1.0
    /// Slider row occupies this fraction of the tray content width, centered.
    static let sliderRowWidthFraction: CGFloat = 0.75
    /// Preset track width — scaled by option count so Pitch (2) and
    /// Reverb/Echo (3) keep similar per-segment spacing. Pill widths stay
    /// content-measured; only the outer track grows.
    /// Baseline: transition Duration width × 1.10 for a 3-option control.
    private static let presetSegmentedWidth3: CGFloat =
        TLClipEditingMetrics.menuSettingsDurationSegmentedWidth * 1.10

    static func presetSegmentedWidth(for effect: MixrEffect) -> CGFloat {
        switch effect {
        case .pitchUp:
            // 2 options — narrower so gaps match the 3-option controls.
            presetSegmentedWidth3 * (2.0 / 3.0)
        default:
            presetSegmentedWidth3
        }
    }

    static let presetSegmentedHeight: CGFloat = 28
    /// Nudge slider + presets slightly lower in the tray.
    static let presetContentDownshift: CGFloat = 3.5
    /// Slow ease for card slide / tray grow / sibling push (+10% from 0.62).
    static let expandAnimationDuration: Double = 0.682

    static func width(for effect: MixrEffect) -> CGFloat {
        switch effect {
        case .reverb, .echo, .pitchUp:
            presetWidth
        default:
            sliderOnlyWidth
        }
    }
}

/// The control tray revealed when an effect card slides open — a 0…100
/// level slider, plus preset segmented controls for Reverb, Echo, Pitch.
/// Flanger and Blur are intensity-slider-only. Values are per selected
/// clip and persist on the clip model.
struct EffectControlTray: View {
    let effect: MixrEffect
    /// 0…100 effect level for the targeted clip.
    var level: Double
    var reverbPreset: ReverbPreset = .smallRoom
    var echoPreset: EchoPreset = .classic
    var pitchDirection: PitchDirection = .up
    /// Matches the effect card it grows out of, which scales with the screen.
    var height: CGFloat = EffectTrayMetrics.height
    var onLevelChanged: (Double) -> Void = { _ in }
    /// true on drag start, false on drag end — for undo commits.
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onReverbPreset: (ReverbPreset) -> Void = { _ in }
    var onEchoPreset: (EchoPreset) -> Void = { _ in }
    var onPitchDirection: (PitchDirection) -> Void = { _ in }

    @State private var hasDragged = false

    private var hasPresets: Bool {
        switch effect {
        case .reverb, .echo, .pitchUp: true
        default: false
        }
    }

    /// Right label shows gray "100" until the user drags (or a stored
    /// value exists), then the current value in white.
    private var showsCurrentValue: Bool { hasDragged || level > 0.5 }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(0, geo.size.width)
            let sliderWidth = contentWidth * EffectTrayMetrics.sliderRowWidthFraction
            // Never wider than the tray — keeps preset tracks centered.
            let presetWidth = min(
                EffectTrayMetrics.presetSegmentedWidth(for: effect),
                max(0, contentWidth - 16)
            )

            VStack(spacing: hasPresets ? 7 : 0) {
                sliderRow
                    .frame(width: sliderWidth)

                if hasPresets {
                    presetControl
                        .frame(
                            width: presetWidth,
                            height: EffectTrayMetrics.presetSegmentedHeight
                        )
                }
            }
            // Always center slider + presets horizontally in the settings glass.
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(
                .top,
                hasPresets ? 8 + EffectTrayMetrics.presetContentDownshift : 0
            )
            .padding(
                .bottom,
                hasPresets ? max(0, 8 - EffectTrayMetrics.presetContentDownshift) : 0
            )
            .frame(
                width: contentWidth,
                height: geo.size.height,
                alignment: hasPresets ? .top : .center
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background { trayGlass }
        .clipShape(RoundedRectangle(cornerRadius: EffectTrayMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EffectTrayMetrics.cornerRadius, style: .continuous)
                .strokeBorder(effect.color.opacity(0.30), lineWidth: 0.6)
        }
        .partyModeBorder(
            shape: RoundedRectangle(
                cornerRadius: EffectTrayMetrics.cornerRadius,
                style: .continuous
            ),
            role: .semantic,
            lighting: .violetTrailing,
            semanticColor: effect.color,
            glintOffset: .far
        )
        .shadow(color: .black.opacity(0.32), radius: 6, x: 0, y: 2)
        .shadow(color: effect.color.opacity(0.14), radius: 9)
    }

    // MARK: Slider row

    private var sliderRow: some View {
        HStack(spacing: 8) {
            Text("0")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(MixrColors.textSecondary)

            TLVolumeSlider(
                value: Binding(
                    get: { min(max(level / 100, 0), 1) },
                    set: { onLevelChanged($0 * 100) }
                ),
                accentColor: effect.color,
                trackColor: effect.color.opacity(0.7),
                onEditingChanged: { editing in
                    if editing { hasDragged = true }
                    onEditingChanged(editing)
                }
            )
            .frame(maxWidth: .infinity)

            Text(showsCurrentValue ? "\(Int(level.rounded()))" : "100")
                .font(.system(size: 9.5, weight: showsCurrentValue ? .semibold : .medium))
                .foregroundStyle(showsCurrentValue ? MixrColors.textPrimary : MixrColors.textSecondary)
                .frame(width: 22, alignment: .trailing)
        }
    }

    // MARK: Presets — the existing Mixr segmented control, accent = effect color

    @ViewBuilder
    private var presetControl: some View {
        if effect == .reverb {
            TLTransitionSettingsSegmentedControl(
                options: ReverbPreset.allCases,
                selected: reverbPreset,
                trackColor: effect.color,
                fontSize: 9.5,
                selectionSpringResponse: 0.30,
                title: { option, _ in option.title },
                onSelect: onReverbPreset
            )
        } else if effect == .echo {
            TLTransitionSettingsSegmentedControl(
                options: EchoPreset.allCases,
                selected: echoPreset,
                trackColor: effect.color,
                fontSize: 9.5,
                selectionSpringResponse: 0.30,
                title: { option, _ in option.title },
                onSelect: onEchoPreset
            )
        } else if effect == .pitchUp {
            // Duration-style labels: only the selected side says "Pitch …".
            TLTransitionSettingsSegmentedControl(
                options: PitchDirection.allCases,
                selected: pitchDirection,
                trackColor: effect.color,
                fontSize: 9.5,
                selectionSpringResponse: 0.30,
                title: { option, isSelected in option.label(isSelected: isSelected) },
                onSelect: onPitchDirection
            )
        }
    }

    // MARK: Glass

    private var trayGlass: some View {
        let shape = RoundedRectangle(cornerRadius: EffectTrayMetrics.cornerRadius, style: .continuous)
        return shape
            .fill(Color(hex: "05070D").opacity(0.56))
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.04)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.clear,
                            Color.black.opacity(0.14),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            effect.color.opacity(0.07),
                            Color.clear,
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
            }
    }
}

#Preview("Effect Trays") {
    VStack(spacing: 16) {
        EffectControlTray(effect: .reverb, level: 0)
            .frame(width: EffectTrayMetrics.presetWidth)
        EffectControlTray(effect: .pitchUp, level: 80, pitchDirection: .up)
            .frame(width: EffectTrayMetrics.presetWidth)
        EffectControlTray(effect: .echo, level: 64, echoPreset: .pingPong)
            .frame(width: EffectTrayMetrics.presetWidth)
        EffectControlTray(effect: .flanger, level: 55)
            .frame(width: EffectTrayMetrics.sliderOnlyWidth)
        EffectControlTray(effect: .blur, level: 32)
            .frame(width: EffectTrayMetrics.sliderOnlyWidth)
    }
    .padding(24)
    .background {
        MixrGradients.backgroundLinear
    }
    .preferredColorScheme(.dark)
}

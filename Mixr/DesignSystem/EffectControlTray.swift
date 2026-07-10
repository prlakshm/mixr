import SwiftUI

// MARK: - Effect Control Tray

enum EffectTrayMetrics {
    static let sliderOnlyWidth: CGFloat = 190
    static let presetWidth: CGFloat = 236
    static let height: CGFloat = EffectCardMetrics.height
    static let cornerRadius: CGFloat = EffectCardMetrics.cornerRadius

    static func width(for effect: MixrEffect) -> CGFloat {
        effect == .reverb || effect == .echo ? presetWidth : sliderOnlyWidth
    }
}

/// The control tray revealed when an effect card slides open — a 0…100
/// level slider, plus the preset segmented control for Reverb and Echo.
/// Values are per selected clip and persist on the clip model.
struct EffectControlTray: View {
    let effect: MixrEffect
    /// 0…100 effect level for the targeted clip.
    var level: Double
    var reverbPreset: ReverbPreset = .smallRoom
    var echoPreset: EchoPreset = .classic
    var onLevelChanged: (Double) -> Void = { _ in }
    /// true on drag start, false on drag end — for undo commits.
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onReverbPreset: (ReverbPreset) -> Void = { _ in }
    var onEchoPreset: (EchoPreset) -> Void = { _ in }

    @State private var hasDragged = false

    private var hasPresets: Bool { effect == .reverb || effect == .echo }

    /// Right label shows gray "100" until the user drags (or a stored
    /// value exists), then the current value in white.
    private var showsCurrentValue: Bool { hasDragged || level > 0.5 }

    var body: some View {
        VStack(spacing: hasPresets ? 7 : 0) {
            sliderRow
                .frame(maxHeight: hasPresets ? nil : .infinity)

            if hasPresets {
                presetControl
                    .frame(height: 28)
            }
        }
        .padding(.horizontal, MixrSpacing.md)
        .padding(.vertical, hasPresets ? 8 : MixrSpacing.md)
        .frame(width: EffectTrayMetrics.width(for: effect), height: EffectTrayMetrics.height)
        .background { trayGlass }
        .clipShape(RoundedRectangle(cornerRadius: EffectTrayMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EffectTrayMetrics.cornerRadius, style: .continuous)
                .strokeBorder(effect.color.opacity(0.30), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.32), radius: 6, x: 0, y: 2)
        .shadow(color: effect.color.opacity(0.14), radius: 9)
    }

    // MARK: Slider row

    private var sliderRow: some View {
        HStack(spacing: 8) {
            Text("0")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                .font(.system(size: 9, weight: showsCurrentValue ? .semibold : .medium, design: .monospaced))
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
        EffectControlTray(effect: .echo, level: 64, echoPreset: .pingPong)
        EffectControlTray(effect: .warmth, level: 32)
    }
    .padding(24)
    .background {
        MixrGradients.backgroundLinear
    }
    .preferredColorScheme(.dark)
}

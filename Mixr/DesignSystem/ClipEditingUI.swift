import SwiftUI
import UIKit

// MARK: - Metrics

enum TLClipEditingMetrics {
    static let toolbarHorizontalPadding: CGFloat = 10
    static let toolbarTrailingPadding: CGFloat = 2.5
    /// Edge-to-edge gap between action labels.
    static let toolbarActionSpacing: CGFloat = 24
    /// Tighter gap before Delete — its red label recedes optically against
    /// the dark pane, so a smaller gap reads as equal to the others.
    static let toolbarDeleteActionSpacing: CGFloat = 19
    /// The action row is two equal halves flanking the center gap
    /// (Split+Speed right-aligned, Duplicate+Delete left-aligned), so the
    /// Speed↔Duplicate midpoint is the exact pane center — which the
    /// presenting overlay pins to the playhead.
    static let toolbarActionHalfWidth: CGFloat = 104
    static let toolbarWidth: CGFloat =
        toolbarHorizontalPadding * 2
        + toolbarActionHalfWidth * 2
        + toolbarActionSpacing
    static let toolbarSpeedWidth: CGFloat = 168
    static let toolbarBodyHeight: CGFloat = 50
    static let toolbarBodyHorizontalOffset: CGFloat = 12
    static let toolbarPointerW: CGFloat = 7
    static let toolbarPointerH: CGFloat = 4
    static let toolbarMorphDuration: Double = 0.28
    static let minPlaybackSpeed: Double = 0.25
    static let maxPlaybackSpeed: Double = 4.0
    static let menuWidth: CGFloat = 170
    static let menuSettingsWidth: CGFloat = 306.5
    static let menuSettingsDurationSegmentedWidth: CGFloat = 210
    static let menuSettingsCurveSegmentedWidth: CGFloat = 224
    static let menuSettingsControlGap: CGFloat = 11.5
    static let menuRowHeight: CGFloat = 42
    /// Sized so heading→Duration spacing matches Duration↔Curve control gap.
    static let menuSettingsHeaderRowHeight: CGFloat = 20.5
    static let menuSettingsHeaderChevronTitleGap: CGFloat = 9
    static let menuSettingsHeaderLeadingOffset: CGFloat = -0.75
    static let menuSettingsHorizontalPadding: CGFloat = 20
    static let menuSettingsTopPadding: CGFloat = 8
    static let menuSettingsBottomPadding: CGFloat = 8
    static let menuSlideDuration: Double = 0.30
    static var menuEstimatedHeight: CGFloat {
        CGFloat(ClipTransitionType.allCases.count) * menuRowHeight + 6
    }
    static var menuSettingsEstimatedHeight: CGFloat {
        menuSettingsHeaderRowHeight
            + menuRowHeight * 2
            + menuSettingsTopPadding
            + menuSettingsBottomPadding
    }
    static let menuIconBoxSize: CGFloat = 22.5
    static let menuIconBoxRadius: CGFloat = 6
    static let iconBoxRadius: CGFloat = 7
    static let gripVisual: CGFloat = 11
    static let gripHit: CGFloat = 32
    static let indicatorSize: CGFloat = 20

    /// Floating clip-editing panels — above transport and clipped timeline content.
    static let toolbarZIndex: CGFloat = 200
    static let menuZIndex: CGFloat = 201
}

// MARK: - Press Style

struct TLClipActionPressStyle: ButtonStyle {
    var isDestructive: Bool = false
    var fillsCell: Bool = false
    var isHovered: Bool = false
    var expandsHorizontally: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let pressedFill =
            isDestructive
            ? Color.red.opacity(0.18)
            : Color.black.opacity(0.34)
        let hoverFill =
            isDestructive
            ? Color.red.opacity(0.10)
            : Color.black.opacity(0.18)

        let label = Group {
            if expandsHorizontally {
                configuration.label
                    .frame(maxWidth: .infinity)
            } else {
                configuration.label
            }
        }

        label
            .background {
                if fillsCell {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            configuration.isPressed
                                ? pressedFill
                                : (isHovered ? hoverFill : Color.clear)
                        )
                }
            }
            .offset(y: configuration.isPressed ? 1.25 : 0)
            .opacity(configuration.isPressed && !fillsCell ? 0.88 : 1)
            .animation(
                .spring(response: 0.17, dampingFraction: 0.82),
                value: configuration.isPressed
            )
            .animation(
                .spring(response: 0.17, dampingFraction: 0.82),
                value: isHovered
            )
    }
}

private struct TLClipToolbarAction: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    private static let destructiveRed = Color(hex: "FF453A")

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6.4) {
                Image(systemName: icon)
                    .font(.system(size: iconFontSize, weight: .regular))
                    .foregroundStyle(
                        isDestructive
                            ? Self.destructiveRed.opacity(0.88)
                            : MixrColors.textPrimary.opacity(0.92)
                    )
                    .offset(y: iconVerticalOffset)
                    .frame(height: 14)

                Text(label)
                    .font(.system(size: 9.8, weight: isDestructive ? .regular : .medium))
                    .foregroundStyle(
                        isDestructive
                            ? Self.destructiveRed.opacity(0.78)
                            : MixrColors.textPrimary.opacity(0.92)
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(y: labelVerticalOffset)
            }
            .padding(.top, 2)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TLClipToolbarPressStyle(isDestructive: isDestructive))
    }

    private var iconFontSize: CGFloat {
        switch icon {
        case "gauge.with.dots.needle.67percent":
            13.2
        case "scissors":
            11.65
        case "doc.on.doc":
            11.35
        case "trash":
            11.4
        default:
            11.5
        }
    }

    private var iconVerticalOffset: CGFloat {
        switch icon {
        case "scissors":
            1.95
        case "gauge.with.dots.needle.67percent":
            2.0
        case "doc.on.doc":
            2.2
        case "trash":
            2.33
        default:
            0
        }
    }

    private var labelVerticalOffset: CGFloat {
        // Keep all labels on Speed's optical baseline.
        0.25
    }
}

/// Toolbar press: normal actions dim; Delete keeps soft reds and darkens by the shared factor.
private struct TLClipToolbarPressStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1.25 : 0)
            .opacity(
                configuration.isPressed
                    ? (isDestructive ? MixrAlertPressColors.pressFactor : 0.88)
                    : 1
            )
            .animation(
                .spring(response: 0.17, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

// MARK: - Transition Icon Box

struct TLTransitionIconBox: View {
    let transitionType: ClipTransitionType
    var highlighted: Bool = false
    var trackColor: Color = .white
    var size: CGFloat = TLClipEditingMetrics.menuIconBoxSize

    var body: some View {
        let radius =
            size == TLClipEditingMetrics.indicatorSize
            ? TLClipEditingMetrics.iconBoxRadius
            : TLClipEditingMetrics.menuIconBoxRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape
                .fill(
                    highlighted
                        ? trackColor.opacity(0.22)
                        : MixrColors.glassNavyStrong.opacity(0.52)
                )
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.06)
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    shape.strokeBorder(
                        highlighted
                            ? trackColor.opacity(0.48)
                            : Color.white.opacity(0.07),
                        lineWidth: 0.5
                    )
                }
                .overlay(alignment: .top) {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.09), Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.35)
                            )
                        )
                }

            transitionIcon
                .foregroundStyle(
                    highlighted ? trackColor : MixrColors.textPrimary
                )
                .font(.system(size: size * 0.44, weight: .medium))
        }
        .frame(width: size, height: size)
        .shadow(
            color: highlighted ? trackColor.opacity(0.30) : .clear,
            radius: 6
        )
    }

    @ViewBuilder
    private var transitionIcon: some View {
        switch transitionType {
        case .none:
            Image(systemName: "minus")
        case .crossfade:
            Image(systemName: "arrow.left.arrow.right")
        case .fadeOut:
            Image(systemName: "arrow.down.forward")
        case .echoOut:
            Image(systemName: "waveform")
        case .auto:
            Image(systemName: "sparkles")
        }
    }
}

// MARK: - Transition Grip

struct TLTransitionGrip: View {
    let trackColor: Color
    var isActive: Bool = false
    var transitionType: ClipTransitionType = .none

    @GestureState private var isPressed: Bool = false

    let onTap: () -> Void

    private let visual = TLClipEditingMetrics.gripVisual
    private let hit = TLClipEditingMetrics.gripHit

    private var hasTransition: Bool { transitionType != .none }
    private var showHalo: Bool { isActive || hasTransition }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())

            if showHalo && !hasTransition {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                trackColor.opacity(0.90),
                                trackColor.opacity(0.36),
                                trackColor.opacity(0.0),
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: 18
                        )
                    )
                    .frame(width: visual + 28, height: visual + 28)
                    .blur(radius: 3.5)

                Circle()
                    .strokeBorder(trackColor.opacity(0.92), lineWidth: 2.2)
                    .frame(width: visual + 10, height: visual + 10)
                    .shadow(color: trackColor.opacity(0.75), radius: 7)
            }

            if hasTransition {
                let boxSize = TLClipEditingMetrics.menuIconBoxSize
                let gripScale = boxSize / 26
                let glowSize = 46 * gripScale
                let ringSize = 28 * gripScale
                let shape = RoundedRectangle(
                    cornerRadius: TLClipEditingMetrics.menuIconBoxRadius,
                    style: .continuous
                )

                // Colored glow behind the icon box (always visible, brighter when active)
                RoundedRectangle(
                    cornerRadius: TLClipEditingMetrics.menuIconBoxRadius + 2,
                    style: .continuous
                )
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.72 : 0.52),
                            trackColor.opacity(isActive ? 0.95 : 0.80),
                            trackColor.opacity(isActive ? 0.45 : 0.32),
                            trackColor.opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 20 * gripScale
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: 4 * gripScale)

                // White separation ring so the box reads clearly over the waveform
                RoundedRectangle(
                    cornerRadius: TLClipEditingMetrics.menuIconBoxRadius + 2,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                .frame(width: ringSize, height: ringSize)

                // Glass icon box — custom plate with transition icon on top
                ZStack {
                    shape
                        .fill(Color(hex: "010207").opacity(0.96))
                        .background {
                            shape
                                .fill(trackColor.opacity(0.08))
                        }
                        .overlay {
                            shape.fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.10), Color.clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: UnitPoint(x: 0.5, y: 0.4)
                                )
                            )
                        }
                        .overlay {
                            shape.strokeBorder(
                                trackColor.opacity(0.60),
                                lineWidth: 1 * gripScale
                            )
                        }

                    TLTransitionIconBox(
                        transitionType: transitionType,
                        highlighted: true,
                        trackColor: trackColor,
                        size: boxSize
                    )
                    .background(Color.clear)
                    .compositingGroup()
                }
                .frame(width: boxSize, height: boxSize)
                .clipShape(shape)
                .shadow(color: trackColor.opacity(0.70), radius: 8 * gripScale)
                .shadow(
                    color: .black.opacity(0.55),
                    radius: 4 * gripScale,
                    x: 0,
                    y: 2 * gripScale
                )
                .scaleEffect(isPressed ? 0.92 : 1.0)
            } else {
                Circle()
                    .fill(Color.white.opacity(isPressed ? 0.15 : 0.07))
                    .frame(width: visual + 4, height: visual + 4)
                    .blur(radius: 3)

                Circle()
                    .strokeBorder(
                        Color.white.opacity(isPressed ? 1.0 : 0.84),
                        lineWidth: 1.5
                    )
                    .frame(width: visual, height: visual)
                    .scaleEffect(isPressed ? 0.93 : 1.0)

                Circle()
                    .fill(Color.black)
                    .frame(width: visual * 0.52, height: visual * 0.52)
            }
        }
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isActive)
        .animation(.easeOut(duration: 0.12), value: transitionType)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
                .onEnded { _ in onTap() }
        )
    }
}

// MARK: - Transition Indicator (applied state above clip edge)

struct TLClipTransitionIndicator: View {
    let transitionType: ClipTransitionType
    let trackColor: Color

    var body: some View {
        TLTransitionIconBox(
            transitionType: transitionType,
            highlighted: true,
            trackColor: trackColor,
            size: TLClipEditingMetrics.indicatorSize
        )
    }
}

// MARK: - Toolbar Pointer Shape

struct TLToolbarPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Clip Context Toolbar

struct TLClipContextToolbar: View {
    enum Mode: Equatable {
        case actions
        case speed
    }

    let trackColor: Color
    let mode: Mode
    let speedValue: Double
    let onSplit: () -> Void
    let onSpeed: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSpeedBack: () -> Void
    let onSpeedCommit: (Double) -> Void

    @State private var speedText: String = "1.0"
    @FocusState private var isSpeedFieldFocused: Bool

    private var bodyWidth: CGFloat {
        switch mode {
        case .actions: TLClipEditingMetrics.toolbarWidth
        case .speed: TLClipEditingMetrics.toolbarSpeedWidth
        }
    }

    var body: some View {
        let tbH = TLClipEditingMetrics.toolbarBodyHeight
        let pW = TLClipEditingMetrics.toolbarPointerW
        let pH = TLClipEditingMetrics.toolbarPointerH
        let radius: CGFloat = 11

        VStack(spacing: 0) {
            ZStack {
                actionsContent
                    .opacity(mode == .actions ? 1 : 0)
                    .allowsHitTesting(mode == .actions)

                speedContent
                    .opacity(mode == .speed ? 1 : 0)
                    .allowsHitTesting(mode == .speed)
            }
            .padding(.leading, TLClipEditingMetrics.toolbarHorizontalPadding)
            .padding(.trailing, TLClipEditingMetrics.toolbarTrailingPadding)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(width: bodyWidth, height: tbH)
            .background {
                let shape = RoundedRectangle(
                    cornerRadius: radius,
                    style: .continuous
                )
                shape
                    .fill(Color(hex: "050810").opacity(0.68))
                    .background {
                        shape
                            .fill(.ultraThinMaterial)
                            .opacity(0.10)
                            .environment(\.colorScheme, .dark)
                    }
                    .overlay {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.04), Color.clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: UnitPoint(x: 0.5, y: 0.35)
                                )
                            )
                    }
                    .overlay {
                        shape
                            .strokeBorder(
                                Color.white.opacity(0.09),
                                lineWidth: 0.5
                            )
                    }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
            // Actions mode is symmetric about the playhead pointer; only the
            // speed editor keeps its tuned sideways shift.
            .offset(
                x: mode == .actions
                    ? 0
                    : TLClipEditingMetrics.toolbarBodyHorizontalOffset
            )

            TLToolbarPointer()
                .fill(Color(hex: "050810").opacity(0.68))
                .overlay {
                    TLToolbarPointer()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.045), Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .frame(width: pW, height: pH)
        }
        .animation(
            .easeInOut(duration: TLClipEditingMetrics.toolbarMorphDuration),
            value: mode
        )
        .onAppear {
            speedText = Self.formattedSpeed(speedValue)
            if mode == .speed {
                isSpeedFieldFocused = true
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .speed {
                speedText = Self.formattedSpeed(speedValue)
                isSpeedFieldFocused = true
            } else {
                isSpeedFieldFocused = false
            }
        }
        .onChange(of: speedValue) { _, newValue in
            if mode == .speed, !isSpeedFieldFocused {
                speedText = Self.formattedSpeed(newValue)
            }
        }
    }

    private var actionsContent: some View {
        HStack(spacing: TLClipEditingMetrics.toolbarActionSpacing) {
            HStack(spacing: TLClipEditingMetrics.toolbarActionSpacing) {
                TLClipToolbarAction(
                    icon: "scissors",
                    label: "Split",
                    action: onSplit
                )

                TLClipToolbarAction(
                    icon: "gauge.with.dots.needle.67percent",
                    label: "Speed",
                    action: onSpeed
                )
            }
            .frame(
                width: TLClipEditingMetrics.toolbarActionHalfWidth,
                alignment: .trailing
            )

            HStack(spacing: TLClipEditingMetrics.toolbarDeleteActionSpacing) {
                TLClipToolbarAction(
                    icon: "doc.on.doc",
                    label: "Duplicate",
                    action: onDuplicate
                )

                TLClipToolbarAction(
                    icon: "trash",
                    label: "Delete",
                    isDestructive: true,
                    action: onDelete
                )
            }
            .frame(
                width: TLClipEditingMetrics.toolbarActionHalfWidth,
                alignment: .leading
            )
            .padding(.leading, -2)
        }
        // Equalize the pane's asymmetric content padding so the center gap
        // sits exactly at the pane's horizontal center.
        .padding(
            .trailing,
            TLClipEditingMetrics.toolbarHorizontalPadding
                - TLClipEditingMetrics.toolbarTrailingPadding
        )
    }

    private var speedContent: some View {
        HStack(spacing: 6) {
            Button(action: onSpeedBack) {
                MixrChevron(
                    direction: .back,
                    size: 11,
                    color: MixrColors.textPrimary.opacity(0.88)
                )
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("x")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MixrColors.textPrimary)

            TextField("1.0", text: $speedText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MixrColors.textPrimary)
                .multilineTextAlignment(.center)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .focused($isSpeedFieldFocused)
                .padding(.horizontal, 8)
                .frame(width: 76, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        }
                }
                .onSubmit { commitSpeed() }

            Button(action: commitSpeed) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func commitSpeed() {
        let parsed = Self.parseSpeed(speedText) ?? speedValue
        let clamped = min(
            TLClipEditingMetrics.maxPlaybackSpeed,
            max(TLClipEditingMetrics.minPlaybackSpeed, parsed)
        )
        speedText = Self.formattedSpeed(clamped)
        onSpeedCommit(clamped)
    }

    private static func parseSpeed(_ text: String) -> Double? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value > 0
        else { return nil }
        return value
    }

    private static func formattedSpeed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if abs(rounded.rounded() - rounded) < 0.001 {
            return String(format: "%.1f", rounded)
        }
        return String(format: "%g", rounded)
    }
}

// MARK: - Transition Menu

struct TLTransitionMenu: View {
    let selected: ClipTransition
    let trackColor: Color
    let onSelect: (ClipTransitionType) -> Void
    var onUpdate: (ClipTransition) -> Void = { _ in }

    @State private var page: MenuPage = .list

    private enum MenuPage: Equatable {
        case list
        case settings(ClipTransitionType)
    }

    private enum DurationOption: Double, CaseIterable, Identifiable {
        case one = 1
        case two = 2
        case four = 4
        case eight = 8

        var id: Double { rawValue }

        func label(isSelected: Bool) -> String {
            let n = Int(rawValue)
            if isSelected {
                return n == 1 ? "1 Beat" : "\(n) Beats"
            }
            return "\(n)"
        }
    }

    private enum CurveOption: String, CaseIterable, Identifiable {
        case linear = "linear"
        case easeInOut = "easeInOut"
        case easeOut = "easeOut"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .linear: "Linear"
            case .easeInOut: "Ease In/Out"
            case .easeOut: "Ease Out"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch page {
            case .list:
                menuRows
                    .frame(width: TLClipEditingMetrics.menuWidth)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading),
                            removal: .move(edge: .leading)
                        )
                    )
            case .settings(let txType):
                settingsPage(for: txType)
                    .frame(width: TLClipEditingMetrics.menuSettingsWidth)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        )
                    )
            }
        }
        .frame(
            width: currentMenuWidth,
            height: currentMenuHeight,
            alignment: .topLeading
        )
        .animation(
            .easeInOut(duration: TLClipEditingMetrics.menuSlideDuration),
            value: page
        )
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "050810").opacity(0.68))
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.10)
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.045), Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.35)
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        .onChange(of: selected.type) { _, newValue in
            if newValue == .none {
                page = .list
            }
        }
    }

    private var currentMenuWidth: CGFloat {
        switch page {
        case .list:
            TLClipEditingMetrics.menuWidth
        case .settings:
            TLClipEditingMetrics.menuSettingsWidth
        }
    }

    private var currentMenuHeight: CGFloat {
        switch page {
        case .list:
            TLClipEditingMetrics.menuEstimatedHeight
        case .settings:
            TLClipEditingMetrics.menuSettingsEstimatedHeight
        }
    }

    private var menuRows: some View {
        VStack(spacing: 0) {
            ForEach(ClipTransitionType.allCases) { txType in
                menuRow(txType)
                    .overlay(alignment: .bottom) {
                        if txType != ClipTransitionType.allCases.last {
                            Rectangle()
                                .fill(MixrColors.divider.opacity(0.5))
                                .frame(height: 0.25)
                                .padding(.leading, 44)
                        }
                    }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func menuRow(_ txType: ClipTransitionType) -> some View {
        let isSel = txType == selected.type
        Button {
            if txType == .none {
                onSelect(txType)
            } else {
                var tx =
                    selected.type == txType
                    ? selected
                    : ClipTransition(
                        type: txType,
                        duration: DurationOption.one.rawValue,
                        curve: CurveOption.linear.rawValue
                    )
                tx.type = txType
                onUpdate(tx)
                withAnimation(
                    .easeInOut(duration: TLClipEditingMetrics.menuSlideDuration)
                ) {
                    page = .settings(txType)
                }
            }
        } label: {
            HStack(spacing: 9) {
                TLTransitionIconBox(
                    transitionType: txType,
                    highlighted: isSel,
                    trackColor: trackColor
                )

                Text(txType.rawValue)
                    .font(
                        .system(size: 12, weight: isSel ? .semibold : .regular)
                    )
                    .foregroundStyle(
                        isSel ? trackColor : MixrColors.textPrimary
                    )

                Spacer()

                if isSel {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(trackColor)
                } else if txType != .none {
                    MixrChevron(direction: .forward)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: TLClipEditingMetrics.menuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TLClipActionPressStyle())
    }

    private func settingsPage(for txType: ClipTransitionType) -> some View {
        VStack(spacing: 0) {
            settingsHeader(txType)
                .overlay(alignment: .bottom) {
                    menuDivider
                }
            settingsRow(
                title: "Duration",
                control: durationControl,
                controlWidth: TLClipEditingMetrics
                    .menuSettingsDurationSegmentedWidth
            )
            .overlay(alignment: .bottom) {
                menuDivider
            }
            settingsRow(
                title: "Curve",
                control: curveControl,
                controlWidth: TLClipEditingMetrics
                    .menuSettingsCurveSegmentedWidth
            )
        }
        .padding(.horizontal, TLClipEditingMetrics.menuSettingsHorizontalPadding)
        .padding(.top, TLClipEditingMetrics.menuSettingsTopPadding)
        .padding(.bottom, TLClipEditingMetrics.menuSettingsBottomPadding)
    }

    private func settingsHeader(_ txType: ClipTransitionType) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: TLClipEditingMetrics.menuSettingsHeaderChevronTitleGap) {
                Button {
                    withAnimation(
                        .easeInOut(duration: TLClipEditingMetrics.menuSlideDuration)
                    ) {
                        page = .list
                    }
                } label: {
                    MixrChevron(direction: .back, size: 10.5)
                        .offset(y: 0.1)
                        .frame(height: TLClipEditingMetrics.menuSettingsHeaderRowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(txType.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
            }
            .offset(x: TLClipEditingMetrics.menuSettingsHeaderLeadingOffset)

            Spacer(minLength: 0)
        }
        .frame(height: TLClipEditingMetrics.menuSettingsHeaderRowHeight)
    }

    private func settingsRow<Control: View>(
        title: String,
        control: Control,
        controlWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(MixrColors.textPrimary)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: TLClipEditingMetrics.menuSettingsControlGap)

            control
                .frame(width: controlWidth)
        }
        .frame(height: TLClipEditingMetrics.menuRowHeight)
    }

    private var durationControl: some View {
        segmentedControl(
            options: DurationOption.allCases,
            selected: selectedDurationOption,
            fontSize: 10,
            selectionSpringResponse: 0.40,
            title: { $0.label(isSelected: $1) }
        ) { option in
            var tx = selected
            tx.duration = option.rawValue
            onUpdate(tx)
        }
    }

    private var curveControl: some View {
        segmentedControl(
            options: CurveOption.allCases,
            selected: selectedCurveOption,
            fontSize: 10.5,
            selectionSpringResponse: 0.30,
            title: { option, _ in option.title }
        ) { option in
            var tx = selected
            tx.curve = option.rawValue
            onUpdate(tx)
        }
    }

    private var selectedDurationOption: DurationOption {
        DurationOption.allCases.min {
            abs($0.rawValue - selected.duration)
                < abs($1.rawValue - selected.duration)
        } ?? .one
    }

    private var selectedCurveOption: CurveOption {
        CurveOption(rawValue: selected.curve) ?? .linear
    }

    private func segmentedControl<Option: Identifiable & Equatable>(
        options: [Option],
        selected: Option,
        fontSize: CGFloat = 10,
        selectionSpringResponse: Double = 0.30,
        title: @escaping (Option, Bool) -> String,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        TLTransitionSettingsSegmentedControl(
            options: options,
            selected: selected,
            trackColor: trackColor,
            fontSize: fontSize,
            selectionSpringResponse: selectionSpringResponse,
            title: title,
            onSelect: onSelect
        )
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(MixrColors.divider.opacity(0.5))
            .frame(height: 0.25)
    }
}

private struct TLSelectedSegmentTitleWidthKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGFloat] = [:]

    static func reduce(
        value: inout [AnyHashable: CGFloat],
        nextValue: () -> [AnyHashable: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Mixr's glass segmented control — shared by transition settings and
/// effect preset pickers (pass the effect color as `trackColor` there).
struct TLTransitionSettingsSegmentedControl<
    Option: Identifiable & Equatable
>: View {
    private let controlHeight: CGFloat = 28
    private let pillHeight: CGFloat = 24

    /// Gap between the selected pill and the outer edge of the segmented control.
    private let controlEdgeGap: CGFloat = 4.5

    /// Actual internal left/right padding inside the selected pill.
    private let selectedTextHorizontalPadding: CGFloat = 14

    private let minimumPillWidth: CGFloat = 46
    private let dividerWidth: CGFloat = 0.35

    let options: [Option]
    let selected: Option
    let trackColor: Color
    let fontSize: CGFloat
    let selectionSpringResponse: Double
    let title: (Option, Bool) -> String
    let onSelect: (Option) -> Void

    @State private var selectedTitleWidths: [AnyHashable: CGFloat] = [:]
    @State private var isPillStretching = false

    var body: some View {
        GeometryReader { proxy in
            let layout = segmentLayout(in: proxy.size.width)
            let selectedIndex = options.firstIndex(of: selected) ?? 0

            let selectedCenter =
                layout.centers.indices.contains(selectedIndex)
                ? layout.centers[selectedIndex]
                : proxy.size.width / 2

            let selectedPillWidth =
                layout.pillWidths.indices.contains(selectedIndex)
                ? layout.pillWidths[selectedIndex]
                : minimumPillWidth

            ZStack(alignment: .topLeading) {
                // Dividers stay behind the pill.
                ForEach(Array(options.enumerated()), id: \.element.id) {
                    index,
                    option in
                    if index != options.count - 1,
                        layout.dividerXs.indices.contains(index)
                    {
                        let nextOption = options[index + 1]
                        let dividerTouchesSelection =
                            option == selected || nextOption == selected

                        Rectangle()
                            .fill(MixrColors.divider.opacity(0.55))
                            .opacity(dividerTouchesSelection ? 0 : 1)
                            .frame(width: dividerWidth, height: 20)
                            .position(
                                x: layout.dividerXs[index],
                                y: controlHeight / 2
                            )
                    }
                }

                selectedSegmentGlass
                    .frame(width: selectedPillWidth, height: pillHeight)
                    .shadow(color: .black.opacity(0.24), radius: 1.2, x: 0, y: 0.5)
                    .shadow(color: .black.opacity(0.32), radius: 2.5, x: 0, y: 1.5)
                    .shadow(color: .black.opacity(0.15), radius: 4.5, x: 0, y: 2.5)
                    .scaleEffect(
                        x: isPillStretching ? 1.055 : 1.0,
                        y: 1.0,
                        anchor: .center
                    )
                    .position(x: selectedCenter, y: controlHeight / 2)

                // Visible labels are centered on the same centers as the pill.
                ForEach(Array(options.enumerated()), id: \.element.id) {
                    index,
                    option in
                    if layout.centers.indices.contains(index) {
                        let isSelected = option == selected

                        Text(title(option, isSelected))
                            .font(
                                .system(
                                    size: fontSize,
                                    weight: isSelected ? .medium : .regular
                                )
                            )
                            .foregroundStyle(
                                isSelected
                                    ? MixrColors.textPrimary
                                    : MixrColors.textSecondary
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: true, vertical: false)
                            .allowsHitTesting(false)
                            .position(
                                x: layout.centers[index],
                                y: controlHeight / 2
                            )
                    }
                }

                // Invisible buttons preserve generous tap targets without affecting label position.
                ForEach(Array(options.enumerated()), id: \.element.id) {
                    index,
                    option in
                    if layout.hitFrames.indices.contains(index) {
                        let hitFrame = layout.hitFrames[index]
                        let isSelected = option == selected

                        Button {
                            onSelect(option)
                        } label: {
                            Color.clear
                                .frame(
                                    width: hitFrame.width,
                                    height: controlHeight
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(title(option, isSelected))
                        .position(
                            x: hitFrame.midX,
                            y: controlHeight / 2
                        )
                    }
                }
            }
        }
        .frame(height: controlHeight)
        .overlay(alignment: .topLeading) {
            selectedTitleMeasurementLayer
        }
        .onPreferenceChange(TLSelectedSegmentTitleWidthKey.self) { widths in
            selectedTitleWidths = widths
        }
        .animation(
            .spring(response: selectionSpringResponse, dampingFraction: 0.76),
            value: selected
        )
        .animation(
            .spring(response: 0.18, dampingFraction: 0.68),
            value: isPillStretching
        )
        .onChange(of: selected) { _, _ in
            isPillStretching = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isPillStretching = false
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.26),
                            Color.black.opacity(0.21),
                            Color.black.opacity(0.30),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.08)
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08), Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.5)
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.124), lineWidth: 0.65)
                        .blur(radius: 0.25)
                        .mask(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.9),
                                    Color.white.opacity(0.45),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.34), lineWidth: 1)
                        .blur(radius: 0.55)
                        .offset(y: 1)
                        .mask(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
        }
    }

    private struct SegmentLayout {
        let centers: [CGFloat]
        let pillWidths: [CGFloat]
        let hitFrames: [CGRect]
        let dividerXs: [CGFloat]
    }

    private func segmentLayout(in controlWidth: CGFloat) -> SegmentLayout {
        let count = options.count

        guard count > 0 else {
            return SegmentLayout(
                centers: [],
                pillWidths: [],
                hitFrames: [],
                dividerXs: []
            )
        }

        let pillWidths = options.map { pillWidth(for: $0) }

        if count == 1 {
            let center = controlWidth / 2

            return SegmentLayout(
                centers: [center],
                pillWidths: pillWidths,
                hitFrames: [
                    CGRect(
                        x: 0,
                        y: 0,
                        width: controlWidth,
                        height: controlHeight
                    )
                ],
                dividerXs: []
            )
        }

        let firstCenter = controlEdgeGap + pillWidths[0] / 2
        let lastCenter =
            controlWidth - controlEdgeGap - pillWidths[count - 1] / 2
        let usableLastCenter = max(firstCenter, lastCenter)
        let step = (usableLastCenter - firstCenter) / CGFloat(count - 1)

        let centers = (0..<count).map { index in
            firstCenter + CGFloat(index) * step
        }

        let hitFrames = centers.enumerated().map { index, center in
            let left: CGFloat =
                index == 0
                ? 0
                : (centers[index - 1] + center) / 2

            let right: CGFloat =
                index == count - 1
                ? controlWidth
                : (center + centers[index + 1]) / 2

            return CGRect(
                x: left,
                y: 0,
                width: max(0, right - left),
                height: controlHeight
            )
        }

        let dividerXs = (0..<(count - 1)).map { index in
            (centers[index] + centers[index + 1]) / 2
        }

        return SegmentLayout(
            centers: centers,
            pillWidths: pillWidths,
            hitFrames: hitFrames,
            dividerXs: dividerXs
        )
    }

    private func pillWidth(for option: Option) -> CGFloat {
        let measuredWidth =
            selectedTitleWidths[optionKey(option)]
            ?? estimatedTitleWidth(title(option, true))

        return max(
            minimumPillWidth,
            ceil(measuredWidth + selectedTextHorizontalPadding * 2)
        )
    }

    private func estimatedTitleWidth(_ text: String) -> CGFloat {
        CGFloat(text.count) * fontSize * 0.58
    }

    private func optionKey(_ option: Option) -> AnyHashable {
        AnyHashable(option.id)
    }

    private var selectedTitleMeasurementLayer: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Text(title(option, true))
                    .font(.system(size: fontSize, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .background {
                        GeometryReader { textProxy in
                            Color.clear.preference(
                                key: TLSelectedSegmentTitleWidthKey.self,
                                value: [optionKey(option): textProxy.size.width]
                            )
                        }
                    }
            }
        }.opacity(0)
            .allowsHitTesting(false)
    }

    private var selectedSegmentGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return shape.fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.16), Color.white.opacity(0.085),
                    Color.white.opacity(0.03), Color.white.opacity(0.045),
                    Color.black.opacity(0.12),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        ).background {
            shape.fill(.ultraThinMaterial).opacity(0.10).environment(
                \.colorScheme,
                .dark
            )
        }.overlay {
            shape.fill(
                LinearGradient(
                    colors: [
                        trackColor.opacity(0.13), Color.clear,
                        trackColor.opacity(0.07),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ).blendMode(.screen)
        }.overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.42), Color.white.opacity(0.20),
                        trackColor.opacity(0.19), Color.white.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
        }.overlay(alignment: .top) {
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12), Color.white.opacity(0.045),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ).mask {
                LinearGradient(
                    colors: [
                        Color.white, Color.white.opacity(0.38), Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.58)
                )
            }.blur(radius: 0.65).mask(shape)
        }.overlay(alignment: .topTrailing) {
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.126), location: 0.0),
                        .init(color: trackColor.opacity(0.12), location: 0.18),
                        .init(color: Color.clear, location: 0.78),
                    ],
                    startPoint: .topTrailing,
                    endPoint: UnitPoint(x: 0.84, y: 0.40)
                )
            ).mask {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.94), Color.white.opacity(0.49),
                        Color.white.opacity(0.14), Color.clear,
                    ],
                    startPoint: .topTrailing,
                    endPoint: UnitPoint(x: 0.68, y: 0.52)
                )
            }.blur(radius: 0.85).mask(shape)
        }.overlay(alignment: .topTrailing) {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.21), trackColor.opacity(0.14),
                        Color.clear,
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.65
            ).blur(radius: 0.38).mask {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96), Color.white.opacity(0.57),
                        Color.white.opacity(0.14), Color.clear,
                    ],
                    startPoint: .topTrailing,
                    endPoint: UnitPoint(x: 0.68, y: 0.78)
                )
            }.mask(shape)
        }.overlay(alignment: .bottomTrailing) {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.clear, trackColor.opacity(0.115),
                        Color.white.opacity(0.062),
                    ],
                    startPoint: .leading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.65
            ).blur(radius: 0.7).mask {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.62), Color.white.opacity(0.245),
                        Color.clear,
                    ],
                    startPoint: .bottomTrailing,
                    endPoint: UnitPoint(x: 0.35, y: 0.64)
                )
            }.mask(shape)
        }.overlay {
            shape.strokeBorder(Color.black.opacity(0.18), lineWidth: 0.45).blur(
                radius: 0.35
            ).offset(y: 1).mask(shape)
        }.shadow(color: trackColor.opacity(0.08), radius: 8, x: 0, y: 2).shadow(
            color: trackColor.opacity(0.08),
            radius: 2,
            x: 0,
            y: 0
        ).shadow(color: Color.black.opacity(0.24), radius: 2.5, x: 0, y: 1.5)
    }
}

import SwiftUI

// MARK: - Metrics

enum TLClipEditingMetrics {
    static let toolbarWidth:        CGFloat = 190
    static let toolbarBodyHeight:   CGFloat = 42
    static let toolbarPointerW:     CGFloat = 9
    static let toolbarPointerH:     CGFloat = 5
    static let menuWidth:           CGFloat = 176
    static let menuRowHeight:       CGFloat = 40
    static let menuEstimatedHeight: CGFloat = 240
    static let iconBoxSize:         CGFloat = 26
    static let iconBoxRadius:       CGFloat = 7
    static let gripVisual:          CGFloat = 11
    static let gripHit:             CGFloat = 32
    static let indicatorSize:       CGFloat = 20

    /// Floating clip-editing panels — above playhead, clips, and grips.
    static let toolbarZIndex: CGFloat = 100
    static let menuZIndex:    CGFloat = 101
}

// MARK: - Press Style

struct TLClipActionPressStyle: ButtonStyle {
    var isDestructive: Bool = false
    var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let interactionColor = isDestructive
            ? Color.red.opacity(configuration.isPressed ? 0.20 : 0.10)
            : Color.black.opacity(configuration.isPressed ? 0.24 : 0.13)

        configuration.label
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed || isHovered ? interactionColor : Color.clear)
            }
            .animation(.spring(response: 0.17, dampingFraction: 0.82),
                       value: configuration.isPressed)
            .animation(.spring(response: 0.17, dampingFraction: 0.82),
                       value: isHovered)
    }
}

private struct TLClipToolbarAction: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10.0, weight: .regular))
                    .foregroundStyle(foreground)
                Text(label)
                    .font(.system(size: 8.2, weight: .medium))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(TLClipActionPressStyle(isDestructive: isDestructive, isHovered: isHovered))
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        if isDestructive, isHovered {
            return Color.red.opacity(0.88)
        }
        return MixrColors.textPrimary.opacity(0.84)
    }
}

// MARK: - Transition Icon Box

struct TLTransitionIconBox: View {
    let transitionType: ClipTransitionType
    var highlighted:    Bool    = false
    var trackColor:     Color   = .white
    var size:           CGFloat = TLClipEditingMetrics.iconBoxSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TLClipEditingMetrics.iconBoxRadius, style: .continuous)
        ZStack {
            shape
                .fill(highlighted
                    ? trackColor.opacity(0.22)
                    : MixrColors.glassNavyStrong.opacity(0.52))
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.06)
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    shape.strokeBorder(
                        highlighted ? trackColor.opacity(0.48) : Color.white.opacity(0.07),
                        lineWidth: 0.5
                    )
                }
                .overlay(alignment: .top) {
                    shape
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.09), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.35)
                        ))
                }

            transitionIcon
                .foregroundStyle(highlighted ? trackColor : MixrColors.textPrimary)
                .font(.system(size: size * 0.44, weight: .medium))
        }
        .frame(width: size, height: size)
        .shadow(color: highlighted ? trackColor.opacity(0.30) : .clear, radius: 6)
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
    let trackColor:    Color
    var isActive:      Bool = false
    var transitionType: ClipTransitionType = .none

    @GestureState private var isPressed: Bool = false

    let onTap: () -> Void

    private let visual = TLClipEditingMetrics.gripVisual
    private let hit    = TLClipEditingMetrics.gripHit

    private var hasTransition: Bool { transitionType != .none }
    private var showHalo: Bool { isActive || hasTransition }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())

            if showHalo {
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
                TLTransitionIconBox(
                    transitionType: transitionType,
                    highlighted: true,
                    trackColor: trackColor,
                    size: TLClipEditingMetrics.indicatorSize
                )
                .scaleEffect(isPressed ? 0.94 : 1.0)
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
    let trackColor:     Color

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
    let trackColor:    Color
    let onSplit:     () -> Void
    let onDuplicate: () -> Void
    let onDelete:    () -> Void

    var body: some View {
        let tbW = TLClipEditingMetrics.toolbarWidth
        let tbH = TLClipEditingMetrics.toolbarBodyHeight
        let pW  = TLClipEditingMetrics.toolbarPointerW
        let pH  = TLClipEditingMetrics.toolbarPointerH
        let radius: CGFloat = 9

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TLClipToolbarAction(icon: "scissors",   label: "Split",     action: onSplit)
                toolbarDivider
                TLClipToolbarAction(icon: "doc.on.doc", label: "Duplicate", action: onDuplicate)
                toolbarDivider
                TLClipToolbarAction(icon: "trash",      label: "Delete",    isDestructive: true, action: onDelete)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(width: tbW, height: tbH)
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                shape
                    .fill(MixrColors.glassNavyStrong.opacity(0.96))
                    .overlay {
                        GlassBackground(level: .strong, cornerRadius: radius)
                            .opacity(0.46)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Circle()
                            .fill(trackColor.opacity(0.08))
                            .frame(width: tbW * 0.66, height: tbW * 0.22)
                            .blur(radius: 16)
                            .offset(x: -tbW * 0.08, y: tbH * 0.22)
                    }
                    .overlay(alignment: .top) {
                        shape.fill(LinearGradient(
                            colors: [
                                Color.white.opacity(0.075),
                                Color.white.opacity(0.024),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(height: tbH * 0.24)
                    }
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(0.085))
                            .frame(height: 0.55)
                            .padding(.horizontal, 14)
                            .padding(.top, 1)
                    }
                    .overlay {
                        shape.strokeBorder(Color.white.opacity(0.085), lineWidth: 0.55)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.70), radius: 24, x: 0, y: 9)
            .shadow(color: trackColor.opacity(0.075), radius: 12, x: 0, y: 3)
            .shadow(color: .black.opacity(0.26), radius: 5,  x: 0, y: 2)

            TLToolbarPointer()
                .fill(MixrColors.glassNavyStrong.opacity(0.96))
                .overlay {
                    TLToolbarPointer()
                        .fill(LinearGradient(
                            colors: [
                                Color.white.opacity(0.045),
                                trackColor.opacity(0.055),
                                MixrColors.backgroundSecondary.opacity(0.10),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                }
                .frame(width: pW, height: pH)
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.13))
            .frame(width: 0.5, height: 22)
            .padding(.vertical, 8)
    }
}

// MARK: - Transition Menu

struct TLTransitionMenu: View {
    let title:      String
    let selected:   ClipTransitionType
    let trackColor: Color
    let onSelect:   (ClipTransitionType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MixrColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            MixrColors.divider.frame(height: 0.5)

            ForEach(ClipTransitionType.allCases) { txType in
                menuRow(txType)
                if txType != ClipTransitionType.allCases.last {
                    MixrColors.divider.opacity(0.5).frame(height: 0.5)
                        .padding(.leading, 48)
                }
            }
        }
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
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.09), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.35)
                        ))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.20), radius: 4,  x: 0, y: 2)
    }

    @ViewBuilder
    private func menuRow(_ txType: ClipTransitionType) -> some View {
        let isSel = txType == selected
        Button {
            onSelect(txType)
        } label: {
            HStack(spacing: 10) {
                TLTransitionIconBox(
                    transitionType: txType,
                    highlighted: isSel,
                    trackColor: trackColor
                )

                Text(txType.rawValue)
                    .font(.system(size: 13, weight: isSel ? .semibold : .regular))
                    .foregroundStyle(MixrColors.textPrimary)

                Spacer()

                if isSel {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(trackColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: TLClipEditingMetrics.menuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TLClipActionPressStyle())
    }
}

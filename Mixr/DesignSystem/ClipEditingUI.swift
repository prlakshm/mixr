import SwiftUI

// MARK: - Metrics

enum TLClipEditingMetrics {
    static let toolbarWidth:        CGFloat = 222
    static let toolbarBodyHeight:   CGFloat = 50
    static let toolbarPointerW:     CGFloat = 7
    static let toolbarPointerH:     CGFloat = 4
    static let menuWidth:           CGFloat = 170
    static let menuRowHeight:       CGFloat = 42
    static var menuEstimatedHeight: CGFloat {
        CGFloat(ClipTransitionType.allCases.count) * menuRowHeight + 4
    }
    static let menuIconBoxSize:     CGFloat = 22.5
    static let menuIconBoxRadius:   CGFloat = 6
    static let iconBoxRadius:       CGFloat = 7
    static let gripVisual:          CGFloat = 11
    static let gripHit:             CGFloat = 32
    static let indicatorSize:       CGFloat = 20

    /// Floating clip-editing panels — above transport and clipped timeline content.
    static let toolbarZIndex: CGFloat = 200
    static let menuZIndex:    CGFloat = 201
}

// MARK: - Press Style

struct TLClipActionPressStyle: ButtonStyle {
    var isDestructive: Bool = false
    var fillsCell:     Bool = false
    var isHovered:     Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressedFill = isDestructive
            ? Color.red.opacity(0.18)
            : Color.black.opacity(0.34)
        let hoverFill = isDestructive
            ? Color.red.opacity(0.10)
            : Color.black.opacity(0.18)

        configuration.label
            .frame(maxWidth: .infinity)
            .background {
                if fillsCell {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(configuration.isPressed ? pressedFill : (isHovered ? hoverFill : Color.clear))
                }
            }
            .offset(y: configuration.isPressed ? 1.25 : 0)
            .opacity(configuration.isPressed && !fillsCell ? 0.88 : 1)
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
            VStack(spacing: 6.4) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(foreground)
                    .offset(
                        y: icon == "scissors"
                        ? 1.5
                            : icon == "trash"
                        ? 1
                                : 0
                    ) // offset to fix some icons being slightly higher than rest
                    .frame(height: 14)

                Text(label)
                    .font(.system(size: 9.8, weight: .medium))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TLClipActionPressStyle(
            isDestructive: isDestructive,
            fillsCell: true,
            isHovered: isHovered
        ))
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        if isDestructive && isHovered {
            return Color.red.opacity(0.88)
        }
        return MixrColors.textPrimary.opacity(isDestructive ? 0.84 : 0.92)
    }
}

// MARK: - Transition Icon Box

struct TLTransitionIconBox: View {
    let transitionType: ClipTransitionType
    var highlighted:    Bool    = false
    var trackColor:     Color   = .white
    var size:           CGFloat = TLClipEditingMetrics.menuIconBoxSize

    var body: some View {
        let radius = size == TLClipEditingMetrics.indicatorSize
            ? TLClipEditingMetrics.iconBoxRadius
            : TLClipEditingMetrics.menuIconBoxRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
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
                                    colors: [Color.white.opacity(0.10), Color.clear],
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
                .shadow(color: .black.opacity(0.55), radius: 4 * gripScale, x: 0, y: 2 * gripScale)
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
        let radius: CGFloat = 11

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TLClipToolbarAction(icon: "scissors",   label: "Split",     action: onSplit)
                TLClipToolbarAction(icon: "doc.on.doc", label: "Duplicate", action: onDuplicate)
                TLClipToolbarAction(icon: "trash",      label: "Delete",    isDestructive: true, action: onDelete)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)      // decrease top padding
            .padding(.bottom, 10)   // more spacing bottom
            .frame(width: tbW, height: tbH)
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
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
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.03), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.35)
                            ))
                    }
                    .overlay {
                        shape
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.20), radius: 4,  x: 0, y: 2)

            TLToolbarPointer()
                .fill(Color(hex: "050810").opacity(0.68))
                .overlay {
                    TLToolbarPointer()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.045), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .frame(width: pW, height: pH)
        }
    }
}

// MARK: - Transition Menu

struct TLTransitionMenu: View {
    let selected:   ClipTransitionType
    let trackColor: Color
    let onSelect:   (ClipTransitionType) -> Void

    var body: some View {
        menuRows
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
                            colors: [Color.white.opacity(0.045), Color.clear],
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
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func menuRow(_ txType: ClipTransitionType) -> some View {
        let isSel = txType == selected
        Button {
            onSelect(txType)
        } label: {
            HStack(spacing: 9) {
                TLTransitionIconBox(
                    transitionType: txType,
                    highlighted: isSel,
                    trackColor: trackColor
                )

                Text(txType.rawValue)
                    .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                    .foregroundStyle(isSel ? trackColor : MixrColors.textPrimary)

                Spacer()

                if isSel {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(trackColor)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: TLClipEditingMetrics.menuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TLClipActionPressStyle())
    }
}

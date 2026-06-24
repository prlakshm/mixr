import SwiftUI

// MARK: - Metrics

enum TLClipEditingMetrics {
    static let toolbarWidth:        CGFloat = 162
    static let toolbarBodyHeight:   CGFloat = 46
    static let toolbarPointerW:     CGFloat = 12
    static let toolbarPointerH:     CGFloat = 7
    static let menuWidth:           CGFloat = 176
    static let menuRowHeight:       CGFloat = 40
    static let menuEstimatedHeight: CGFloat = 240
    static let iconBoxSize:         CGFloat = 26
    static let iconBoxRadius:       CGFloat = 7
    static let gripVisual:          CGFloat = 11
    static let gripHit:             CGFloat = 32
    static let indicatorSize:       CGFloat = 20
}

// MARK: - Press Style

struct TLClipActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .background {
                if configuration.isPressed {
                    Color.black.opacity(0.20)
                }
            }
            .animation(.spring(response: 0.18, dampingFraction: 0.85),
                       value: configuration.isPressed)
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
    var hasTransition: Bool = false

    @GestureState private var isPressed: Bool = false

    let onTap: () -> Void

    private let visual = TLClipEditingMetrics.gripVisual
    private let hit    = TLClipEditingMetrics.gripHit

    private var showHalo: Bool { isActive || hasTransition }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())

            if showHalo {
                Circle()
                    .fill(trackColor.opacity(0.20))
                    .frame(width: visual + 11, height: visual + 11)
                    .blur(radius: 5)

                Circle()
                    .strokeBorder(trackColor.opacity(0.55), lineWidth: 2.0)
                    .frame(width: visual + 6, height: visual + 6)
            }

            Circle()
                .fill(Color.white.opacity(isPressed ? 0.12 : 0.06))
                .frame(width: visual + 4, height: visual + 4)
                .blur(radius: 3)

            Circle()
                .strokeBorder(
                    Color.white.opacity(isPressed ? 1.0 : 0.80),
                    lineWidth: 1.5
                )
                .frame(width: visual, height: visual)
                .scaleEffect(isPressed ? 0.93 : 1.0)

            Circle()
                .fill(Color.black)
                .frame(width: visual * 0.52, height: visual * 0.52)
        }
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isActive)
        .animation(.easeOut(duration: 0.12), value: hasTransition)
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
    let onSplit:     () -> Void
    let onDuplicate: () -> Void
    let onDelete:    () -> Void

    var body: some View {
        let tbW = TLClipEditingMetrics.toolbarWidth
        let tbH = TLClipEditingMetrics.toolbarBodyHeight
        let pW  = TLClipEditingMetrics.toolbarPointerW
        let pH  = TLClipEditingMetrics.toolbarPointerH

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                toolbarAction(icon: "scissors",   label: "Split",     action: onSplit)
                Divider().frame(width: 0.5, height: 28).background(MixrColors.divider)
                toolbarAction(icon: "doc.on.doc", label: "Duplicate", action: onDuplicate)
                Divider().frame(width: 0.5, height: 28).background(MixrColors.divider)
                toolbarAction(icon: "trash",      label: "Delete",    action: onDelete)
            }
            .frame(width: tbW, height: tbH)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: "050810").opacity(0.65))
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.10)
                            .environment(\.colorScheme, .dark)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.09), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.4)
                            ))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 6)
            .shadow(color: .black.opacity(0.20), radius: 4,  x: 0, y: 2)

            TLToolbarPointer()
                .fill(Color(hex: "050810").opacity(0.65))
                .frame(width: pW, height: pH)
        }
    }

    @ViewBuilder
    private func toolbarAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MixrColors.textPrimary)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MixrColors.textPrimary.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TLClipActionPressStyle())
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

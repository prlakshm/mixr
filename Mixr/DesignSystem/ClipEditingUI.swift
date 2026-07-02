import SwiftUI

// MARK: - Metrics

enum TLClipEditingMetrics {
    static let toolbarWidth:        CGFloat = 222
    static let toolbarBodyHeight:   CGFloat = 50
    static let toolbarPointerW:     CGFloat = 7
    static let toolbarPointerH:     CGFloat = 4
    static let menuWidth:           CGFloat = 170
    static let menuSettingsWidth:   CGFloat = 336
    static let menuSettingsSegmentedWidth: CGFloat = 224
    static let menuRowHeight:       CGFloat = 42
    static let menuSlideDuration:   Double  = 0.30
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
        .buttonStyle(TLClipActionPressStyle(isDestructive: isDestructive))
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
    let selected:   ClipTransition
    let trackColor: Color
    let onSelect:   (ClipTransitionType) -> Void
    var onUpdate:   (ClipTransition) -> Void = { _ in }

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
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            case .settings(let txType):
                settingsPage(for: txType)
                    .frame(width: TLClipEditingMetrics.menuSettingsWidth)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
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
            TLClipEditingMetrics.menuRowHeight * 3 + 4
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
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func menuRow(_ txType: ClipTransitionType) -> some View {
        let isSel = txType == selected.type
        Button {
            if txType == .none {
                onSelect(txType)
            } else {
                var tx = selected.type == txType
                    ? selected
                    : ClipTransition(type: txType, duration: DurationOption.one.rawValue, curve: CurveOption.linear.rawValue)
                tx.type = txType
                onUpdate(tx)
                withAnimation(.easeInOut(duration: TLClipEditingMetrics.menuSlideDuration)) {
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
                    .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                    .foregroundStyle(isSel ? trackColor : MixrColors.textPrimary)

                Spacer()

                if isSel {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(trackColor)
                } else if txType != .none {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MixrColors.textSecondary)
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
                control: durationControl
            )
            .overlay(alignment: .bottom) {
                menuDivider
            }
            settingsRow(
                title: "Curve",
                control: curveControl
            )
        }
        .padding(.vertical, 2)
    }

    private func settingsHeader(_ txType: ClipTransitionType) -> some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: TLClipEditingMetrics.menuSlideDuration)) {
                    page = .list
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MixrColors.textPrimary)
                    .frame(
                        width: TLClipEditingMetrics.menuIconBoxSize,
                        height: TLClipEditingMetrics.menuIconBoxSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(txType.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MixrColors.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: TLClipEditingMetrics.menuRowHeight)
    }

    private func settingsRow<Control: View>(
        title: String,
        control: Control
    ) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(MixrColors.textPrimary)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 9)

            control
                .frame(width: TLClipEditingMetrics.menuSettingsSegmentedWidth)
        }
        .padding(.horizontal, 20)
        .frame(height: TLClipEditingMetrics.menuRowHeight)
    }

    private var durationControl: some View {
        segmentedControl(
            options: DurationOption.allCases,
            selected: selectedDurationOption,
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
            title: { option, _ in option.title }
        ) { option in
            var tx = selected
            tx.curve = option.rawValue
            onUpdate(tx)
        }
    }

    private var selectedDurationOption: DurationOption {
        DurationOption.allCases.min {
            abs($0.rawValue - selected.duration) < abs($1.rawValue - selected.duration)
        } ?? .one
    }

    private var selectedCurveOption: CurveOption {
        CurveOption(rawValue: selected.curve) ?? .linear
    }

    private func segmentedControl<Option: Identifiable & Equatable>(
        options: [Option],
        selected: Option,
        title: @escaping (Option, Bool) -> String,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                let isSelected = option == selected
                Button {
                    onSelect(option)
                } label: {
                    Text(title(option, isSelected))
                        .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? MixrColors.textPrimary : MixrColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.25),
                                                Color.white.opacity(0.08),
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)

                if index != options.count - 1 {
                    Rectangle()
                        .fill(MixrColors.divider.opacity(0.55))
                        .frame(width: 0.35, height: 20)
                }
            }
        }
        .padding(2)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.08)
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.5)
                        ))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                }
        }
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(MixrColors.divider.opacity(0.5))
            .frame(height: 0.25)
            .padding(.leading, 20)
    }
}

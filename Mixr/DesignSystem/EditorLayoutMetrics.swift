import CoreGraphics

enum EditorLayoutMode: Equatable {
    case compact
    case regular
}

enum EditorEffectsState: Equatable {
    case collapsed
    case expanded

    init(isCollapsed: Bool) {
        self = isCollapsed ? .collapsed : .expanded
    }
}

enum EditorEffectsInteraction {
    static let dragThreshold: CGFloat = 24

    static func toggled(_ isCollapsed: Bool) -> Bool {
        !isCollapsed
    }

    static func collapsedState(
        afterDrag translation: CGSize,
        current isCollapsed: Bool
    ) -> Bool {
        let vertical = translation.height
        guard abs(vertical) > abs(translation.width) else {
            return isCollapsed
        }
        if vertical > dragThreshold {
            return true
        }
        if vertical < -dragThreshold {
            return false
        }
        return isCollapsed
    }
}

enum EditorPresentationStyle: Equatable {
    case popover
    case sheet
}

enum EditorPresentationRules {
    static let regularWidthThreshold: CGFloat = 600

    static func style(availableWidth: CGFloat) -> EditorPresentationStyle {
        availableWidth >= regularWidthThreshold ? .popover : .sheet
    }
}

/// Content-driven dimensions for the three-column editor. Side panels have
/// compact and ideal widths; every point beyond those ideals belongs to the
/// timeline.
struct EditorLayoutMetrics: Equatable {
    static let minimumTracksWidth: CGFloat = 148
    static let idealTracksWidth: CGFloat = 208
    static let maximumTracksWidth: CGFloat = 224

    static let minimumControlsWidth: CGFloat = 104
    static let idealControlsWidth: CGFloat = 130
    static let maximumControlsWidth: CGFloat = 144

    static let regularTransportMinimumWidth: CGFloat = 820
    static let compactWidthFloor: CGFloat = 393

    static let regularTransportHeight: CGFloat = 50
    static let compactTransportHeight: CGFloat = 94

    static let regularImportFooterHeight: CGFloat = 46
    static let compactImportFooterHeight: CGFloat = 82

    static let expandedEffectsHeight: CGFloat = 118
    static let collapsedEffectsHeight: CGFloat = 42

    let containerSize: CGSize
    let effectsState: EditorEffectsState
    let mode: EditorLayoutMode
    let tracksWidth: CGFloat
    let controlsWidth: CGFloat
    let timelineWidth: CGFloat
    let transportHeight: CGFloat
    let importFooterHeight: CGFloat
    let effectsHeight: CGFloat
    let timelineHeight: CGFloat

    init(containerSize: CGSize, effectsState: EditorEffectsState) {
        let width = max(0, containerSize.width)
        let height = max(0, containerSize.height)
        let mode: EditorLayoutMode =
            width >= Self.regularTransportMinimumWidth ? .regular : .compact

        let tracksWidth: CGFloat
        let controlsWidth: CGFloat
        if mode == .regular {
            tracksWidth = Self.idealTracksWidth
            controlsWidth = Self.idealControlsWidth
        } else {
            let interpolationRange =
                Self.regularTransportMinimumWidth - Self.compactWidthFloor
            let progress = min(
                1,
                max(0, (width - Self.compactWidthFloor) / interpolationRange)
            )
            tracksWidth = Self.minimumTracksWidth
                + (Self.idealTracksWidth - Self.minimumTracksWidth) * progress
            controlsWidth = Self.minimumControlsWidth
                + (Self.idealControlsWidth - Self.minimumControlsWidth) * progress
        }

        let transportHeight = mode == .regular
            ? Self.regularTransportHeight
            : Self.compactTransportHeight
        let importFooterHeight = mode == .regular
            ? Self.regularImportFooterHeight
            : Self.compactImportFooterHeight
        let effectsHeight = effectsState == .collapsed
            ? Self.collapsedEffectsHeight
            : Self.expandedEffectsHeight

        self.containerSize = CGSize(width: width, height: height)
        self.effectsState = effectsState
        self.mode = mode
        self.tracksWidth = tracksWidth
        self.controlsWidth = controlsWidth
        self.timelineWidth = max(1, width - tracksWidth - controlsWidth)
        self.transportHeight = transportHeight
        self.importFooterHeight = importFooterHeight
        self.effectsHeight = effectsHeight
        self.timelineHeight = max(1, height - transportHeight - effectsHeight)
    }
}

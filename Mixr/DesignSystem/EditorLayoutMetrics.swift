import CoreGraphics

enum EditorLayoutMode: Equatable {
    case compact
    case regular
}

/// Physical chrome the editor has to stay clear of: the Dynamic Island in
/// landscape, the home indicator, the iPad status bar / multitasking control,
/// and the Mac Catalyst title bar.
///
/// Read from the *window* rather than the SwiftUI safe area — the editor keeps
/// its background full-bleed, which zeroes the insets a `GeometryProxy`
/// reports, so the values have to come from UIKit (see `EditorChrome`).
struct EditorSafeArea: Equatable {
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0

    static let zero = EditorSafeArea()

    /// Floor for the top band whenever the system reports chrome up there, so
    /// the clock, the iPad multitasking control, and the Mac window title all
    /// clear the toolbar instead of sitting on it. A screen that reports no top
    /// chrome (phone landscape) keeps its edge-to-edge toolbar.
    static let minimumTopChrome: CGFloat = 28

    var horizontal: CGFloat { leading + trailing }
    var vertical: CGFloat { top + bottom }

    /// Grows a reported top inset to the minimum chrome band.
    var resolved: EditorSafeArea {
        var value = self
        if value.top > 0 {
            value.top = max(value.top, Self.minimumTopChrome)
        }
        return value
    }

    /// Editor content size inside a container of `size`.
    func contentSize(in size: CGSize) -> CGSize {
        CGSize(
            width: max(1, size.width - horizontal),
            height: max(1, size.height - vertical)
        )
    }
}

/// How much room the one-row transport has to spend. `tight` is a phone in
/// landscape once the Dynamic Island bands are removed; `roomy` is a small
/// desktop window or a tablet in portrait; `large` is a full tablet or a big
/// desktop window.
enum EditorLayoutDensity: Equatable {
    case tight
    case roomy
    case large

    /// Toolbar gaps shrink first when width is scarce — the transport cluster
    /// and Export must never be pushed off the bar.
    var toolbarEdgePadding: CGFloat {
        switch self {
        case .tight: 10
        case .roomy: 14
        case .large: 18
        }
    }

    var toolbarLogoGap: CGFloat {
        switch self {
        case .tight: 12
        case .roomy: 22
        case .large: 26
        }
    }

    var toolbarTitleGap: CGFloat {
        switch self {
        case .tight: 8
        case .roomy: 16
        case .large: 18
        }
    }

    var transportSpacing: CGFloat {
        switch self {
        case .tight: 8
        case .roomy: 12
        case .large: 14
        }
    }

    var readoutKeyWidth: CGFloat {
        switch self {
        case .tight: 46
        case .roomy: 56
        case .large: 60
        }
    }
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

/// Fixed widths of the one-row transport's three groups. Kept next to the
/// layout math so the collision-free placement below can be tested without
/// rendering, and read by the toolbar itself so the two never drift apart.
enum EditorTransportMetrics {
    /// Waveform mark + "Mixr" wordmark.
    static let logoWidth: CGFloat = 66
    /// Project title column + chevron (see TLProjectTitleMetrics.controlWidth).
    static let projectTitleWidth: CGFloat = 96.25
    /// Undo + redo hit areas and the gap between them.
    static let historyWidth: CGFloat = 72
    static let transportButtonWidth: CGFloat = 44
    /// "0:00 / 2:09" at the monospaced readout size.
    static let timeReadoutWidth: CGFloat = 78
    static let bpmWidth: CGFloat = 30
    static let readoutGap: CGFloat = 10
    static let exportWidth: CGFloat = 96
    /// Clearance the centre cluster keeps from the side groups.
    static let minimumClusterGap: CGFloat = 10
    /// The bar keeps the same share of the editor's height on every screen, so
    /// a tablet's toolbar reads as substantial as a desktop window's instead of
    /// shrinking to a phone-sized strip on a much taller display.
    static let toolbarHeightBasis: CGFloat = 590
    static let toolbarScaleCeiling: CGFloat = 1.7

    /// Toolbar scale wanted on a screen of this content height.
    static func desiredScale(contentHeight: CGFloat) -> CGFloat {
        min(toolbarScaleCeiling, max(1, contentHeight / toolbarHeightBasis))
    }

    static func homeGroupWidth(
        _ density: EditorLayoutDensity,
        scale: CGFloat = 1
    ) -> CGFloat {
        density.toolbarEdgePadding
            + (logoWidth + projectTitleWidth + historyWidth) * scale
            + density.toolbarLogoGap
            + density.toolbarTitleGap
    }

    static func exportGroupWidth(
        _ density: EditorLayoutDensity,
        scale: CGFloat = 1
    ) -> CGFloat {
        exportWidth * scale + density.toolbarEdgePadding
    }

    /// Cluster width splits into parts that scale with the toolbar and gaps
    /// that come from density, so the fitting scale can be solved directly.
    static func clusterScalableWidth(_ density: EditorLayoutDensity) -> CGFloat {
        transportButtonWidth * 3
            + timeReadoutWidth
            + bpmWidth
            + density.readoutKeyWidth
    }

    static func clusterFixedWidth(_ density: EditorLayoutDensity) -> CGFloat {
        density.transportSpacing * 4 + readoutGap
    }

    static func clusterWidth(
        _ density: EditorLayoutDensity,
        scale: CGFloat = 1
    ) -> CGFloat {
        clusterFixedWidth(density) + clusterScalableWidth(density) * scale
    }

    /// Distance from the cluster's leading edge to the play button's centre.
    static func playCentreInCluster(
        _ density: EditorLayoutDensity,
        scale: CGFloat = 1
    ) -> CGFloat {
        transportButtonWidth * scale
            + density.transportSpacing
            + transportButtonWidth * scale / 2
    }

    /// Narrowest width that still fits all three groups with clearance.
    static func minimumOneRowWidth(
        _ density: EditorLayoutDensity,
        scale: CGFloat = 1
    ) -> CGFloat {
        homeGroupWidth(density, scale: scale)
            + clusterWidth(density, scale: scale)
            + exportGroupWidth(density, scale: scale)
            + minimumClusterGap * 2
    }
}

/// Where the centre transport cluster sits on the one-row toolbar. The play
/// button wants the middle of the bar; when width is scarce it gives way so the
/// cluster never lands on the project title, undo/redo, or Export.
struct EditorTransportLayout: Equatable {
    /// Applied toolbar scale — the desired scale, reduced as far as needed for
    /// the three groups to fit with clearance. Never below the phone baseline.
    let scale: CGFloat
    let clusterLeading: CGFloat
    let clusterWidth: CGFloat
    let playCentreX: CGFloat
    /// Offset from a centred cluster — what the toolbar applies as `.offset`.
    let centreOffset: CGFloat
    /// True when the bar is too narrow to keep full clearance on both sides.
    let isCramped: Bool

    init(
        contentWidth: CGFloat,
        density: EditorLayoutDensity,
        desiredScale: CGFloat = 1
    ) {
        // Solve for the largest toolbar scale that still leaves clearance.
        let gapAllowance = EditorTransportMetrics.minimumClusterGap * 2
        let fixed = EditorTransportMetrics.clusterFixedWidth(density)
            + density.toolbarEdgePadding * 2
            + density.toolbarLogoGap
            + density.toolbarTitleGap
            + gapAllowance
        let scalable = EditorTransportMetrics.clusterScalableWidth(density)
            + EditorTransportMetrics.logoWidth
            + EditorTransportMetrics.projectTitleWidth
            + EditorTransportMetrics.historyWidth
            + EditorTransportMetrics.exportWidth
        let fittingScale = scalable > 0
            ? (contentWidth - fixed) / scalable
            : desiredScale

        // Fitting alone isn't enough: the bar must be able to seat the play
        // button on the centre line with clearance on both sides. Solve each
        // side for the largest scale that still allows it, and let a slightly
        // smaller toolbar win over an off-centre play button.
        let half = contentWidth / 2
        let sideGroups = EditorTransportMetrics.logoWidth
            + EditorTransportMetrics.projectTitleWidth
            + EditorTransportMetrics.historyWidth
        let playHalfSpan = EditorTransportMetrics.transportButtonWidth * 1.5
        let leadingHeadroom = half
            - density.transportSpacing
            - density.toolbarEdgePadding
            - density.toolbarLogoGap
            - density.toolbarTitleGap
            - EditorTransportMetrics.minimumClusterGap
        let trailingHeadroom = half
            + density.transportSpacing
            - EditorTransportMetrics.clusterFixedWidth(density)
            - density.toolbarEdgePadding
            - EditorTransportMetrics.minimumClusterGap
        let leadingCentringScale = leadingHeadroom / (playHalfSpan + sideGroups)
        let trailingCentringScale = trailingHeadroom
            / (EditorTransportMetrics.clusterScalableWidth(density)
                + EditorTransportMetrics.exportWidth
                - playHalfSpan)
        let centringScale = min(leadingCentringScale, trailingCentringScale)

        let scale = max(1, min(min(desiredScale, fittingScale), centringScale))

        let width = EditorTransportMetrics.clusterWidth(density, scale: scale)
        let playCentre = EditorTransportMetrics.playCentreInCluster(
            density,
            scale: scale
        )
        let home = EditorTransportMetrics.homeGroupWidth(density, scale: scale)
        let export = EditorTransportMetrics.exportGroupWidth(density, scale: scale)
        let gap = EditorTransportMetrics.minimumClusterGap

        // Ideal: the play button owns the centre of the bar.
        let ideal = contentWidth / 2 - playCentre
        let lowerBound = home + gap
        let upperBound = contentWidth - export - gap - width

        let leading: CGFloat
        let cramped: Bool
        if lowerBound <= upperBound {
            leading = min(max(ideal, lowerBound), upperBound)
            cramped = false
        } else {
            // Not enough room for both clearances — split the shortfall evenly
            // so neither side collides harder than the other.
            leading = (lowerBound + upperBound) / 2
            cramped = true
        }

        self.scale = scale
        self.clusterWidth = width
        self.clusterLeading = leading
        self.playCentreX = leading + playCentre
        self.centreOffset = leading - (contentWidth - width) / 2
        self.isCramped = cramped
    }
}

/// Content-driven dimensions for the three-column editor. Side panels have
/// compact and ideal widths; every point beyond those ideals belongs to the
/// timeline.
struct EditorLayoutMetrics: Equatable {
    static let minimumTracksWidth: CGFloat = 148
    static let idealTracksWidth: CGFloat = 208
    static let maximumTracksWidth: CGFloat = 360

    static let minimumControlsWidth: CGFloat = 104
    static let idealControlsWidth: CGFloat = 130
    static let maximumControlsWidth: CGFloat = 220

    /// Side panels hold the share of the editor the desktop window uses, so a
    /// wider screen widens the panels instead of pouring everything into the
    /// timeline and leaving phone-width columns on a tablet.
    static let tracksWidthShare: CGFloat = 0.219
    static let controlsWidthShare: CGFloat = 0.141

    /// A phone in landscape keeps the one-row transport after its Dynamic
    /// Island bands are removed — that is the narrowest bar the groups fit on
    /// (see `EditorTransportMetrics.minimumOneRowWidth`).
    static let regularTransportMinimumWidth: CGFloat = 720
    static let compactWidthFloor: CGFloat = 393
    /// Width at which the compact side columns reach their ideals. Held above
    /// the one-row threshold so lowering that threshold does not make the
    /// columns grow faster and squeeze the timeline in narrow windows.
    static let compactColumnGrowthCeiling: CGFloat = 820

    static let regularTransportHeight: CGFloat = 50
    static let compactTransportHeight: CGFloat = 94

    static let regularImportFooterHeight: CGFloat = 46
    static let compactImportFooterHeight: CGFloat = 82

    static let expandedEffectsHeight: CGFloat = 118
    static let collapsedEffectsHeight: CGFloat = 42

    /// Phone-baseline effect card — scaled up by `contentScale`.
    static let baseEffectCardWidth: CGFloat = 152
    static let baseEffectCardHeight: CGFloat = 66
    static let baseEffectCardGap: CGFloat = 8
    /// Cards span the panel at the phone's rhythm — five and a half across, so
    /// the last card is always half-cut and the row reads as scrollable.
    static let effectCardsAcrossPanel: CGFloat = 5.5
    /// Gutter either side of the card row (see TLEffectsPanel.horizontalInset).
    static let effectRowInset: CGFloat = 16

    /// Panel width one baseline card's worth of row occupies, inset and gaps
    /// included — dividing by this gives the scale that lands the cut cleanly.
    static var effectRowSpanPerCard: CGFloat {
        effectRowInset
            + effectCardsAcrossPanel * (baseEffectCardWidth + baseEffectCardGap)
    }

    /// Track rows share out the timeline so a full project fills the editor
    /// instead of stranding a phone-sized stack at the top of a tablet.
    static let baseTrackRowHeight: CGFloat = 46
    static let maximumTrackRowHeight: CGFloat = 132
    /// Share of the timeline a full track stack should occupy.
    static let trackStackHeightShare: CGFloat = 0.86
    /// Rows stop growing below this count, so one or two tracks don't become
    /// enormous on a tall screen.
    static let trackRowGrowthFloorCount: CGFloat = 5

    /// Row height that gives `trackCount` rows the target share of the
    /// timeline, held between the phone baseline and a sane maximum.
    static func trackRowHeight(
        timelineHeight: CGFloat,
        rulerHeight: CGFloat,
        trackCount: Int
    ) -> CGFloat {
        let lanes = max(CGFloat(trackCount), trackRowGrowthFloorCount)
        let available = max(0, timelineHeight - rulerHeight)
        let ideal = available * trackStackHeightShare / lanes
        return min(maximumTrackRowHeight, max(baseTrackRowHeight, ideal.rounded()))
    }

    static let roomyDensityWidth: CGFloat = 900
    static let largeDensityWidth: CGFloat = 1150

    /// Phone-landscape geometry is the 1.0 baseline; tablets and desktop
    /// windows scale the effects panel and side columns up from there.
    static let contentScaleBasis: CGFloat = 560
    static let contentScaleCeiling: CGFloat = 1.45
    /// Height weight — a short desktop window should not read as a tablet.
    static let contentScaleHeightWeight: CGFloat = 1.2
    /// The effects panel never eats more than this share of the editor.
    static let effectsHeightShareCeiling: CGFloat = 0.32

    let containerSize: CGSize
    let effectsState: EditorEffectsState
    let mode: EditorLayoutMode
    let density: EditorLayoutDensity
    /// Multiplier applied to the effects panel and side columns on roomier
    /// screens. 1.0 on a phone.
    let contentScale: CGFloat
    let tracksWidth: CGFloat
    let controlsWidth: CGFloat
    let timelineWidth: CGFloat
    let transportHeight: CGFloat
    let importFooterHeight: CGFloat
    let effectsHeight: CGFloat
    let effectCardWidth: CGFloat
    let effectCardHeight: CGFloat
    let timelineHeight: CGFloat
    let transport: EditorTransportLayout

    /// Phone landscape keeps its edge-to-edge toolbar; anything tall enough to
    /// show system chrome leaves the status bar visible, so the clock and the
    /// iPad multitasking control get their own band above the editor.
    static let statusBarHiddenHeightCeiling: CGFloat = 500

    /// An unmeasured container (first render) keeps the status bar, so a tablet
    /// or desktop window never flashes an edge-to-edge bar on launch.
    static func prefersStatusBarHidden(containerHeight: CGFloat) -> Bool {
        containerHeight > 0 && containerHeight < statusBarHiddenHeightCeiling
    }

    var prefersStatusBarHidden: Bool {
        Self.prefersStatusBarHidden(containerHeight: containerSize.height)
    }

    init(containerSize: CGSize, effectsState: EditorEffectsState) {
        let width = max(0, containerSize.width)
        let height = max(0, containerSize.height)
        let mode: EditorLayoutMode =
            width >= Self.regularTransportMinimumWidth ? .regular : .compact
        let density: EditorLayoutDensity =
            if mode == .compact || width < Self.roomyDensityWidth {
                .tight
            } else if width < Self.largeDensityWidth {
                .roomy
            } else {
                .large
            }

        // A tablet is roomy in both axes; a short, wide desktop window is not.
        let scaleBasis = min(width, height * Self.contentScaleHeightWeight)
        let contentScale = min(
            Self.contentScaleCeiling,
            max(1, scaleBasis / Self.contentScaleBasis)
        )

        let tracksWidth: CGFloat
        let controlsWidth: CGFloat
        if mode == .regular {
            // Never narrower than the phone's ideals, never wider than the caps.
            tracksWidth = min(
                Self.maximumTracksWidth,
                max(Self.idealTracksWidth, width * Self.tracksWidthShare)
            )
            controlsWidth = min(
                Self.maximumControlsWidth,
                max(Self.idealControlsWidth, width * Self.controlsWidthShare)
            )
        } else {
            let interpolationRange =
                Self.compactColumnGrowthCeiling - Self.compactWidthFloor
            let progress = min(
                1,
                max(0, (width - Self.compactWidthFloor) / interpolationRange)
            )
            tracksWidth = Self.minimumTracksWidth
                + (Self.idealTracksWidth - Self.minimumTracksWidth) * progress
            controlsWidth = Self.minimumControlsWidth
                + (Self.idealControlsWidth - Self.minimumControlsWidth) * progress
        }

        let transport = EditorTransportLayout(
            contentWidth: width,
            density: density,
            desiredScale: mode == .regular
                ? EditorTransportMetrics.desiredScale(contentHeight: height)
                : 1
        )
        let transportHeight = mode == .regular
            ? (Self.regularTransportHeight * transport.scale).rounded()
            : Self.compactTransportHeight
        let importFooterHeight = mode == .regular
            ? Self.regularImportFooterHeight
            : Self.compactImportFooterHeight
        // Cards span the panel at the phone's rhythm, so a wider screen shows
        // the same "five and a bit" row rather than the same small cards on a
        // longer runway. Growth is then capped so the panel can never crowd out
        // the timeline on a short window.
        let cardsFitScale = width / Self.effectRowSpanPerCard
        let cardScale = max(
            1,
            min(
                cardsFitScale,
                height * Self.effectsHeightShareCeiling / Self.expandedEffectsHeight
            )
        )
        let effectCardWidth = (EditorLayoutMetrics.baseEffectCardWidth * cardScale)
            .rounded()
        let effectCardHeight = (EditorLayoutMetrics.baseEffectCardHeight * cardScale)
            .rounded()
        let expandedEffectsHeight = (Self.expandedEffectsHeight * cardScale).rounded()
        let collapsedEffectsHeight =
            (Self.collapsedEffectsHeight + (cardScale - 1) * 18).rounded()
        let effectsHeight = effectsState == .collapsed
            ? collapsedEffectsHeight
            : expandedEffectsHeight

        self.containerSize = CGSize(width: width, height: height)
        self.effectsState = effectsState
        self.mode = mode
        self.density = density
        self.contentScale = cardScale
        self.tracksWidth = tracksWidth
        self.controlsWidth = controlsWidth
        self.timelineWidth = max(1, width - tracksWidth - controlsWidth)
        self.transportHeight = transportHeight
        self.importFooterHeight = importFooterHeight
        self.effectsHeight = effectsHeight
        self.effectCardWidth = effectCardWidth
        self.effectCardHeight = effectCardHeight
        self.timelineHeight = max(1, height - transportHeight - effectsHeight)
        self.transport = transport
    }
}

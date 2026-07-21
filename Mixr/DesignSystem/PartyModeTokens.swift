import SwiftUI

enum PartyModeTokens {
    static let electricBlue = Color(hex: "72A7FF")
    static let coolCyan = Color(hex: "67C8FF")
    static let violet = Color(hex: "825EFF")
    static let lavender = Color(hex: "B26EFF")
    static let magenta = Color(hex: "E068FF")
    static let glintWhite = Color(hex: "FFF8FF")

    // The visible line remains precise. Depth comes from the three independent
    // bloom layers rather than inflating the core stroke.
    static let coreStrokeWidth: CGFloat = 1.02
    static let compactStrokeWidth: CGFloat = 0.88
    static let nearGlowRadius: CGFloat = 3.6
    static let mediumGlowRadius: CGFloat = 8.8
    static let ambientGlowRadius: CGFloat = 18
    // Blurred strokes carry more light energy than the visible 1 pt core. This
    // makes the bloom survive full-app compositing without thickening the rim.
    static let nearGlowStrokeScale: CGFloat = 2.35
    static let mediumGlowStrokeScale: CGFloat = 3.4
    static let ambientGlowStrokeScale: CGFloat = 4.8
    static let innerHighlightWidth: CGFloat = 0.64

    // One finite activation clock. Individual surfaces derive their subtle
    // offsets and shorter durations from this shared time source.
    static let activationArmingDelay: TimeInterval = 0.016
    static let activationSequenceDuration: TimeInterval = 1.64
    static let traceDurationPanel: TimeInterval = 0.96
    static let traceDurationButton: TimeInterval = 0.62
    static let reconnectFlareDuration: TimeInterval = 0.10
    static let afterglintDuration: TimeInterval = 0.50
    static let traceHeadCoreWidth: CGFloat = 1.9
    static let traceHeadGlowRadius: CGFloat = 8
    static let traceTrailLength: CGFloat = 0.095
    static let afterglintInitialTrail: CGFloat = 0.12
    static let afterglintFinalTrail: CGFloat = 0.024

    static let playOuterRimInset: CGFloat = 0.08
    static let playInnerRingInset: CGFloat = 2.7
    static let playNearAuraRadius: CGFloat = 9
    static let playAmbientAuraRadius: CGFloat = 16

    static let activationFadeDuration: TimeInterval = 0.18
    static let exitFadeDuration: TimeInterval = 0.24
    static let reduceMotionFadeDuration: TimeInterval = 0.20

    static func delay(for offset: PartyModeGlintOffset) -> TimeInterval {
        switch offset {
        case .none: 0
        case .near: 0.04
        case .far: 0.075
        }
    }
}

enum PartyModeGlintOffset: Sendable {
    case none
    case near
    case far
}

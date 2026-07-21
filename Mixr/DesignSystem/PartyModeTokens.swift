import SwiftUI

enum PartyModeTokens {
    static let electricBlue = Color(hex: "72A7FF")
    static let coolCyan = Color(hex: "67C8FF")
    static let violet = Color(hex: "825EFF")
    static let lavender = Color(hex: "B26EFF")
    static let magenta = Color(hex: "E068FF")
    static let glintWhite = Color(hex: "FFF8FF")

    static let primaryStrokeWidth: CGFloat = 0.96
    static let compactStrokeWidth: CGFloat = 0.82
    static let nearGlowRadius: CGFloat = 4.8
    static let ambientGlowRadius: CGFloat = 10.5
    static let glintArmingDelay: TimeInterval = 0.016
    static let glintDuration: TimeInterval = 1.10
    static let activationFadeDuration: TimeInterval = 0.20
    static let exitFadeDuration: TimeInterval = 0.24
    static let reduceMotionFadeDuration: TimeInterval = 0.20

    static func delay(for offset: PartyModeGlintOffset) -> TimeInterval {
        switch offset {
        case .none: 0
        case .near: 0.04
        case .far: 0.07
        }
    }
}

enum PartyModeGlintOffset: Sendable {
    case none
    case near
    case far
}

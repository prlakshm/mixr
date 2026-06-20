import SwiftUI

enum MixrTextStyle {
    case displayLogo
    case sectionTitle
    case songTitle
    case body
    case metadata
    case button
    case caption
    case timecode

    var size: CGFloat {
        switch self {
        case .displayLogo: 24
        case .sectionTitle: 15
        case .songTitle: 13
        case .body, .button, .timecode: 12
        case .metadata: 10
        case .caption: 9
        }
    }

    var weight: Font.Weight {
        switch self {
        case .displayLogo, .sectionTitle, .songTitle: .semibold
        case .metadata, .button, .timecode: .medium
        case .body, .caption: .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .timecode: .monospaced
        default: .default
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .displayLogo: 4
        case .sectionTitle: 3
        case .songTitle, .body, .button, .timecode: 4
        case .metadata: 4
        case .caption: 3
        }
    }
}

extension Font {
    static func mixr(_ style: MixrTextStyle) -> Font {
        .system(size: style.size, weight: style.weight, design: style.design)
    }
}

struct MixrFontModifier: ViewModifier {
    let style: MixrTextStyle

    func body(content: Content) -> some View {
        content
            .font(.mixr(style))
            .lineSpacing(style.lineSpacing)
    }
}

extension View {
    func mixrFont(_ style: MixrTextStyle) -> some View {
        modifier(MixrFontModifier(style: style))
    }
}

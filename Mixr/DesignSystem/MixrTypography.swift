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

    var relativeTextStyle: Font.TextStyle {
        switch self {
        case .displayLogo: .largeTitle
        case .sectionTitle: .headline
        case .songTitle: .subheadline
        case .body, .button, .timecode: .body
        case .metadata: .caption
        case .caption: .caption2
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
    @ScaledMetric private var scaledSize: CGFloat

    init(style: MixrTextStyle) {
        self.style = style
        _scaledSize = ScaledMetric(
            wrappedValue: style.size,
            relativeTo: style.relativeTextStyle
        )
    }

    func body(content: Content) -> some View {
        content
            .font(
                .system(
                    size: min(scaledSize, style.size * 1.35),
                    weight: style.weight,
                    design: style.design
                )
            )
            .lineSpacing(style.lineSpacing)
    }
}

struct MixrScaledSystemFontModifier: ViewModifier {
    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let maximumScale: CGFloat
    @ScaledMetric private var scaledSize: CGFloat

    init(
        size: CGFloat,
        weight: Font.Weight,
        design: Font.Design,
        relativeTo textStyle: Font.TextStyle,
        maximumScale: CGFloat
    ) {
        baseSize = size
        self.weight = weight
        self.design = design
        self.maximumScale = maximumScale
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    func body(content: Content) -> some View {
        content.font(
            .system(
                size: min(scaledSize, baseSize * maximumScale),
                weight: weight,
                design: design
            )
        )
    }
}

extension View {
    func mixrFont(_ style: MixrTextStyle) -> some View {
        modifier(MixrFontModifier(style: style))
    }

    func mixrScaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body,
        maximumScale: CGFloat = 1.35
    ) -> some View {
        modifier(
            MixrScaledSystemFontModifier(
                size: size,
                weight: weight,
                design: design,
                relativeTo: textStyle,
                maximumScale: maximumScale
            )
        )
    }
}

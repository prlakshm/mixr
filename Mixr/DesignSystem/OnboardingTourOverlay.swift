import SwiftUI

// First-launch spotlight tour: dims the editor except one real control,
// animates the gesture over it, and explains it in a tip card.
// Steps, copy and flow: Models/OnboardingTour.swift.

// MARK: - Target frames

struct OnboardingTargetKey: PreferenceKey {
    static var defaultValue: [OnboardingTarget: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [OnboardingTarget: Anchor<CGRect>],
        nextValue: () -> [OnboardingTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { current, _ in current }
    }
}

extension View {
    /// Reports this view's frame as a tour spotlight target. Merges with
    /// targets inside it (a plain anchorPreference would replace them).
    func onboardingTarget(_ target: OnboardingTarget, isActive: Bool = true) -> some View {
        transformAnchorPreference(key: OnboardingTargetKey.self, value: .bounds) { value, anchor in
            if isActive { value[target] = anchor }
        }
    }
}

// MARK: - Tokens

enum OnboardingTourTokens {
    static let scrim = Color.black.opacity(0.62)
    static let ring = Color(hex: "9873EB")
    static let ringGlow = Color(hex: "9873EB", opacity: 0.55)
    static let spotlightPadding: CGFloat = 6
    static let spotlightRadius: CGFloat = 12

    static let cardWidth: CGFloat = 262
    static let cardRadius: CGFloat = 14
    static let cardFill = Color(hex: "050810", opacity: 0.88)
    static let cardBorder = Color.white.opacity(0.12)
    static let eyebrow = Color(hex: "B9A2F2")
    static let message = Color(hex: "B4BAC6")
    static let skip = Color.white.opacity(0.74)
    static let gap: CGFloat = 14
    static let margin: CGFloat = 12

    // Next button: the Play button's purple and glow.
    static let nextRest = Color(hex: "7231DD")
    static let nextHover = Color(hex: "8244E9")
    static let nextPressed = Color(hex: "682BCF")
    static let nextGlow = Color(hex: "7231DD")
}

// MARK: - Overlay

struct OnboardingTourOverlay: View {
    let step: OnboardingStep
    /// The target's frame in this overlay's coordinate space (nil while
    /// the control is off screen or not laid out yet).
    let targetFrame: CGRect?
    let containerSize: CGSize
    var onNext: () -> Void
    var onSkip: () -> Void

    @State private var cardSize = CGSize(width: OnboardingTourTokens.cardWidth, height: 150)

    var body: some View {
        let hole = targetFrame.map {
            $0.insetBy(dx: -OnboardingTourTokens.spotlightPadding, dy: -OnboardingTourTokens.spotlightPadding)
        }
        ZStack(alignment: .topLeading) {
            scrim(hole: hole)

            if let hole {
                RoundedRectangle(cornerRadius: OnboardingTourTokens.spotlightRadius, style: .continuous)
                    .strokeBorder(OnboardingTourTokens.ring, lineWidth: 1.5)
                    .shadow(color: OnboardingTourTokens.ringGlow, radius: 9)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                OnboardingFinger(gesture: step.gesture, travel: fingerTravel(in: hole))
                    .position(fingerPoint(in: hole))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .id(step)
            }

            OnboardingTipCard(step: step, onNext: onNext, onSkip: onSkip)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                .offset(cardOrigin(hole: hole))
                .id(step)
                .transition(.opacity)
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: step)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { announce() }
        .onChange(of: step) { _, _ in announce() }
    }

    // Dims everything except the spotlight. On step 1 touches inside the
    // spotlight reach the real Import Songs button; elsewhere the scrim
    // swallows them so the editor isn't edited by accident mid-tour.
    @ViewBuilder
    private func scrim(hole: CGRect?) -> some View {
        let shape = SpotlightScrimShape(hole: hole, cornerRadius: OnboardingTourTokens.spotlightRadius)
        let base = shape
            .fill(OnboardingTourTokens.scrim, style: FillStyle(eoFill: true))
            .accessibilityHidden(true)
        if step.passesTouchesToTarget, hole != nil {
            base.contentShape(shape, eoFill: true).onTapGesture {}
        } else {
            base.contentShape(Rectangle()).onTapGesture {}
        }
    }

    private func announce() {
        AccessibilityNotification.Announcement(
            "\(step.accessibilityProgress). \(step.title). \(step.message)"
        ).post()
    }

    // MARK: Placement

    /// Right of the target, else left, else above, else below; clamped
    /// inside the container. Centered when the target isn't on screen.
    private func cardOrigin(hole: CGRect?) -> CGSize {
        let size = cardSize
        let m = OnboardingTourTokens.margin, g = OnboardingTourTokens.gap
        let w = containerSize.width, h = containerSize.height
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, m), max(m, w - size.width - m)) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, m), max(m, h - size.height - m)) }
        guard let r = hole else {
            return CGSize(width: clampX((w - size.width) / 2), height: clampY((h - size.height) / 2))
        }
        if r.maxX + g + size.width <= w - m {
            return CGSize(width: r.maxX + g, height: clampY(r.midY - size.height / 2))
        }
        if r.minX - g - size.width >= m {
            return CGSize(width: r.minX - g - size.width, height: clampY(r.midY - size.height / 2))
        }
        if r.minY - g - size.height >= m {
            return CGSize(width: clampX(r.midX - size.width / 2), height: r.minY - g - size.height)
        }
        return CGSize(width: clampX(r.midX - size.width / 2), height: clampY(r.maxY + g))
    }

    private func fingerPoint(in r: CGRect) -> CGPoint {
        switch step.gesture {
        case .tap: CGPoint(x: r.midX, y: r.midY)
        case .swipeLeft: CGPoint(x: r.maxX - 28, y: r.midY)
        case .drag: CGPoint(x: r.minX + r.width * 0.62, y: r.minY + min(r.height / 2, 24))
        case .scroll: CGPoint(x: r.maxX - 90, y: r.midY + 10)
        }
    }

    private func fingerTravel(in r: CGRect) -> CGFloat {
        switch step.gesture {
        case .tap: 0
        case .swipeLeft: -min(96, r.width * 0.45)
        case .drag: 26
        case .scroll: -min(140, r.width * 0.3)
        }
    }
}

/// Full-container rectangle with a rounded hole; fill with eoFill.
struct SpotlightScrimShape: Shape {
    var hole: CGRect?
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let hole {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        }
        return path
    }
}

// MARK: - Finger

private struct OnboardingFinger: View {
    let gesture: OnboardingGesture
    /// Horizontal travel for swipe / drag / scroll (points).
    let travel: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                .scaleEffect(gesture == .tap && phase ? 2.1 : 1)
                .opacity(gesture == .tap && phase ? 0 : 0.9)
            // Translucent, like iOS touch indicators, so a small target
            // (the sfx button) stays readable under the finger.
            Circle()
                .fill(Color.white.opacity(0.42))
                .padding(3)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                .scaleEffect(gesture == .tap && phase ? 0.78 : 1)
        }
        .frame(width: 26, height: 26)
        .offset(x: gesture != .tap && phase ? travel : 0)
        .opacity(fadesAtEnd && phase ? 0.15 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(animation) { phase = true }
        }
    }

    private var fadesAtEnd: Bool { gesture == .swipeLeft || gesture == .scroll }

    private var animation: Animation {
        switch gesture {
        case .tap: .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
        case .drag: .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .swipeLeft, .scroll: .easeInOut(duration: 1.3).repeatForever(autoreverses: false)
        }
    }
}

// MARK: - Tip card

private struct OnboardingTipCard: View {
    let step: OnboardingStep
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(step.progressLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(OnboardingTourTokens.eyebrow)
                    .accessibilityLabel(step.accessibilityProgress)
                Spacer(minLength: 8)
                progressDots
            }
            Text(step.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(step.message)
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(OnboardingTourTokens.message)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if !step.isLast {
                    Button(OnboardingCopy.skip, action: onSkip)
                        .buttonStyle(OnboardingSkipButtonStyle())
                        .accessibilityHint("Ends the tour")
                }
                Spacer(minLength: 8)
                Button(step.isLast ? OnboardingCopy.finish : OnboardingCopy.next, action: onNext)
                    .buttonStyle(OnboardingNextButtonStyle())
            }
            .padding(.top, 2)
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(width: OnboardingTourTokens.cardWidth, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: OnboardingTourTokens.cardRadius, style: .continuous)
            shape
                .fill(OnboardingTourTokens.cardFill)
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.10)
                        .environment(\.colorScheme, .dark)
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingTourTokens.cardRadius, style: .continuous)
                .strokeBorder(OnboardingTourTokens.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, y: 9)
    }

    private var progressDots: some View {
        HStack(spacing: 4) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Capsule()
                    .fill(s == step ? OnboardingTourTokens.ring : Color.white.opacity(0.25))
                    .frame(width: s == step ? 14 : 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Filled purple, same fill and glow as the Play button.
/// Hover (pointer) a step lighter, press a step darker and 97 % scale.
struct OnboardingNextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnboardingNextButton(configuration: configuration)
    }

    private struct OnboardingNextButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            let fill = pressed ? OnboardingTourTokens.nextPressed
                : (isHovered ? OnboardingTourTokens.nextHover : OnboardingTourTokens.nextRest)
            let glow: (opacity: Double, radius: CGFloat) = pressed ? (0.35, 6) : (isHovered ? (0.70, 15) : (0.50, 10))
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minWidth: 84, minHeight: 36)
                .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: OnboardingTourTokens.nextGlow.opacity(glow.opacity), radius: glow.radius)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.15), value: pressed)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
    }
}

/// Text-only Skip: 74 % white, full white on hover, 44 pt tall target.
struct OnboardingSkipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnboardingSkipButton(configuration: configuration)
    }

    private struct OnboardingSkipButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(
                    configuration.isPressed ? Color.white.opacity(0.6)
                        : (isHovered ? Color.white : OnboardingTourTokens.skip)
                )
                .padding(.trailing, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

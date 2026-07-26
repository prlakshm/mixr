import SwiftUI
import UIKit

extension EditorSafeArea {
    var edgeInsets: EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    /// Best-effort insets for the very first render, before the probe below has
    /// had a layout pass to report — keeps the editor from visibly settling into
    /// its bands at launch.
    static var currentWindow: EditorSafeArea {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else {
            return .zero
        }
        let insets = window.safeAreaInsets
        return EditorSafeArea(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
    }
}

// MARK: - Window inset reader

private struct EditorSafeAreaKey: PreferenceKey {
    static var defaultValue: EditorSafeArea = .zero

    static func reduce(value: inout EditorSafeArea, nextValue: () -> EditorSafeArea) {
        value = nextValue()
    }
}

/// Watches the hosting window's safe-area insets, reporting on first layout,
/// on rotation, and on Catalyst window resizes.
private final class WindowSafeAreaProbeView: UIView {
    var onReport: ((EditorSafeArea) -> Void)?
    private var reported: EditorSafeArea?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        report()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        report()
    }

    func report() {
        guard let window else { return }
        let insets = window.safeAreaInsets
        let value = EditorSafeArea(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
        guard value != reported else { return }
        reported = value
        // Never mutate SwiftUI state inside a layout pass.
        DispatchQueue.main.async { [weak self] in
            self?.onReport?(value)
        }
    }
}

extension View {
    /// Reports the hosting window's safe-area insets — the editor lays its
    /// content out inside them while backgrounds stay full-bleed.
    func onWindowSafeAreaChange(
        _ action: @escaping (EditorSafeArea) -> Void
    ) -> some View {
        background {
            WindowSafeAreaReaderHost(action: action)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct WindowSafeAreaReaderHost: UIViewRepresentable {
    let action: (EditorSafeArea) -> Void

    func makeUIView(context: Context) -> WindowSafeAreaProbeView {
        let view = WindowSafeAreaProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onReport = action
        return view
    }

    func updateUIView(_ view: WindowSafeAreaProbeView, context: Context) {
        view.onReport = action
        view.report()
    }
}

// MARK: - Edge fade

/// Fills each safe-area band with the neighbouring editor surface dissolving
/// into the background, so the toolbar and the effects panel fade to black at a
/// notch, the home indicator, or a window title bar instead of ending in a hard
/// line. Editor content is clipped inside the bands, so nothing interactive is
/// ever dimmed.
struct EditorEdgeFade: View {
    let safeArea: EditorSafeArea
    /// Heights of the two banded surfaces — the side bands only fade alongside
    /// them, since the timeline between is already background-coloured.
    var transportHeight: CGFloat = 0
    var effectsHeight: CGFloat = 0
    var surface: Color = MixrColors.backgroundSecondary
    var background: Color = MixrColors.background

    var body: some View {
        ZStack {
            horizontalBand(.top, thickness: safeArea.top)
            horizontalBand(.bottom, thickness: safeArea.bottom)
            verticalBand(.leading, thickness: safeArea.leading)
            verticalBand(.trailing, thickness: safeArea.trailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Surface colour where the content begins, background at the outer edge.
    private func fade(towards edge: Edge) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: surface, location: 0),
                .init(color: surface.mix(with: background, by: 0.5), location: 0.45),
                .init(color: background, location: 1),
            ],
            startPoint: inner(of: edge),
            endPoint: outer(of: edge)
        )
    }

    @ViewBuilder
    private func horizontalBand(_ edge: Edge, thickness: CGFloat) -> some View {
        if thickness > 0 {
            fade(towards: edge)
                .frame(height: thickness)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: edge == .top ? .top : .bottom
                )
        }
    }

    /// Fades beside the toolbar and the effects panel only.
    @ViewBuilder
    private func verticalBand(_ edge: Edge, thickness: CGFloat) -> some View {
        if thickness > 0 {
            VStack(spacing: 0) {
                fade(towards: edge)
                    .frame(height: max(0, transportHeight))
                Spacer(minLength: 0)
                fade(towards: edge)
                    .frame(height: max(0, effectsHeight))
            }
            .padding(.top, safeArea.top)
            .padding(.bottom, safeArea.bottom)
            .frame(width: thickness)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: edge == .leading ? .leading : .trailing
            )
        }
    }

    private func inner(of edge: Edge) -> UnitPoint {
        switch edge {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        }
    }

    private func outer(of edge: Edge) -> UnitPoint {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

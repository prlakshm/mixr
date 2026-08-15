#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Catalyst-only: routes trackpad / scroll-wheel panning over the timeline's
/// lane viewport into the horizontal scroll position.
///
/// The lanes live in a horizontal `ScrollView` nested inside the editor's
/// vertical one. Touch platforms resolve that nesting per-gesture, but with a
/// pointer the outer vertical scroll view claims continuous scroll events and
/// the inner one never sees the horizontal component — the timeline reads as
/// unscrollable on a Mac. This bridge listens for scroll-type pans at the
/// window (a pan recognizer with `maximumNumberOfTouches == 0` receives only
/// pointer scroll events, never clicks or touches), takes the horizontal
/// component for the timeline, and leaves the vertical component alone so the
/// outer scroll view keeps working exactly as it does today.
struct EditorPointerScrollBridge: UIViewRepresentable {
    /// False while a modal surface or clip drag owns input.
    var isEnabled: Bool
    /// Content overflow: `max(0, contentW - viewportW)`.
    var maximumOffset: CGFloat
    /// The timeline's current horizontal offset.
    var currentOffset: CGFloat
    /// Absolute target offset, already clamped.
    var onScroll: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        // Never participates in hit-testing — the window-level recognizer does
        // the listening; this view only defines the active region.
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        context.coordinator.bridgeView = view
        return view
    }

    func updateUIView(_ view: BridgeView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.maximumOffset = maximumOffset
        context.coordinator.latestOffset = currentOffset
        context.coordinator.onScroll = onScroll
    }

    static func dismantleUIView(_ view: BridgeView, coordinator: Coordinator) {
        coordinator.detachRecognizer()
    }

    final class BridgeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window {
                coordinator?.attachRecognizer(to: window)
            } else {
                coordinator?.detachRecognizer()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true
        var maximumOffset: CGFloat = 0
        var latestOffset: CGFloat = 0
        var onScroll: (CGFloat) -> Void = { _ in }
        weak var bridgeView: BridgeView?

        private weak var recognizer: UIPanGestureRecognizer?
        private var gestureStartOffset: CGFloat = 0

        func attachRecognizer(to window: UIWindow) {
            guard recognizer == nil else { return }
            let pan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleScrollPan(_:))
            )
            // Scroll events only: a zero-touch pan can never claim a click,
            // a clip drag, or any touch gesture.
            pan.allowedScrollTypesMask = .all
            pan.maximumNumberOfTouches = 0
            pan.delegate = self
            window.addGestureRecognizer(pan)
            recognizer = pan
        }

        func detachRecognizer() {
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
        }

        @objc private func handleScrollPan(_ pan: UIPanGestureRecognizer) {
            guard let bridgeView, let window = pan.view else { return }
            switch pan.state {
            case .began:
                gestureStartOffset = latestOffset
                fallthrough
            case .changed:
                let translation = pan.translation(in: window)
                let target = min(
                    maximumOffset,
                    max(0, gestureStartOffset - translation.x)
                )
                // Only drive when the pointer scroll actually has a horizontal
                // component — pure vertical scrolls belong to the outer
                // scroll view untouched.
                if abs(translation.x) > 0.5 {
                    onScroll(target)
                }
                _ = bridgeView
            default:
                break
            }
        }

        // Begin only for pointer scrolls that start over the lane viewport.
        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard isEnabled, maximumOffset > 0, let bridgeView else {
                return false
            }
            let location = gestureRecognizer.location(in: bridgeView)
            return bridgeView.bounds.contains(location)
        }

        // The vertical component must keep flowing to the editor's own scroll
        // views, so this recognizer never blocks them.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif

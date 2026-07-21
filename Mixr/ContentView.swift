import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppAppearanceState.self) private var appearanceState

#if DEBUG
    private var isVisualQAScreenshot: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-MixrPartyModeScreenshot")
            || arguments.contains("-MixrVisualQAScreenshot")
            || arguments.contains("-MixrPartyModeCaptureProgress")
            || arguments.contains("-MixrPartyModeCaptureSequence")
    }
#endif

    var body: some View {
        timelineContent
            .modifier(PartyModeAnimationHost(appearanceState: appearanceState))
#if DEBUG
            .task {
                await runVisualQASessionIfRequested()
            }
#endif
    }

    @ViewBuilder
    private var timelineContent: some View {
#if DEBUG
        if isVisualQAScreenshot {
            PartyModeScreenshotVerificationContainer {
                TimelineScreen()
            }
        } else {
            TimelineScreen()
        }
#else
        TimelineScreen()
#endif
    }

#if DEBUG
    private func runVisualQASessionIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-MixrVisualQAScreenshot") {
            try? await Task.sleep(for: .seconds(2))
            _ = try? PartyModeVisualQACapture.capture(filename: "mixr-normal.png")
            return
        }

        if arguments.contains("-MixrPartyModeCaptureSequence") {
            await captureLiveActivationSequence()
            return
        }

        let capturesSettledPartyMode = arguments.contains("-MixrPartyModeScreenshot")
        let capturesActivation = arguments.contains("-MixrPartyModeCaptureProgress")
        guard capturesSettledPartyMode || capturesActivation else { return }

        // Let persistence and the first layout pass settle before activating.
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        if !appearanceState.isPartyModeEnabled {
            appearanceState.togglePartyMode()
        }

        if capturesActivation {
            try? await Task.sleep(for: .milliseconds(180))
            let progress = visualQACaptureProgress(from: arguments)
            let suffix = String(format: "%.3f", progress)
                .replacingOccurrences(of: ".", with: "_")
            _ = try? PartyModeVisualQACapture.capture(
                filename: "mixr-party-progress-\(suffix).png"
            )
        } else {
            try? await Task.sleep(
                for: .seconds(PartyModeTokens.activationSequenceDuration + 0.3)
            )
            _ = try? PartyModeVisualQACapture.capture(
                filename: "mixr-party-settled.png"
            )
        }
    }

    private func visualQACaptureProgress(from arguments: [String]) -> Double {
        guard let flagIndex = arguments.firstIndex(of: "-MixrPartyModeCaptureProgress"),
              arguments.indices.contains(flagIndex + 1),
              let value = Double(arguments[flagIndex + 1])
        else { return 0 }
        return min(1, max(0, value))
    }

    private func captureLiveActivationSequence() async {
        let captures: [(filename: String, elapsed: TimeInterval)] = [
            (
                "mixr-party-live-initial.png",
                PartyModeTokens.traceDurationPanel * 0.18
            ),
            (
                "mixr-party-live-mid.png",
                PartyModeTokens.traceDurationPanel * 0.55
            ),
            (
                "mixr-party-live-reconnect.png",
                PartyModeTokens.globalAfterglintStartTime
                    - PartyModeTokens.reconnectFlareDuration * 0.5
            ),
            (
                "mixr-party-live-afterglint-early.png",
                PartyModeTokens.globalAfterglintStartTime
                    + PartyModeTokens.afterglintDuration * 0.18
            ),
        ]
        var frames: [PartyModeVisualQACapture.Frame] = []

        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        if !appearanceState.isPartyModeEnabled {
            appearanceState.togglePartyMode()
        }

        let startedAt = Date.timeIntervalSinceReferenceDate
        for capture in captures {
            let target = startedAt + capture.elapsed
            let remaining = target - Date.timeIntervalSinceReferenceDate
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            if let frame = try? PartyModeVisualQACapture.snapshot(
                filename: capture.filename
            ) {
                frames.append(frame)
            }
            // Give the shared activation clock a render turn after the
            // synchronous UIKit hierarchy snapshot. PNG encoding is deferred
            // until every timing-sensitive sample is held in memory.
            try? await Task.sleep(for: .milliseconds(16))
        }

        let settledTarget = startedAt
            + PartyModeTokens.activationSequenceDuration
            + 0.3
        let settledRemaining = settledTarget - Date.timeIntervalSinceReferenceDate
        if settledRemaining > 0 {
            try? await Task.sleep(for: .seconds(settledRemaining))
        }
        guard !Task.isCancelled else { return }
        if let frame = try? PartyModeVisualQACapture.snapshot(
            filename: "mixr-party-live-settled.png"
        ) {
            frames.append(frame)
        }

        for frame in frames {
            _ = try? PartyModeVisualQACapture.write(frame)
        }
    }
#endif
}

#if DEBUG
/// Headless `simctl` capture has no Simulator window to rotate. Keep this
/// verification-only transform outside `TimelineScreen` so the feature renders
/// at the same landscape dimensions while normal application geometry is
/// completely untouched.
private struct PartyModeScreenshotVerificationContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= proxy.size.height {
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                content
                    .frame(width: proxy.size.height, height: proxy.size.width)
                    .rotationEffect(.degrees(90))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .ignoresSafeArea()
    }
}
#endif

#Preview {
    ContentView()
        .frame(width: 932, height: 430)
        .environment(AppAppearanceState())
        .modelContainer(for: MixrProjectRecord.self, inMemory: true)
}

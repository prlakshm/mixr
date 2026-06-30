import CoreGraphics
import Foundation

// MARK: - Clip Drop Result

enum ClipDropResult: Equatable, Sendable {
    /// Snap or free placement — ripple handled by reflowedClips on commit.
    case place(start: CGFloat)
    /// User inserted into the body of an existing clip; timeline splits it on commit.
    case insertIntoClip(
        targetClipID: UUID,
        splitUnit: CGFloat,
        insertStart: CGFloat
    )
}

// MARK: - Visual Preview Frame (render-only, never stored in track model)

struct ClipRenderFrame: Identifiable, Equatable, Sendable {
    /// Stable render identity — may differ from clipID when showing split segments.
    var id: String
    let clipID: UUID
    var start: CGFloat
    var length: CGFloat
    var opacity: Double
    var isSourceGhost: Bool
    /// Local neighbor preview shift in screen pixels.
    var neighborShiftPx: CGFloat

    init(
        id: String? = nil,
        clipID: UUID,
        start: CGFloat,
        length: CGFloat,
        opacity: Double = 1,
        isSourceGhost: Bool = false,
        neighborShiftPx: CGFloat = 0
    ) {
        self.id = id ?? clipID.uuidString
        self.clipID = clipID
        self.start = start
        self.length = length
        self.opacity = opacity
        self.isSourceGhost = isSourceGhost
        self.neighborShiftPx = neighborShiftPx
    }
}

enum MixrTimeline {
    nonisolated static let totalUnits: CGFloat = 130
    nonisolated static let timelineDurationSeconds: Double = 240
    nonisolated static let clipEdgeEpsilon: CGFloat = 0.001
    nonisolated static let minClipLengthUnits: CGFloat = 2

    private enum SnapKind: Equatable {
        case before
        case after
    }

    nonisolated static func seconds(fromUnits units: CGFloat) -> Double {
        Double(units / totalUnits) * timelineDurationSeconds
    }

    nonisolated static func units(fromSeconds seconds: Double) -> CGFloat {
        guard timelineDurationSeconds > 0 else { return 0 }
        return CGFloat(seconds / timelineDurationSeconds) * totalUnits
    }

    nonisolated static func remixDurationSeconds(tracks: [MixrTrack]) -> Double {
        tracks
            .flatMap(\.clips)
            .map { seconds(fromUnits: $0.start + $0.length) }
            .max() ?? 0
    }

    nonisolated static func contentUnits(for tracks: [MixrTrack]) -> CGFloat {
        let maxClipEnd = tracks
            .flatMap(\.clips)
            .map { $0.start + $0.length }
            .max() ?? 0
        return max(totalUnits, maxClipEnd)
    }

    nonisolated static func gridLineSeconds(upToContentUnits units: CGFloat) -> [CGFloat] {
        let maxSeconds = Int(seconds(fromUnits: units).rounded(.up))
        guard maxSeconds > 0 else { return [0] }
        return stride(from: 0, through: maxSeconds, by: 10).map { CGFloat($0) }
    }

    nonisolated static func rulerLabelSeconds(upToContentUnits units: CGFloat) -> [CGFloat] {
        let maxSeconds = Int(seconds(fromUnits: units).rounded(.up))
        guard maxSeconds > 0 else { return [0] }
        return stride(from: 0, through: maxSeconds, by: 30).map { CGFloat($0) }
    }

    /// Insertion start for the dragged clip derived from a drop result.
    nonisolated static func insertionStart(
        for result: ClipDropResult,
        movingClipLength: CGFloat
    ) -> CGFloat {
        switch result {
        case .place(let start):
            return max(0, start)
        case .insertIntoClip(_, _, let insertStart):
            return max(0, insertStart)
        }
    }

    /// Priority:
    ///   1. Ghost restore  — within 10px of originalStart → return original start (no ripple)
    ///   2. Clip-edge snap — within snapZone of any clip edge → snap before/after
    ///   3. Literal gap    — rawStart lands entirely in empty space → place exactly there
    ///   4. Insert into clip body — pointer inside a clip body (outside edge snap zones)
    ///   5. Free placement
    ///
    /// Hysteresis: if pointer moved less than `hysteresisUnits` from the last anchor, keep `previousResult`.
    nonisolated static func resolveClipDrop(
        moving clipID: UUID,
        rawStart: CGFloat,
        pointerUnit: CGFloat,
        in clips: [MixrClip],
        snapZoneUnits: CGFloat,
        hysteresisUnits: CGFloat,
        previousResult: ClipDropResult?,
        previousPointerUnit: CGFloat?,
        originalStart: CGFloat? = nil,
        epsilon: CGFloat = clipEdgeEpsilon
    ) -> ClipDropResult {
        if let previousResult,
           let previousPointerUnit,
           abs(pointerUnit - previousPointerUnit) < hysteresisUnits {
            return previousResult
        }

        guard let movingClip = clips.first(where: { $0.id == clipID }) else {
            return .place(start: max(0, rawStart))
        }

        let others = clips.filter { $0.id != clipID }
        let snapZone = max(0, snapZoneUnits)

        // 1 — Ghost restore: released within snapZone of original position → no-op drop
        if let orig = originalStart,
           abs(rawStart - orig) <= snapZone + epsilon {
            return .place(start: orig)
        }

        // 2 — Clip-edge snap (before or after a clip edge)
        if let target = bestSnapTarget(
            kind: .before,
            pointerUnit: pointerUnit,
            others: others,
            snapZone: snapZone,
            epsilon: epsilon
        ) {
            let prefixEnd = others
                .filter { $0.id != target.id && $0.start < target.start - epsilon }
                .map { $0.start + $0.length }
                .max() ?? 0
            let start = max(0, max(prefixEnd, target.start - movingClip.length))
            return .place(start: start)
        }

        if let target = bestSnapTarget(
            kind: .after,
            pointerUnit: pointerUnit,
            others: others,
            snapZone: snapZone,
            epsilon: epsilon
        ) {
            return .place(start: max(0, target.start + target.length))
        }

        // 3 — Literal gap: rawStart lands in empty space → place exactly where released
        let clampedStart = max(0, rawStart)
        let movingEnd = clampedStart + movingClip.length
        let startsInClip = others.contains { clip in
            clampedStart > clip.start + epsilon
                && clampedStart < clip.start + clip.length - epsilon
        }
        if !startsInClip {
            // Tail may overlap a later clip — that's handled by reflowedClips ripple on commit.
            // Drop exactly here; do NOT force an insert-into-clip in this case.
            return .place(start: clampedStart)
        }

        // 4 — Insert into clip body (pointer lands inside a clip, outside its edge snap zones)
        if let target = insertTarget(
            pointerUnit: pointerUnit,
            others: others,
            snapZone: snapZone,
            epsilon: epsilon
        ) {
            let minSplit = target.start + minClipLengthUnits
            let maxSplit = target.start + target.length - minClipLengthUnits
            let splitUnit = min(max(pointerUnit, minSplit), maxSplit)
            return .insertIntoClip(
                targetClipID: target.id,
                splitUnit: splitUnit,
                insertStart: splitUnit
            )
        }

        // 5 — Free placement
        return .place(start: clampedStart)
    }

    /// Commit-only mutation — never call during drag preview.
    nonisolated static func applyClipDrop(
        result: ClipDropResult,
        moving clipID: UUID,
        in clips: [MixrClip],
        epsilon: CGFloat = clipEdgeEpsilon
    ) -> [MixrClip] {
        switch result {
        case .place(let start):
            return reflowedClips(moving: clipID, to: start, in: clips, epsilon: epsilon)
        case .insertIntoClip(let targetClipID, let splitUnit, let insertStart):
            return applyInsertIntoClip(
                moving: clipID,
                targetClipID: targetClipID,
                splitUnit: splitUnit,
                insertStart: insertStart,
                in: clips,
                epsilon: epsilon
            )
        }
    }

    /// Visual-only frames for drag preview — does not mutate or fabricate model clips.
    nonisolated static func resolveClipRenderFrames(
        moving clipID: UUID,
        dropResult: ClipDropResult,
        insertPreviewProgress: CGFloat,
        in clips: [MixrClip],
        neighborShiftPx: CGFloat,
        epsilon: CGFloat = clipEdgeEpsilon
    ) -> [ClipRenderFrame] {
        guard let movingClip = clips.first(where: { $0.id == clipID }) else {
            return clips.map {
                ClipRenderFrame(clipID: $0.id, start: $0.start, length: $0.length)
            }
        }

        let insertionStart = insertionStart(for: dropResult, movingClipLength: movingClip.length)
        let others = clips
            .filter { $0.id != clipID }
            .sorted { $0.start < $1.start }

        let prevID = others.last(where: { $0.start + $0.length <= insertionStart + epsilon })?.id
        let nextID = others.first(where: { $0.start >= insertionStart - epsilon && $0.id != prevID })?.id

        var frames: [ClipRenderFrame] = []

        frames.append(ClipRenderFrame(
            clipID: clipID,
            start: movingClip.start,
            length: movingClip.length,
            opacity: 0.28,
            isSourceGhost: true
        ))

        for clip in others {
            var shift: CGFloat = 0
            if clip.id == prevID { shift = -neighborShiftPx }
            if clip.id == nextID { shift = neighborShiftPx }

            if case .insertIntoClip(let targetID, let splitUnit, _) = dropResult,
               clip.id == targetID,
               insertPreviewProgress > epsilon {
                let progress = min(max(insertPreviewProgress, 0), 1)
                let separation = movingClip.length * progress
                let leadingLen = max(minClipLengthUnits, splitUnit - clip.start - separation / 2)
                let trailingStart = splitUnit + separation / 2
                let trailingLen = max(
                    minClipLengthUnits,
                    (clip.start + clip.length) - trailingStart
                )

                frames.append(ClipRenderFrame(
                    id: "\(clip.id.uuidString)-leading",
                    clipID: clip.id,
                    start: clip.start,
                    length: leadingLen,
                    neighborShiftPx: shift
                ))
                frames.append(ClipRenderFrame(
                    id: "\(clip.id.uuidString)-trailing",
                    clipID: clip.id,
                    start: trailingStart,
                    length: trailingLen,
                    neighborShiftPx: shift
                ))
            } else {
                frames.append(ClipRenderFrame(
                    clipID: clip.id,
                    start: clip.start,
                    length: clip.length,
                    neighborShiftPx: shift
                ))
            }
        }

        return frames
    }

    /// Repositions a dragged clip and pushes only clips that overlap its new range.
    nonisolated static func reflowedClips(
        moving clipID: UUID,
        to proposedStart: CGFloat,
        in clips: [MixrClip],
        epsilon: CGFloat = clipEdgeEpsilon
    ) -> [MixrClip] {
        guard var movingClip = clips.first(where: { $0.id == clipID }) else {
            return clips.sorted { $0.start < $1.start }
        }

        let anchoredStart = max(0, proposedStart)
        let emptyTransition = ClipTransition()
        movingClip.start = anchoredStart
        movingClip.transitionIn = emptyTransition
        movingClip.transitionOut = emptyTransition

        let movingEnd = anchoredStart + movingClip.length
        let otherClips = clips
            .filter { $0.id != clipID }
            .sorted { lhs, rhs in
                if abs(lhs.start - rhs.start) > epsilon { return lhs.start < rhs.start }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        var arranged: [MixrClip] = []
        var suffix: [MixrClip] = []
        var prefixEnd: CGFloat = 0

        for clip in otherClips {
            let clipEnd = clip.start + clip.length
            if clipEnd <= anchoredStart + epsilon {
                var prefixClip = clip
                if prefixClip.start < prefixEnd - epsilon {
                    prefixClip.start = prefixEnd
                    prefixClip.transitionIn = emptyTransition
                    prefixClip.transitionOut = emptyTransition
                }
                prefixEnd = max(prefixEnd, prefixClip.start + prefixClip.length)
                arranged.append(prefixClip)
            } else {
                suffix.append(clip)
            }
        }

        arranged.append(movingClip)

        var cursorEnd = movingEnd
        for var clip in suffix {
            if clip.start < cursorEnd - epsilon {
                clip.start = cursorEnd
                clip.transitionIn = emptyTransition
                clip.transitionOut = emptyTransition
            }
            cursorEnd = max(cursorEnd, clip.start + clip.length)
            arranged.append(clip)
        }

        return arranged.sorted { lhs, rhs in
            if abs(lhs.start - rhs.start) > epsilon { return lhs.start < rhs.start }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    nonisolated static func formattedTime(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    // MARK: - Private helpers

    private nonisolated static func bestSnapTarget(
        kind: SnapKind,
        pointerUnit: CGFloat,
        others: [MixrClip],
        snapZone: CGFloat,
        epsilon: CGFloat
    ) -> MixrClip? {
        var best: (clip: MixrClip, distance: CGFloat)?

        for clip in others {
            guard clip.length > epsilon else { continue }
            let edge: CGFloat
            switch kind {
            case .before: edge = clip.start
            case .after:  edge = clip.start + clip.length
            }
            let distance = abs(pointerUnit - edge)
            guard distance <= snapZone + epsilon else { continue }
            if best == nil || distance < best!.distance - epsilon {
                best = (clip, distance)
            }
        }

        return best?.clip
    }

    private nonisolated static func insertTarget(
        pointerUnit: CGFloat,
        others: [MixrClip],
        snapZone: CGFloat,
        epsilon: CGFloat
    ) -> MixrClip? {
        for clip in others {
            let start = clip.start
            let end = clip.start + clip.length
            guard clip.length > minClipLengthUnits * 2 + epsilon else { continue }

            let inBody = pointerUnit > start + snapZone + epsilon
                && pointerUnit < end - snapZone - epsilon
            if inBody { return clip }
        }
        return nil
    }

    private nonisolated static func applyInsertIntoClip(
        moving clipID: UUID,
        targetClipID: UUID,
        splitUnit: CGFloat,
        insertStart: CGFloat,
        in clips: [MixrClip],
        epsilon: CGFloat
    ) -> [MixrClip] {
        guard var movingClip = clips.first(where: { $0.id == clipID }),
              let targetClip = clips.first(where: { $0.id == targetClipID })
        else {
            return reflowedClips(moving: clipID, to: insertStart, in: clips, epsilon: epsilon)
        }

        let minSplit = targetClip.start + minClipLengthUnits
        let maxSplit = targetClip.start + targetClip.length - minClipLengthUnits
        let clampedSplit = min(max(splitUnit, minSplit), maxSplit)
        let leftLen = clampedSplit - targetClip.start
        let rightLen = targetClip.length - leftLen

        guard leftLen >= minClipLengthUnits - epsilon,
              rightLen >= minClipLengthUnits - epsilon
        else {
            return reflowedClips(moving: clipID, to: insertStart, in: clips, epsilon: epsilon)
        }

        var a1 = targetClip
        let savedTransitionOut = a1.transitionOut
        a1.length = leftLen
        a1.transitionOut = .none

        let a2ID = UUID()
        var a2 = MixrClip(
            id: a2ID,
            start: clampedSplit + movingClip.length,
            length: rightLen
        )
        a2.transitionIn = .none
        a2.transitionOut = savedTransitionOut

        movingClip.start = clampedSplit
        movingClip.transitionIn = .none
        movingClip.transitionOut = .none

        var rebuilt = clips.filter { $0.id != clipID && $0.id != targetClipID }
        rebuilt.append(a1)
        rebuilt.append(movingClip)
        rebuilt.append(a2)
        rebuilt.sort { lhs, rhs in
            if abs(lhs.start - rhs.start) > epsilon { return lhs.start < rhs.start }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return reflowedClips(moving: clipID, to: clampedSplit, in: rebuilt, epsilon: epsilon)
    }
}

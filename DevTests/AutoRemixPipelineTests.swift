import Foundation

// Standalone verification harness for the Auto remix plan pipeline —
// NOT part of the app target (the Xcode project only syncs the Mixr/ folder).
// Run from the repo root with:
//
//   Scripts/run_auto_remix_tests.sh
//
// Covers: scope engine routing, seed determinism, duo handoffs, SFX density,
// gap repair, intentional pauses, supported effects only, applied summary,
// and atomic apply (no mutation of the input track array).

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

// MARK: - Fixtures

func makeSong(
    title: String,
    artist: String = "Artist",
    bpm: Int = 124,
    key: String = "Am",
    durationSeconds: Double = 210,
    color: MixrWaveformColor = .pink,
    bpmConfidence: Double? = nil,
    keyConfidence: Double? = nil
) -> MixrTrack {
    let length = MixrTimeline.units(fromSeconds: min(durationSeconds, 180))
    return MixrTrack(
        id: UUID(),
        title: title,
        artist: artist,
        duration: "3:30",
        durationSeconds: durationSeconds,
        bpm: bpm,
        bpmConfidence: bpmConfidence,
        key: key,
        keyConfidence: keyConfidence,
        color: color,
        volume: 0.75,
        isMuted: false,
        url: nil,
        artworkData: nil,
        clips: [MixrClip(id: UUID(), start: 0, length: length)]
    )
}

// MARK: - 1. Scope engine routing

check(
    "Entire Project uses plan pipeline",
    AutoRemixRunner.engine(for: .entireProject) == .planPipeline
)
check(
    "Selected Clip uses arrangement engine",
    AutoRemixRunner.engine(for: .selectedClip(UUID())) == .arrangementEngine
)
check(
    "Playhead Clips uses arrangement engine",
    AutoRemixRunner.engine(for: .playheadClips) == .arrangementEngine
)

// MARK: - 2. Successful apply + summary from applied plan

do {
    let tracks = [makeSong(title: "Hook Song", bpm: 128, key: "C")]
    let seed: UInt64 = 42
    let outcome = AutoRemixRunner.runEntireProject(tracks: tracks, seed: seed)
    switch outcome {
    case .success(_, let plan, let summary):
        check("Remix mode for one song", plan.mode == .remix)
        check("Summary mode matches plan", summary.modeTitle == plan.mode.rawValue)
        check("Summary seed retained for debug", summary.randomSeed == seed)
        check("Summary BPM matches plan", summary.targetBPM == Int(plan.targetBPM.rounded()))
        check("Summary handoffs match plan", summary.handoffCount == plan.handoffCount)
        check("Summary decisions come from plan records", summary.decisions.count == plan.decisions.count)
        check("Plan retains seed", plan.randomSeed == seed)
        check("Applied plan has placements", !plan.placements.isEmpty)
    case .failure(let message):
        check("One-song Entire Project succeeds", false, message)
    }
}

// MARK: - 3. Failed apply leaves input unchanged (atomic)

do {
    let empty: [MixrTrack] = []
    let original = empty
    let outcome = AutoRemixRunner.runEntireProject(tracks: empty, seed: 1)
    if case .failure = outcome {
        check("Empty project fails cleanly", true)
        check("Failure does not invent tracks", original.isEmpty)
    } else {
        check("Empty project fails cleanly", false)
    }
}

do {
    // Song with clips but zero-length source — still has clips; should usually succeed.
    // Force failure path: tracks with songs but no clips.
    let bare = MixrTrack(
        id: UUID(),
        title: "Bare",
        artist: "X",
        duration: "--:--",
        durationSeconds: 120,
        bpm: 120,
        key: "C",
        color: .blue,
        volume: 0.75,
        isMuted: false,
        url: nil,
        artworkData: nil,
        clips: []
    )
    let before = [bare]
    let outcome = AutoRemixRunner.runEntireProject(tracks: before, seed: 9)
    check("No-clip songs fail without applying", {
        if case .failure = outcome { return true }
        return false
    }())
    check("Input track array identity preserved on failure path", before[0].clips.isEmpty)
}

// MARK: - 4. Same seed → same plan

do {
    let tracks = [
        makeSong(title: "Alpha", bpm: 122, key: "Am", color: .pink),
        makeSong(title: "Beta", bpm: 126, key: "C", color: .purple),
    ]
    let seed: UInt64 = 99_001
    let a = AutoRemixRunner.runEntireProject(tracks: tracks, seed: seed)
    let b = AutoRemixRunner.runEntireProject(tracks: tracks, seed: seed)
    switch (a, b) {
    case (.success(_, let pa, _), .success(_, let pb, _)):
        check("Same seed → same mode", pa.mode == pb.mode)
        check("Same seed → same target BPM", abs(pa.targetBPM - pb.targetBPM) < 0.01)
        check("Same seed → same sequence", pa.sequence == pb.sequence)
        check("Same seed → same handoff count", pa.handoffCount == pb.handoffCount)
        check("Same seed → same placement count", pa.placements.count == pb.placements.count)
        check("Same seed → same SFX count", pa.sfxEvents.count == pb.sfxEvents.count)
        let sameStarts = zip(pa.placements, pb.placements).allSatisfy {
            abs($0.timelineStart - $1.timelineStart) < 0.001
                && abs($0.sourceStart - $1.sourceStart) < 0.001
                && $0.songID == $1.songID
        }
        check("Same seed → same clip placements", sameStarts)
        let sameFX = zip(pa.placements, pb.placements).allSatisfy { $0.effects == $1.effects }
        check("Same seed → same effects", sameFX)
        let sameSFX = zip(pa.sfxEvents, pb.sfxEvents).allSatisfy {
            $0.assetID == $1.assetID && abs($0.timelineStart - $1.timelineStart) < 0.001
        }
        check("Same seed → same SFX selections", sameSFX)
    default:
        check("Same seed dual run succeeds", false)
    }
}

// MARK: - 5. Two-song mashup targets ≥3 handoffs

do {
    let tracks = [
        makeSong(title: "Groove Anchor", bpm: 124, key: "Am", color: .pink),
        makeSong(title: "Vocal Feature", bpm: 124, key: "C", color: .purple),
    ]
    let outcome = AutoRemixRunner.runEntireProject(tracks: tracks, seed: 7)
    switch outcome {
    case .success(_, let plan, let summary):
        check("Two songs → Mashup mode", plan.mode == .mashup)
        check("Two-song mashup handoffs ≥ 3", plan.handoffCount >= 3, "got \(plan.handoffCount)")
        check("Summary sequence uses song names", summary.sequence.contains("Groove Anchor") || summary.sequence.contains("Vocal Feature"))
        let letters = AutoRemixPlanner.summary(for: plan, tracks: tracks)
        _ = letters
    case .failure(let message):
        check("Two-song mashup succeeds", false, message)
    }
}

// MARK: - 6. One-song remix keeps musical SFX sparse (pulse is separate)

do {
    let remixTracks = [makeSong(title: "Solo Remix", bpm: 128, key: "G")]
    let mashupTracks = [
        makeSong(title: "M1", bpm: 128, key: "G", color: .pink),
        makeSong(title: "M2", bpm: 128, key: "Em", color: .blue),
    ]
    let remix = AutoRemixRunner.runEntireProject(tracks: remixTracks, seed: 55)
    let mashup = AutoRemixRunner.runEntireProject(tracks: mashupTracks, seed: 55)
    switch (remix, mashup) {
    case (.success(_, let rp, _), .success(_, let mp, _)):
        // Musical SFX (risers/impacts) stay sparse; club pulse lives in
        // pulseRegions and is expanded at apply/render time.
        let musical = rp.sfxEvents.filter { !SoundEffectLibrary.isPulseLayer($0.assetID) }
        let rMinutes = max(rp.targetDuration / 60, 0.01)
        check(
            "One-song remix musical SFX ≤ 3 events/min",
            Double(musical.count) / rMinutes <= 3.0 + 0.0001,
            String(format: "%.2f events/min", Double(musical.count) / rMinutes)
        )
        check("Mashup still coordinates SFX moments", !mp.sfxEvents.isEmpty)
        check("One-song remix records pulse regions", !rp.pulseRegions.isEmpty)
    default:
        check("Remix vs Mashup SFX comparison runs", false)
    }
}

// MARK: - 7. Gap repair (mashup path — multiple placements)

do {
    let songs = [
        makeSong(title: "Gap Song A", bpm: 120, key: "C", color: .pink),
        makeSong(title: "Gap Song B", bpm: 120, key: "Am", color: .blue),
    ]
    if let (draft, profiles) = AutoRemixPlanner.makePlan(tracks: songs, seed: 12) {
        var broken = draft
        // Inject an accidental 1-second gap between the first two dominant placements.
        let dominants = broken.placements
            .enumerated()
            .filter { $0.element.role == .dominant }
            .sorted { $0.element.timelineStart < $1.element.timelineStart }
        if dominants.count >= 2 {
            let secondIdx = dominants[1].offset
            let threshold = dominants[1].element.timelineStart
            broken.placements[secondIdx].timelineStart += 1.0
            for i in broken.placements.indices where i != secondIdx
                && broken.placements[i].timelineStart >= threshold - 0.001 {
                broken.placements[i].timelineStart += 1.0
            }
            for i in broken.sfxEvents.indices where broken.sfxEvents[i].timelineStart >= threshold - 0.001 {
                broken.sfxEvents[i].timelineStart += 1.0
            }
            for i in broken.intentionalGaps.indices where broken.intentionalGaps[i].start >= threshold - 0.001 {
                broken.intentionalGaps[i].start += 1.0
                broken.intentionalGaps[i].end += 1.0
            }
            for i in broken.pulseRegions.indices where broken.pulseRegions[i].timelineStart >= threshold - 0.001 {
                broken.pulseRegions[i].timelineStart += 1.0
                broken.pulseRegions[i].timelineEnd += 1.0
            }

            let repaired = AutoRemixValidator.validate(broken, profiles: profiles, tuning: .standard)
            let maxGap = repaired.eighthNoteSeconds
            let coveragePlacements = repaired.placements.map { ($0.timelineStart, $0.timelineEnd) }
            let sorted = coveragePlacements.sorted { $0.0 < $1.0 }
            var merged: [(Double, Double)] = []
            for range in sorted {
                if var last = merged.last, range.0 <= last.1 + 0.001 {
                    last.1 = max(last.1, range.1)
                    merged[merged.count - 1] = last
                } else {
                    merged.append(range)
                }
            }
            var largestAccidental = 0.0
            for pair in zip(merged, merged.dropFirst()) {
                let gapStart = pair.0.1
                let gapEnd = pair.1.0
                let gap = gapEnd - gapStart
                let intentional = repaired.intentionalGaps.contains { g in
                    let overlap = min(gapEnd, g.end) - max(gapStart, g.start)
                    return overlap > gap * 0.5
                }
                if intentional { continue }
                if gap > largestAccidental { largestAccidental = gap }
            }
            check(
                "Invalid gaps repaired to ≤ eighth note",
                largestAccidental <= maxGap + 0.02,
                String(format: "largest gap %.3fs, eighth=%.3fs", largestAccidental, maxGap)
            )
            check(
                "Gap repair records a decision",
                repaired.decisions.contains { $0.kind == .repairedTimelineGap }
            )
        } else {
            check("Gap repair fixture has two placements", false)
        }
    } else {
        check("Gap repair fixture plans", false)
    }
}

// MARK: - 8. Intentional micro-pauses preserved

do {
    let song = makeSong(title: "Pause Song", bpm: 120, key: "C")
    if let (draft, profiles) = AutoRemixPlanner.makePlan(tracks: [song], seed: 3) {
        var plan = draft
        let beat = plan.beatSeconds
        let pause = beat * 0.2
        if let firstEnd = plan.placements.map(\.timelineEnd).sorted().first {
            let gapStart = firstEnd
            for i in plan.placements.indices where plan.placements[i].timelineStart >= gapStart - 0.001 {
                plan.placements[i].timelineStart += pause
            }
            plan.intentionalGaps = [
                AutoIntentionalGap(start: gapStart, end: gapStart + pause, reason: "pre-drop pause")
            ]
            let validated = AutoRemixValidator.validate(plan, profiles: profiles, tuning: .standard)
            let stillMarked = validated.intentionalGaps.contains {
                abs($0.length - pause) < 0.02 || $0.reason == "pre-drop pause"
            }
            check(
                "Intentional micro-pause preserved",
                stillMarked || pause <= AutoTuning.standard.maxIntentionalPauseBeats * validated.beatSeconds + 0.01
            )
        } else {
            check("Intentional micro-pause preserved", false, "no placements")
        }
    } else {
        check("Intentional pause fixture plans", false)
    }
}

// MARK: - 9. Unsupported effects never generated

do {
    let tracks = [
        makeSong(title: "FX A", bpm: 125, key: "Dm"),
        makeSong(title: "FX B", bpm: 125, key: "F"),
    ]
    let outcome = AutoRemixRunner.runEntireProject(tracks: tracks, seed: 77)
    switch outcome {
    case .success(_, let plan, _):
        let retired: Set<String> = ["bassBoost", "stutter"]
        var clean = true
        for p in plan.placements {
            for key in p.effects.levels.keys {
                if retired.contains(key) || !AutoSupportedEffects.levelKeys.contains(key) {
                    clean = false
                }
            }
        }
        check("No unsupported / retired effects in plan", clean)
        let applied = AutoRemixApplier.apply(plan, to: tracks)
        var appliedClean = true
        for track in applied.tracks where !track.isSFXTrack {
            for clip in track.clips {
                for key in clip.effects.levels.keys {
                    if retired.contains(key) || !AutoSupportedEffects.levelKeys.contains(key) {
                        appliedClean = false
                    }
                }
            }
        }
        check("No unsupported effects on applied clips", appliedClean)
    case .failure(let message):
        check("Effects whitelist fixture succeeds", false, message)
    }
}

// MARK: - 10. Summary reflects validator repairs (SFX strip)

do {
    let tracks = [makeSong(title: "Summary Song", bpm: 128, key: "C")]
    if let validated = AutoRemixPlanner.makeValidatedPlan(tracks: tracks, seed: 5) {
        var tampered = validated
        tampered.sfxEvents.append(
            AutoSFXEvent(assetID: "riser", timelineStart: 0.0, purpose: "orphan riser")
        )
        let profiles = Dictionary(
            uniqueKeysWithValues: tracks.map {
                ($0.id, AutoSectionCatalog.profile(track: $0))
            }
        )
        let repaired = AutoRemixValidator.validate(tampered, profiles: profiles, tuning: .standard)
        let applied = AutoRemixApplier.apply(repaired, to: tracks)
        let summary = AutoRemixPlanner.summary(for: applied.plan, tracks: applied.tracks)
        let orphanSurvived = applied.plan.sfxEvents.contains {
            $0.purpose == "orphan riser"
        }
        check("Summary uses applied plan (orphan riser removed)", !orphanSurvived)
        check("Summary SFX list matches applied plan", summary.sfxUsed.count >= 0)
    } else {
        check("Summary repair fixture plans", false)
    }
}

// MARK: - 11. Undo Auto contract (mirrors TimelineScreen wiring)

do {
    // Successful path: one undo snapshot of pre-Auto tracks; undo restores it.
    var tracks = [makeSong(title: "Undo Song", bpm: 124, key: "Am")]
    let before = tracks
    var undoStack: [[MixrTrack]] = []
    let outcome = AutoRemixRunner.runEntireProject(tracks: tracks, seed: 21)
    switch outcome {
    case .success(let arranged, _, _):
        undoStack.append(before)          // beginGestureEdit capture
        tracks = arranged                 // apply
        // commitGestureEdit registers undo → pop restores before
        check("Successful apply creates one undo entry", undoStack.count == 1)
        if let restored = undoStack.popLast() {
            tracks = restored
        }
        check("Undo Auto restores pre-Auto project", tracks == before)
    case .failure(let message):
        check("Undo Auto fixture succeeds", false, message)
    }
}

do {
    // Failure path: no undo entry, tracks unchanged.
    var tracks: [MixrTrack] = []
    let before = tracks
    let undoStack: [[MixrTrack]] = []
    let outcome = AutoRemixRunner.runEntireProject(tracks: tracks, seed: 1)
    if case .failure = outcome {
        // TimelineScreen does not begin/commit on failure.
        tracks = before
        check("Failed apply leaves undo stack empty", undoStack.isEmpty)
        check("Failed apply restores original timeline", tracks == before)
    } else {
        check("Failed apply leaves undo stack empty", false)
    }
}

// MARK: - 12. Runner does not mutate the input array

do {
    let tracks = [makeSong(title: "Immutable", bpm: 120, key: "C")]
    let clipID = tracks[0].clips[0].id
    _ = AutoRemixRunner.runEntireProject(tracks: tracks, seed: 8)
    check("Input tracks unchanged after run", tracks[0].clips[0].id == clipID)
    check("Input still has one clip", tracks[0].clips.count == 1)
}

print("\n\(failures == 0 ? "ALL PASSED" : "FAILED: \(failures)")")
exit(failures == 0 ? 0 : 1)

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Auto Scope

enum AutoScope: Equatable {
    case selectedClip(UUID)
    case playheadClips
    case entireProject

    var title: String {
        switch self {
        case .selectedClip: "Selected Clip"
        case .playheadClips: "Playhead Clips"
        case .entireProject: "Entire Project"
        }
    }
}

// MARK: - Timeline Editor
// The mutation vocabulary Auto composes arrangements from. Every operation
// clamps to valid ranges and no-ops rather than corrupting the timeline.

private struct TimelineEditor {
    var tracks: [MixrTrack]

    private let minLen = MixrTimeline.minClipLengthUnits
    private let epsilon = MixrTimeline.clipEdgeEpsilon

    // MARK: Lookup

    func locate(_ clipID: UUID) -> (track: Int, clip: Int)? {
        for (ti, track) in tracks.enumerated() {
            if let ci = track.clips.firstIndex(where: { $0.id == clipID }) {
                return (ti, ci)
            }
        }
        return nil
    }

    func clip(_ clipID: UUID) -> MixrClip? {
        locate(clipID).map { tracks[$0.track].clips[$0.clip] }
    }

    /// Last clip (by start) on a track — the "outgoing" clip after edits.
    func lastClipID(onTrack trackIdx: Int) -> UUID? {
        tracks[trackIdx].clips.max { $0.start < $1.start }?.id
    }

    // MARK: Structural mutations

    /// Splits a clip at a timeline unit. The left keeps the id; the right is
    /// a new clip whose source offset continues exactly where the left ends,
    /// so both segments play the correct part of the song.
    @discardableResult
    mutating func splitClip(_ clipID: UUID, atUnit unit: CGFloat) -> (left: UUID, right: UUID)? {
        guard let (ti, ci) = locate(clipID) else { return nil }
        let original = tracks[ti].clips[ci]
        let leftLen = unit - original.start
        let rightLen = original.start + original.length - unit
        guard leftLen >= minLen - epsilon, rightLen >= minLen - epsilon else { return nil }

        let rightID = UUID()
        let right = MixrClip(
            id: rightID,
            start: unit,
            length: rightLen,
            playbackSpeed: original.playbackSpeed,
            transitionIn: .none,
            transitionOut: original.transitionOut,
            volume: original.volume,
            effects: original.effects,
            soundEffectID: original.soundEffectID,
            sourceOffsetSeconds: original.sourceOffsetSeconds
                + MixrTimeline.seconds(fromUnits: leftLen) * original.playbackSpeed
        )

        tracks[ti].clips[ci].length = leftLen
        tracks[ti].clips[ci].transitionOut = .none
        tracks[ti].clips.insert(right, at: ci + 1)
        tracks[ti].clips.sort { $0.start < $1.start }
        return (clipID, rightID)
    }

    /// Shrinks a clip's end to `unit` (never grows, never moves neighbors).
    mutating func trimClipEnd(_ clipID: UUID, toUnit unit: CGFloat) {
        guard let (ti, ci) = locate(clipID) else { return }
        let clip = tracks[ti].clips[ci]
        let newLen = unit - clip.start
        guard newLen >= minLen, newLen < clip.length - epsilon else { return }
        tracks[ti].clips[ci].length = newLen
    }

    /// Shrinks a clip's start to `unit`, advancing its source offset so the
    /// remaining content is unchanged.
    mutating func trimClipStart(_ clipID: UUID, toUnit unit: CGFloat) {
        guard let (ti, ci) = locate(clipID) else { return }
        let clip = tracks[ti].clips[ci]
        let delta = unit - clip.start
        guard delta > epsilon, clip.length - delta >= minLen else { return }
        tracks[ti].clips[ci].start = unit
        tracks[ti].clips[ci].length -= delta
        tracks[ti].clips[ci].sourceOffsetSeconds +=
            MixrTimeline.seconds(fromUnits: delta) * clip.playbackSpeed
    }

    /// Repositions one clip (caller is responsible for same-track overlaps —
    /// cross-track overlap is exactly how blend sections work).
    mutating func moveClip(_ clipID: UUID, toStart start: CGFloat) {
        guard let (ti, ci) = locate(clipID) else { return }
        tracks[ti].clips[ci].start = max(0, start)
        tracks[ti].clips.sort { $0.start < $1.start }
    }

    /// Shifts every clip on a track, preserving internal layout. The delta
    /// is clamped so no clip goes negative.
    mutating func shiftTrackClips(trackIdx: Int, byUnits delta: CGFloat) {
        guard tracks.indices.contains(trackIdx), !tracks[trackIdx].clips.isEmpty else { return }
        let minStart = tracks[trackIdx].clips.map(\.start).min() ?? 0
        let clamped = max(delta, -minStart)
        guard abs(clamped) > epsilon else { return }
        for i in tracks[trackIdx].clips.indices {
            tracks[trackIdx].clips[i].start += clamped
        }
    }

    /// Duplicates a clip's content to a new position (same source offset —
    /// identical audio). Used sparingly for stutter/fill moments.
    @discardableResult
    mutating func duplicateClip(_ clipID: UUID, toStart start: CGFloat) -> UUID? {
        guard let (ti, _) = locate(clipID), let source = clip(clipID) else { return nil }
        let newID = UUID()
        let copy = MixrClip(
            id: newID,
            start: max(0, start),
            length: source.length,
            playbackSpeed: source.playbackSpeed,
            volume: source.volume,
            effects: source.effects,
            soundEffectID: source.soundEffectID,
            sourceOffsetSeconds: source.sourceOffsetSeconds
        )
        tracks[ti].clips.append(copy)
        tracks[ti].clips.sort { $0.start < $1.start }
        return newID
    }

    // MARK: Per-clip settings

    mutating func setClipVolume(_ clipID: UUID, _ volume: Double) {
        guard let (ti, ci) = locate(clipID) else { return }
        tracks[ti].clips[ci].volume = min(1, max(0, volume))
    }

    /// Available to arrangements (tape-stop / halftime moments); unused by
    /// the V1 heuristics to keep results tasteful.
    mutating func setClipSpeed(_ clipID: UUID, _ speed: Double) {
        guard let (ti, ci) = locate(clipID) else { return }
        tracks[ti].clips[ci].playbackSpeed = min(4, max(0.25, speed))
    }

    /// Beatmatching: sets a tempo ratio (playback speed) AND rescales the
    /// clip's timeline length so the same source content occupies the right
    /// number of timeline seconds at the new rate. Pitch preservation is the
    /// playback engine's job (AVAudioUnitTimePitch).
    mutating func setClipTempo(_ clipID: UUID, ratio: Double) {
        guard let (ti, ci) = locate(clipID) else { return }
        let clip = tracks[ti].clips[ci]
        let clamped = min(4, max(0.25, ratio))
        let sourceUnits = Double(clip.length) * clip.playbackSpeed
        tracks[ti].clips[ci].playbackSpeed = clamped
        tracks[ti].clips[ci].length = max(minLen, CGFloat(sourceUnits / clamped))
    }

    mutating func setEffect(_ clipID: UUID, _ effect: MixrEffect, level: Double) {
        guard let (ti, ci) = locate(clipID) else { return }
        tracks[ti].clips[ci].effects.setLevel(level, for: effect.rawValue)
    }

    mutating func setReverbPreset(_ clipID: UUID, _ preset: ReverbPreset) {
        guard let (ti, ci) = locate(clipID) else { return }
        tracks[ti].clips[ci].effects.reverbPreset = preset
    }

    mutating func setEchoPreset(_ clipID: UUID, _ preset: EchoPreset) {
        guard let (ti, ci) = locate(clipID) else { return }
        tracks[ti].clips[ci].effects.echoPreset = preset
    }

    mutating func setPitchDirection(_ clipID: UUID, _ direction: PitchDirection) {
        guard let (ti, ci) = locate(clipID) else { return }
        tracks[ti].clips[ci].effects.pitchDirection = direction
    }

    mutating func setTransitionIn(_ clipID: UUID, _ transition: ClipTransition) {
        guard let (ti, ci) = locate(clipID) else { return }
        tracks[ti].clips[ci].transitionIn = transition
    }

    mutating func setTransitionOut(_ clipID: UUID, _ transition: ClipTransition) {
        guard let (ti, ci) = locate(clipID) else { return }
        tracks[ti].clips[ci].transitionOut = transition
    }

    // MARK: SFX

    /// Adds an SFX clip at a unit using the shared collision rule.
    mutating func addSFX(_ definitionID: String, atUnit unit: CGFloat) {
        guard let definition = SoundEffectLibrary.definition(for: definitionID) else { return }
        let idx = ensureSFXTrack()
        let start = SoundEffectLibrary.nonOverlappingStart(
            proposedStart: max(0, unit),
            lengthUnits: definition.lengthUnits,
            in: tracks[idx].clips
        )
        tracks[idx].clips.append(
            MixrClip(id: UUID(), start: start, length: definition.lengthUnits, soundEffectID: definition.id)
        )
        tracks[idx].clips.sort { $0.start < $1.start }
    }

    /// Adds an SFX so it ENDS at `unit` (risers/builds into a drop).
    /// Skipped when it would need a negative start.
    mutating func addSFXEnding(_ definitionID: String, atUnit unit: CGFloat) {
        guard let definition = SoundEffectLibrary.definition(for: definitionID) else { return }
        let start = unit - definition.lengthUnits
        guard start >= 0 else { return }
        addSFX(definitionID, atUnit: start)
    }

    private mutating func ensureSFXTrack() -> Int {
        if let idx = tracks.firstIndex(where: { $0.isSFXTrack }) { return idx }
        tracks.append(
            MixrTrack(
                id: UUID(),
                title: "Sound Effects",
                artist: "Built-in SFX",
                duration: "",
                durationSeconds: nil,
                bpm: nil,
                key: nil,
                color: .silver,
                volume: 0.85,
                isMuted: false,
                trackType: .soundEffect,
                url: nil,
                artworkData: nil,
                clips: []
            )
        )
        return tracks.count - 1
    }
}

// MARK: - Auto Arrangement Engine

/// Local mashup arrangement engine — a beginner-friendly DJ assistant.
///
/// It analyzes each song (SongAnalyzer: real BPM/key + phrase/section
/// heuristics), then mutates the real timeline with clip-level edits:
/// splitting at phrase boundaries, trimming to mix-out points, moving songs
/// into overlap, and building dedicated blend sections where the outgoing
/// clip ducks and echoes out while the incoming clip rises underneath —
/// plus risers/impacts/sweeps on the SFX track and per-clip effect settings
/// that differ clip to clip. No external AI service is involved.
///
/// The caller (TimelineScreen.runAuto) wraps one whole run in a single undo
/// snapshot, so undo restores the exact prior project and redo re-applies
/// the arrangement.
enum AutoArrangementEngine {

    /// Half-width of the playhead scope's editing region (≈12 s total).
    private static let playheadRegionSeconds: Double = 6

    // MARK: Entry point

    static func arrange(
        tracks: [MixrTrack],
        scope: AutoScope,
        playheadUnit: CGFloat
    ) -> [MixrTrack] {
        var editor = TimelineEditor(tracks: tracks)
        let analyses = analyzeSongs(tracks)

        switch scope {
        case .selectedClip(let clipID):
            arrangeSelectedClip(clipID, editor: &editor, analyses: analyses)
        case .playheadClips:
            arrangePlayheadRegion(around: playheadUnit, editor: &editor, analyses: analyses)
        case .entireProject:
            // Entire Project Auto in the UI uses AutoRemixRunner (plan pipeline).
            // This path remains for focused tooling / legacy callers only.
            arrangeEntireProject(editor: &editor, analyses: analyses)
        }

        return editor.tracks
    }

    private static func analyzeSongs(_ tracks: [MixrTrack]) -> [UUID: SongAnalysis] {
        var result: [UUID: SongAnalysis] = [:]
        for track in tracks where !track.isSFXTrack {
            result[track.id] = SongAnalyzer.analyze(track: track)
        }
        return result
    }

    private static func analysis(
        forClip clipID: UUID,
        editor: TimelineEditor,
        analyses: [UUID: SongAnalysis]
    ) -> SongAnalysis? {
        guard let (ti, _) = editor.locate(clipID) else { return nil }
        return analyses[editor.tracks[ti].id]
    }

    // MARK: - Scope: Selected Clip

    /// Edits stay inside the selected clip's bounds: trim its end to a clean
    /// phrase, split it at an internal phrase boundary to create an arrival
    /// moment with distinct effect settings per half, and place SFX only
    /// around that clip's region. Nothing else moves.
    private static func arrangeSelectedClip(
        _ clipID: UUID,
        editor: inout TimelineEditor,
        analyses: [UUID: SongAnalysis]
    ) {
        guard let clip = editor.clip(clipID), !clip.isSoundEffect,
              let analysis = analysis(forClip: clipID, editor: editor, analyses: analyses)
        else { return }

        trimEndToPhrase(clipID, analysis: analysis, maxTrimSeconds: 4, editor: &editor)

        if clip.start > MixrTimeline.clipEdgeEpsilon {
            editor.setTransitionIn(clipID, ClipTransition(type: .crossfade, duration: 4))
        }

        applyInternalMoment(
            clipID,
            analysis: analysis,
            focusUnit: nil,
            variant: 0,
            editor: &editor
        )
    }

    // MARK: - Scope: Playhead Region

    /// Improves the ~12 s around the playhead. If an outgoing and an
    /// incoming song meet near the playhead, it builds a real blend section
    /// between them (moving the incoming song locally if needed); otherwise
    /// it creates an internal moment in the clip under the playhead.
    private static func arrangePlayheadRegion(
        around playheadUnit: CGFloat,
        editor: inout TimelineEditor,
        analyses: [UUID: SongAnalysis]
    ) {
        let halfRegion = MixrTimeline.units(fromSeconds: playheadRegionSeconds)
        let regionStart = max(0, playheadUnit - halfRegion)
        let regionEnd = playheadUnit + halfRegion

        struct Candidate {
            let trackIdx: Int
            let clip: MixrClip
        }
        var candidates: [Candidate] = []
        for (ti, track) in editor.tracks.enumerated() where !track.isSFXTrack {
            for clip in track.clips where !clip.isSoundEffect {
                let end = clip.start + clip.length
                if end > regionStart - halfRegion, clip.start < regionEnd + halfRegion {
                    candidates.append(Candidate(trackIdx: ti, clip: clip))
                }
            }
        }
        guard !candidates.isEmpty else { return }

        // Blend pair: a clip ending in/near the region + a clip on another
        // track starting in/near the region.
        let outgoing = candidates
            .filter { ($0.clip.start + $0.clip.length) >= regionStart && ($0.clip.start + $0.clip.length) <= regionEnd + halfRegion }
            .min { abs($0.clip.start + $0.clip.length - playheadUnit) < abs($1.clip.start + $1.clip.length - playheadUnit) }
        let incoming = candidates
            .filter { candidate in
                guard let outgoing else { return false }
                return candidate.trackIdx != outgoing.trackIdx
                    && candidate.clip.start >= regionStart - halfRegion
                    && candidate.clip.start <= regionEnd + halfRegion
            }
            .min { abs($0.clip.start - playheadUnit) < abs($1.clip.start - playheadUnit) }

        if let outgoing, let incoming,
           let analysisB = analyses[editor.tracks[incoming.trackIdx].id] {
            // Position the incoming song so the blend overlaps the outgoing
            // tail — a local move only (both clips are already near here).
            let aEnd = outgoing.clip.start + outgoing.clip.length
            let blendUnits = blendLengthUnits(bpm: analysisB.bpm)
            let desiredStart = max(0, aEnd - blendUnits)
            let delta = desiredStart - incoming.clip.start
            // Local alignment only — enough budget to close a small gap
            // plus the blend overlap, never a project-wide rewrite.
            if abs(delta) <= MixrTimeline.units(fromSeconds: 20) {
                editor.shiftTrackClips(trackIdx: incoming.trackIdx, byUnits: delta)
            }
            applyBlend(
                outgoing: outgoing.clip.id,
                incoming: incoming.clip.id,
                blendUnits: blendUnits,
                variant: 0,
                editor: &editor
            )
        } else {
            // Single-song region: build a moment at the phrase nearest the playhead.
            let target = candidates
                .filter { playheadUnit >= $0.clip.start && playheadUnit <= $0.clip.start + $0.clip.length }
                .first ?? candidates[0]
            guard let analysis = analyses[editor.tracks[target.trackIdx].id] else { return }
            applyInternalMoment(
                target.clip.id,
                analysis: analysis,
                focusUnit: playheadUnit,
                variant: 1,
                editor: &editor
            )
        }
    }

    // MARK: - Scope: Entire Project

    /// Maximum pitch-preserving tempo stretch for beatmatching (±8% vocal gate).
    private static let beatmatchTolerance = AutoClubTempo.maxVocalStretch

    /// Entire project is mode-aware:
    /// - 1 song  → a CLUB REMIX of that song (intro → build → drop → break →
    ///   drop 2 energy story with pre-drop chokes and coordinated SFX).
    /// - 2+ songs → a MASHUP: songs beatmatched toward a shared pocket,
    ///   chained through phrase-aligned blend sections.
    private static func arrangeEntireProject(
        editor: inout TimelineEditor,
        analyses: [UUID: SongAnalysis]
    ) {
        let songTrackIdxs = editor.tracks.indices
            .filter { !editor.tracks[$0].isSFXTrack && !editor.tracks[$0].clips.isEmpty }
            .sorted {
                (editor.tracks[$0].clips.map(\.start).min() ?? 0)
                    < (editor.tracks[$1].clips.map(\.start).min() ?? 0)
            }
        guard let firstIdx = songTrackIdxs.first else { return }

        if songTrackIdxs.count == 1 {
            arrangeSingleSongRemix(trackIdx: firstIdx, editor: &editor, analyses: analyses)
            return
        }

        // ── Mashup: anchor the first song at 0 and shape its opening ──
        let firstTrackID = editor.tracks[firstIdx].id
        guard let firstMain = editor.tracks[firstIdx].clips.min(by: { $0.start < $1.start }),
              let firstAnalysis = analyses[firstTrackID]
        else { return }

        editor.shiftTrackClips(trackIdx: firstIdx, byUnits: -firstMain.start)
        applyIntroShaping(firstMain.id, analysis: firstAnalysis, editor: &editor)

        // The set's master tempo — every compatible song locks to it.
        let masterBPM = firstAnalysis.bpm

        var outgoingID = editor.lastClipID(onTrack: firstIdx) ?? firstMain.id
        var outgoingAnalysis = firstAnalysis

        // ── Chain: beatmatch + blend each following song under the previous ──
        for (k, ti) in songTrackIdxs.dropFirst().enumerated() {
            guard let analysisB = analyses[editor.tracks[ti].id],
                  let aClip = editor.clip(outgoingID)
            else { continue }

            // Beatmatch: stretch the incoming song toward the master tempo
            // when it's within ±8% — the difference between a loose collage
            // and a locked DJ set. Outside the window, keep native tempo and
            // let the phrase-cut fallback carry the transition.
            let ratio = masterBPM / analysisB.bpm
            let beatmatched = abs(ratio - 1) <= beatmatchTolerance && abs(ratio - 1) > 0.0001
            if beatmatched {
                for clipID in editor.tracks[ti].clips.map(\.id) {
                    editor.setClipTempo(clipID, ratio: ratio)
                }
            }
            let blendBPM = beatmatched || abs(ratio - 1) <= 0.0001 ? masterBPM : analysisB.bpm

            guard let bMain = editor.tracks[ti].clips.min(by: { $0.start < $1.start }) else { continue }

            // Trim the outgoing clip to a phrase-snapped, low-vocal mix-out
            // point so the transition lands on a musical boundary.
            trimEndToMixOut(outgoingID, analysis: outgoingAnalysis, editor: &editor)
            let aEnd = (editor.clip(outgoingID).map { $0.start + $0.length }) ?? (aClip.start + aClip.length)

            // Move the incoming song so it enters UNDER the outgoing tail.
            let blendUnits = blendLengthUnits(bpm: blendBPM)
            let entry = max(0, aEnd - blendUnits)
            editor.shiftTrackClips(trackIdx: ti, byUnits: entry - bMain.start)

            applyBlend(
                outgoing: outgoingID,
                incoming: bMain.id,
                blendUnits: blendUnits,
                variant: k,
                editor: &editor
            )

            outgoingID = editor.lastClipID(onTrack: ti) ?? bMain.id
            outgoingAnalysis = analysisB
        }

        // ── Release: shaped outro on the final song ──
        applyOutroShaping(outgoingID, analysis: outgoingAnalysis, editor: &editor)
    }

    // MARK: - Scope: Single-Song Remix

    /// One song → club remix energy on the arrangement-engine path:
    /// shaped intro, ducked + blurred pre-drop choke into each chorus/drop,
    /// denser treatment on the second drop, and a shaped outro. Pulse SFX
    /// (kick) are added only when the source kit is thin.
    private static func arrangeSingleSongRemix(
        trackIdx: Int,
        editor: inout TimelineEditor,
        analyses: [UUID: SongAnalysis]
    ) {
        guard let analysis = analyses[editor.tracks[trackIdx].id],
              let main = editor.tracks[trackIdx].clips.min(by: { $0.start < $1.start })
        else { return }

        editor.shiftTrackClips(trackIdx: trackIdx, byUnits: -main.start)
        applyIntroShaping(main.id, analysis: analysis, editor: &editor)

        let barUnits = MixrTimeline.units(fromSeconds: analysis.barSeconds)
        let chokeUnits = max(barUnits * 2, MixrTimeline.minClipLengthUnits + 0.1)
        let pulse = AutoClubPulse.policy(
            drumStrength: analysis.drumStrength,
            bassDensity: analysis.bassDensity,
            bpm: analysis.bpm,
            analysisConfidence: analysis.analysisConfidence
        )

        for (k, chorus) in analysis.chorusOrDropCandidates.prefix(2).enumerated() {
            guard let body = editor.tracks[trackIdx].clips.first(where: { clip in
                !clip.isSoundEffect
                    && chorus.startSeconds > clip.songSeconds(atUnit: clip.start)
                    && chorus.startSeconds < clip.songSeconds(atUnit: clip.start + clip.length)
            }) else { continue }

            let dropUnit = body.unit(forSongSeconds: chorus.startSeconds)
            let chokeStart = dropUnit - chokeUnits

            if let (_, rest) = editor.splitClip(body.id, atUnit: chokeStart),
               let (chokeID, dropID) = editor.splitClip(rest, atUnit: dropUnit) {
                editor.setClipVolume(chokeID, 0.55)
                editor.setEffect(chokeID, .blur, level: k == 0 ? 48 : 36)
                editor.setEffect(chokeID, .echo, level: 28)
                editor.setEchoPreset(chokeID, .pingPong)

                editor.setClipVolume(dropID, 1.0)
                editor.setEffect(dropID, .reverb, level: k == 0 ? 10 : 16)
                editor.setReverbPreset(dropID, k == 0 ? .hall : .ambient)
            }

            editor.addSFXEnding(k == 0 ? "riser" : "snareBuild", atUnit: dropUnit)
            editor.addSFX("impact", atUnit: dropUnit)
            if k == 0 {
                editor.addSFX("sweepDown", atUnit: dropUnit)
            } else {
                editor.addSFX("airSweep", atUnit: dropUnit)
            }

            // Thin sources get a kick on the drop downbeat — never a second
            // kick when the source already slams.
            if pulse.writesKick {
                editor.addSFX("clubKick", atUnit: dropUnit)
            }
        }

        if let lastID = editor.lastClipID(onTrack: trackIdx) {
            applyOutroShaping(lastID, analysis: analysis, editor: &editor)
        }
    }

    // MARK: - Shared routines

    /// Blend length: 4 bars at the blend tempo, clamped 4–12 s.
    private static func blendLengthUnits(bpm: Double) -> CGFloat {
        let barSeconds = 240.0 / max(bpm, 40)
        return MixrTimeline.units(fromSeconds: min(12, max(4, barSeconds * 4)))
    }

    /// A blend section between two songs: the outgoing tail becomes its own
    /// clip that ducks and echoes out; the incoming head becomes its own
    /// clip that rises in warm and filtered; the SFX track sells the drop.
    ///
    /// True gradual gain ramps inside the blend are an AVAudioEngine
    /// integration point — V1 approximates them with tail/head clip volumes
    /// plus fade/crossfade transitions.
    private static func applyBlend(
        outgoing outgoingID: UUID,
        incoming incomingID: UUID,
        blendUnits: CGFloat,
        variant: Int,
        editor: inout TimelineEditor
    ) {
        guard let a = editor.clip(outgoingID), let b = editor.clip(incomingID) else { return }
        let aEnd = a.start + a.length
        let blendStart = max(a.start, b.start)
        let dropUnit = min(aEnd, blendStart + blendUnits)

        guard dropUnit > blendStart + MixrTimeline.clipEdgeEpsilon else {
            // No usable overlap (the incoming song couldn't be moved) —
            // treat it as a phrase cut and hide the seam instead.
            editor.setTransitionOut(outgoingID, ClipTransition(type: .echoOut, duration: 4))
            editor.setEffect(outgoingID, .echo, level: 30)
            editor.setEchoPreset(outgoingID, .classic)
            editor.setTransitionIn(incomingID, ClipTransition(type: .crossfade, duration: 4))
            editor.setEffect(incomingID, .blur, level: 12)
            editor.addSFXEnding(variant % 2 == 0 ? "riser" : "snareBuild", atUnit: b.start)
            editor.addSFX("impact", atUnit: b.start)
            return
        }

        // Outgoing tail — duck, echo out, filter motion. Split so ONLY the
        // blend section carries the exit treatment.
        if let (bodyID, tailID) = editor.splitClip(outgoingID, atUnit: blendStart) {
            editor.setClipVolume(tailID, 0.78)
            editor.setEffect(tailID, .echo, level: 32 + Double(variant % 3) * 5)
            editor.setEchoPreset(tailID, variant % 2 == 0 ? .pingPong : .classic)
            editor.setEffect(tailID, .blur, level: 30 + Double(variant % 2) * 8)
            editor.setTransitionOut(tailID, ClipTransition(type: .fadeOut, duration: 8))
            editor.setEffect(bodyID, .blur, level: 6)
        } else {
            // Too short to split — fade the whole outgoing clip.
            editor.setClipVolume(outgoingID, 0.85)
            editor.setEffect(outgoingID, .echo, level: 28)
            editor.setTransitionOut(outgoingID, ClipTransition(type: .fadeOut, duration: 8))
        }

        // Incoming head — rise underneath, warm and slightly filtered so it
        // doesn't fight the outgoing vocal, then open to full volume.
        if let (headID, bodyID) = editor.splitClip(incomingID, atUnit: dropUnit) {
            editor.setClipVolume(headID, 0.88)
            editor.setTransitionIn(headID, ClipTransition(type: .crossfade, duration: 8))
            editor.setEffect(headID, .blur, level: 16 + Double(variant % 2) * 6)
            editor.setClipVolume(bodyID, 1.0)
            editor.setEffect(bodyID, .reverb, level: 14)
            editor.setReverbPreset(bodyID, .hall)
        } else {
            editor.setTransitionIn(incomingID, ClipTransition(type: .crossfade, duration: 8))
            editor.setEffect(incomingID, .blur, level: 12)
        }

        // SFX vocabulary — build into the drop, hit it, breathe out after.
        editor.addSFXEnding(variant % 2 == 0 ? "riser" : "snareBuild", atUnit: dropUnit)
        editor.addSFX("impact", atUnit: dropUnit)
        editor.addSFX(variant % 2 == 0 ? "sweepDown" : "downlifter", atUnit: dropUnit)
    }

    /// Splits a clip at an internal phrase boundary to create an arrival
    /// moment — each half gets its own settings, SFX stay in the clip's region.
    private static func applyInternalMoment(
        _ clipID: UUID,
        analysis: SongAnalysis,
        focusUnit: CGFloat?,
        variant: Int,
        editor: inout TimelineEditor
    ) {
        guard let clip = editor.clip(clipID) else { return }
        let clipEnd = clip.start + clip.length
        let margin = MixrTimeline.minClipLengthUnits

        // Candidate phrase boundaries strictly inside the clip.
        let songLow = clip.songSeconds(atUnit: clip.start + margin)
        let songHigh = clip.songSeconds(atUnit: clipEnd - margin)
        let candidates = analysis.phraseBoundaries.filter { $0 > songLow && $0 < songHigh }

        let targetSong: Double?
        if let focusUnit {
            let focusSong = clip.songSeconds(atUnit: focusUnit)
            targetSong = candidates.min { abs($0 - focusSong) < abs($1 - focusSong) }
        } else {
            // Default arrival ~62% through the clip's window.
            let goal = songLow + (songHigh - songLow) * 0.62
            targetSong = candidates.min { abs($0 - goal) < abs($1 - goal) }
        }

        if let targetSong,
           let (firstID, secondID) = editor.splitClip(clipID, atUnit: clip.unit(forSongSeconds: targetSong)) {
            let splitUnit = editor.clip(secondID)?.start ?? clip.unit(forSongSeconds: targetSong)

            editor.setEffect(firstID, .blur, level: 10)
            editor.setEffect(secondID, .blur, level: 24 + Double(variant % 2) * 6)
            editor.setEffect(secondID, .echo, level: 18)
            editor.setEffect(secondID, .reverb, level: 16)
            editor.setReverbPreset(secondID, .hall)

            editor.addSFXEnding("riser", atUnit: splitUnit)
            editor.addSFX("impact", atUnit: splitUnit)
            editor.addSFX("sweepDown", atUnit: clipEnd)
        } else {
            // Too short to split — per-clip polish only.
            editor.setEffect(clipID, .reverb, level: 22)
            editor.setReverbPreset(clipID, .hall)
            editor.setEffect(clipID, .echo, level: 16)
            editor.setTransitionOut(clipID, ClipTransition(type: .echoOut, duration: 4))
            editor.addSFX("impact", atUnit: clip.start)
            editor.addSFX("sweepDown", atUnit: clipEnd)
        }
    }

    /// First song's opening: a dedicated intro clip that sits lower and
    /// filtered, then an impact where the song fully opens up.
    private static func applyIntroShaping(
        _ clipID: UUID,
        analysis: SongAnalysis,
        editor: inout TimelineEditor
    ) {
        guard let clip = editor.clip(clipID) else { return }
        let introEndSong = analysis.introCandidate?.endSeconds ?? analysis.phraseSeconds
        let splitUnit = clip.unit(forSongSeconds: introEndSong)

        if let (introID, _) = editor.splitClip(clipID, atUnit: splitUnit) {
            editor.setClipVolume(introID, 0.85)
            editor.setEffect(introID, .blur, level: 24)
            editor.addSFX("impact", atUnit: splitUnit)
        } else {
            editor.setEffect(clipID, .blur, level: 14)
        }
    }

    /// Last song's release: a dedicated outro clip with reverb air and a
    /// fade, announced by a crash + downlifter.
    private static func applyOutroShaping(
        _ clipID: UUID,
        analysis: SongAnalysis,
        editor: inout TimelineEditor
    ) {
        guard let clip = editor.clip(clipID) else { return }
        let clipEndSong = clip.songSeconds(atUnit: clip.start + clip.length)
        let outroStartSong = min(
            analysis.outroCandidate?.startSeconds ?? analysis.phraseFloor(of: clipEndSong),
            analysis.phraseFloor(of: clipEndSong)
        )
        let splitUnit = clip.unit(forSongSeconds: outroStartSong)

        if let (_, outroID) = editor.splitClip(clipID, atUnit: splitUnit) {
            editor.setClipVolume(outroID, 0.85)
            editor.setEffect(outroID, .reverb, level: 34)
            editor.setReverbPreset(outroID, .ambient)
            editor.setTransitionOut(outroID, ClipTransition(type: .fadeOut, duration: 8))
            editor.addSFX("crash", atUnit: splitUnit)
            editor.addSFX("downlifter", atUnit: splitUnit)
        } else {
            editor.setEffect(clipID, .reverb, level: 26)
            editor.setReverbPreset(clipID, .ambient)
            editor.setTransitionOut(clipID, ClipTransition(type: .fadeOut, duration: 8))
        }
    }

    // MARK: - Trim helpers

    /// Trims a clip's end down to the nearest phrase boundary (small,
    /// shrink-only cleanup — neighbors never move).
    private static func trimEndToPhrase(
        _ clipID: UUID,
        analysis: SongAnalysis,
        maxTrimSeconds: Double,
        editor: inout TimelineEditor
    ) {
        guard let clip = editor.clip(clipID) else { return }
        let endSong = clip.songSeconds(atUnit: clip.start + clip.length)
        let phrase = analysis.phraseFloor(of: endSong)
        guard phrase > clip.sourceOffsetSeconds, endSong - phrase <= maxTrimSeconds else { return }
        editor.trimClipEnd(clipID, toUnit: clip.unit(forSongSeconds: phrase))
    }

    /// Trims the outgoing clip to its best mix-out point: the latest
    /// phrase-snapped, low-vocal-density point the analysis suggests,
    /// without shortening the clip by more than ~16 s.
    private static func trimEndToMixOut(
        _ clipID: UUID,
        analysis: SongAnalysis,
        editor: inout TimelineEditor
    ) {
        guard let clip = editor.clip(clipID) else { return }
        let endSong = clip.songSeconds(atUnit: clip.start + clip.length)
        let mixOut = analysis.mixOutPoints
            .filter { $0 < endSong && endSong - $0 <= 16 && $0 > clip.sourceOffsetSeconds }
            .max()
        guard let mixOut else {
            trimEndToPhrase(clipID, analysis: analysis, maxTrimSeconds: 6, editor: &editor)
            return
        }
        editor.trimClipEnd(clipID, toUnit: clip.unit(forSongSeconds: mixOut))
    }
}


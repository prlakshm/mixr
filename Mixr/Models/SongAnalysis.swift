#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Song Section

struct SongSection: Equatable, Sendable {
    enum Kind: String, Sendable {
        case intro
        case verse
        case build       // pre-chorus / riser bars leading into a chorus
        case chorus      // chorus or drop
        case bridge
        case instrumental
        case outro
    }

    let kind: Kind
    /// Seconds into the source audio.
    let startSeconds: Double
    let endSeconds: Double

    var durationSeconds: Double { endSeconds - startSeconds }

    func contains(_ seconds: Double) -> Bool {
        seconds >= startSeconds && seconds < endSeconds
    }
}

// MARK: - Song Analysis

/// Per-song musical understanding used by the Auto arrangement engine.
/// All times are seconds into the source audio.
///
/// V1 fills this with REAL data where the app already has it (BPM and key
/// from embedded metadata or MixrAudioAnalyzer's on-device estimation) and
/// deterministic phrase/section/energy heuristics everywhere else.
///
/// DSP / MIR integration points (replace heuristics, keep this shape):
///  - beatGrid / downbeats  → real beat tracking (onset + dynamic programming)
///  - vocalDensityCurve / lyricOrVocalMoments → vocal detection or source
///    separation (e.g. band-pass vocal presence, or a separation model)
///  - sectionCandidates      → self-similarity / novelty section detection
///  - energyCurve            → true short-time RMS from MixrAudioAnalyzer's
///    onset-energy pass (already computed there for BPM; expose it)
struct SongAnalysis: Sendable {
    var bpm: Double
    /// True when bpm came from metadata/analysis rather than the default.
    var bpmIsReal: Bool
    /// nil = trusted (metadata); 0…1 when estimated on-device.
    var bpmConfidence: Double?
    var key: String?
    /// nil = trusted (metadata); 0…1 when estimated on-device.
    var keyConfidence: Double?
    var durationSeconds: Double

    var beatGrid: [Double]
    var downbeats: [Double]
    /// 8-bar phrase starts — the musically safe edit points.
    var phraseBoundaries: [Double]

    var sectionCandidates: [SongSection]
    var introCandidate: SongSection?
    var verseCandidates: [SongSection]
    var chorusOrDropCandidates: [SongSection]
    /// Pre-chorus bars leading into each chorus/drop — riser real estate.
    var buildCandidates: [SongSection]
    var bridgeCandidate: SongSection?
    var outroCandidate: SongSection?
    var instrumentalCandidates: [SongSection]

    /// Normalized 0…1, sampled evenly across the song.
    var energyCurve: [Double]
    /// Normalized 0…1 — likelihood that vocals are active.
    var vocalDensityCurve: [Double]

    /// Good places to bring this song IN under another song.
    var mixInPoints: [Double]
    /// Good places to take this song OUT under an incoming song.
    var mixOutPoints: [Double]

    /// Salient vocal/lyric moments. Empty in V1 — requires vocal detection
    /// or lyric alignment (integration point above).
    var lyricOrVocalMoments: [Double]

    /// Song times where a recognizable hook most likely starts (chorus/drop
    /// entrances) — used for teasers and "lead with the hook" placement.
    var hookMoments: [Double]

    /// 0…1 estimate of drum/transient strength (rhythmic reliability).
    var drumStrength: Double
    /// 0…1 estimate of low-end density (drop-vs-drop clash avoidance).
    var bassDensity: Double
    /// 0…1 overall trust in this analysis (beat grid + key + duration).
    /// Below ~0.5 the Auto planner switches to its safe fallback behavior.
    var analysisConfidence: Double

    /// Real signal-derived measurements when the source audio has been
    /// analyzed (nil = metadata/heuristics only, so editing must stay
    /// maximally conservative).
    var signal: SongSignalFeatures? = nil

    // MARK: Derived musical units

    var beatSeconds: Double { 60.0 / bpm }
    var barSeconds: Double { beatSeconds * 4 }
    var phraseSeconds: Double { barSeconds * 8 }

    // MARK: Queries

    /// Nearest phrase boundary to `seconds` (clamped into the song).
    func nearestPhrase(to seconds: Double) -> Double {
        phraseBoundaries.min { abs($0 - seconds) < abs($1 - seconds) } ?? 0
    }

    /// Largest phrase boundary ≤ `seconds`.
    func phraseFloor(of seconds: Double) -> Double {
        phraseBoundaries.last { $0 <= seconds } ?? 0
    }

    /// Sampled vocal density at a song time, 0…1.
    func vocalDensity(at seconds: Double) -> Double {
        sample(vocalDensityCurve, at: seconds)
    }

    /// Sampled energy at a song time, 0…1.
    func energy(at seconds: Double) -> Double {
        sample(energyCurve, at: seconds)
    }

    /// Mean energy over a source range, 0…1.
    func meanEnergy(from start: Double, to end: Double) -> Double {
        meanSample(energyCurve, from: start, to: end)
    }

    /// Mean vocal density over a source range, 0…1.
    func meanVocalDensity(from start: Double, to end: Double) -> Double {
        meanSample(vocalDensityCurve, from: start, to: end)
    }

    private func meanSample(_ curve: [Double], from start: Double, to end: Double) -> Double {
        guard end > start else { return sample(curve, at: start) }
        let steps = 8
        var total = 0.0
        for i in 0...steps {
            total += sample(curve, at: start + (end - start) * Double(i) / Double(steps))
        }
        return total / Double(steps + 1)
    }

    private func sample(_ curve: [Double], at seconds: Double) -> Double {
        guard !curve.isEmpty, durationSeconds > 0 else { return 0.5 }
        let t = min(max(seconds / durationSeconds, 0), 1)
        let idx = min(curve.count - 1, Int(t * Double(curve.count - 1)))
        return curve[idx]
    }
}

// MARK: - Analyzer (heuristic V1 builder)

enum SongAnalyzer {

    static let defaultBPM: Double = 124
    private static let curveSamples = 64

    /// Builds an analysis for one song track. Uses the track's real BPM/key
    /// when known (metadata or MixrAudioAnalyzer), real signal features
    /// when the audio has been measured, and deterministic heuristics
    /// only where no measurement exists.
    static func analyze(track: MixrTrack, signal: SongSignalFeatures? = nil) -> SongAnalysis {
        let bpm = track.bpm.map(Double.init) ?? defaultBPM
        let duration = track.durationSeconds
            ?? track.clips.first.map { MixrTimeline.seconds(fromUnits: $0.length) * $0.playbackSpeed }
            ?? 60

        let beat = 60.0 / bpm
        let bar = beat * 4
        let phrase = bar * 8
        let seed = stableSeed(track.title + track.artist)

        // Beat grid anchored to the MEASURED first downbeat when the
        // signal has one — source time zero is never assumed to be beat
        // one without evidence.
        let gridAnchor: Double
        if let signal, let firstDownbeat = signal.downbeatOffsetSeconds, signal.beatConfidence > 0.3 {
            gridAnchor = firstDownbeat.truncatingRemainder(dividingBy: beat)
        } else {
            gridAnchor = 0
        }
        let beatGrid = Array(stride(from: gridAnchor, to: duration, by: beat))
        let downbeatAnchor: Double
        if let signal, let firstDownbeat = signal.downbeatOffsetSeconds, signal.beatConfidence > 0.3 {
            downbeatAnchor = firstDownbeat.truncatingRemainder(dividingBy: bar)
        } else {
            downbeatAnchor = 0
        }
        let downbeats = Array(stride(from: downbeatAnchor, to: duration, by: bar))
        let phrases = Array(stride(from: downbeatAnchor, to: duration, by: phrase))

        // ── Section heuristics (phrase-snapped fractions of the song) ──
        func snap(_ t: Double) -> Double {
            phrases.last { $0 <= t } ?? 0
        }

        let introEnd = min(phrase * (duration > phrase * 6 ? 2 : 1), duration * 0.20)
        let intro = SongSection(kind: .intro, startSeconds: 0, endSeconds: max(4, snapOr(introEnd, phrases)))

        let outroStart = max(intro.endSeconds, snap(duration - phrase))
        let outro = SongSection(kind: .outro, startSeconds: outroStart, endSeconds: duration)

        let chorus1Start = max(intro.endSeconds, snap(duration * 0.28))
        var chorus1 = SongSection(
            kind: .chorus,
            startSeconds: chorus1Start,
            endSeconds: min(outro.startSeconds, chorus1Start + phrase)
        )
        let chorus2Start = max(chorus1.endSeconds, snap(duration * 0.60))
        var chorus2 = SongSection(
            kind: .chorus,
            startSeconds: chorus2Start,
            endSeconds: min(outro.startSeconds, chorus2Start + phrase)
        )

        // Measured title-chorus: duration-fraction `.first` often lands on a
        // repeated prechorus (Oops ~40.4s) not the title line (~46s).
        if let signal,
           let refined = AutoChorusIsland.refineChoruses(
               signal: signal,
               downbeats: downbeats,
               barSeconds: bar,
               phraseSeconds: phrase,
               duration: duration,
               introEnd: intro.endSeconds,
               outroStart: outro.startSeconds
           ) {
            chorus1 = refined.0
            chorus2 = refined.1
        }

        let bridgeStart = max(chorus2.endSeconds, snap(duration * 0.76))
        let bridge = bridgeStart < outro.startSeconds - bar
            ? SongSection(kind: .bridge, startSeconds: bridgeStart, endSeconds: min(outro.startSeconds, bridgeStart + phrase))
            : nil

        var verses: [SongSection] = []
        if intro.endSeconds < chorus1.startSeconds {
            verses.append(SongSection(kind: .verse, startSeconds: intro.endSeconds, endSeconds: chorus1.startSeconds))
        }
        if chorus1.endSeconds < chorus2.startSeconds {
            verses.append(SongSection(kind: .verse, startSeconds: chorus1.endSeconds, endSeconds: chorus2.startSeconds))
        }

        var instrumentals: [SongSection] = [
            SongSection(kind: .instrumental, startSeconds: intro.startSeconds, endSeconds: intro.endSeconds),
            SongSection(kind: .instrumental, startSeconds: outro.startSeconds, endSeconds: outro.endSeconds),
        ]
        if let bridge {
            instrumentals.append(SongSection(kind: .instrumental, startSeconds: bridge.startSeconds, endSeconds: bridge.endSeconds))
        }

        // Pre-chorus builds: the 4 bars leading into each chorus entrance.
        let builds: [SongSection] = [chorus1, chorus2].compactMap { chorus in
            let start = chorus.startSeconds - bar * 4
            guard start >= intro.endSeconds - 0.01 else { return nil }
            return SongSection(kind: .build, startSeconds: start, endSeconds: chorus.startSeconds)
        }

        var sections: [SongSection] = [intro] + verses + [chorus1, chorus2] + (bridge.map { [$0] } ?? []) + [outro]
        sections.sort { $0.startSeconds < $1.startSeconds }

        // ── Energy & vocal-density curves ──
        // MEASURED when the signal was analyzed; heuristic shape otherwise.
        let energy: [Double]
        let vocals: [Double]
        if let signal, !signal.energyCurve.isEmpty {
            energy = resample(signal.energyCurve, to: curveSamples)
            vocals = signal.vocalPresenceCurve.isEmpty
                ? resample(signal.energyCurve, to: curveSamples)
                : resample(signal.vocalPresenceCurve, to: curveSamples)
        } else {
            energy = buildEnergyCurve(
                duration: duration,
                intro: intro, outro: outro,
                choruses: [chorus1, chorus2],
                bridge: bridge,
                seed: seed
            )
            vocals = buildVocalCurve(
                duration: duration,
                intro: intro, outro: outro,
                choruses: [chorus1, chorus2],
                bridge: bridge,
                verses: verses,
                seed: seed
            )
        }

        // ── Mix points: phrase boundaries in low-vocal regions ──
        func density(at t: Double) -> Double {
            guard duration > 0 else { return 0.5 }
            let idx = min(vocals.count - 1, Int(min(max(t / duration, 0), 1) * Double(vocals.count - 1)))
            return vocals[idx]
        }

        var mixIn = phrases
            .filter { $0 <= duration * 0.35 && density(at: $0 + bar) < 0.5 }
        if mixIn.isEmpty { mixIn = [0] }

        var mixOut = phrases
            .filter { $0 >= duration * 0.55 && density(at: $0 + bar) < 0.5 }
        if mixOut.isEmpty { mixOut = [snap(duration - phrase)] }
        mixOut = mixOut.filter { $0 > 0 }
        if mixOut.isEmpty { mixOut = [max(0, duration - phrase)] }

        // ── Trust estimates ──
        // BPM/key from metadata are fully trusted (confidence nil → 1.0);
        // on-device estimates carry their own confidence; a default BPM
        // means the beat grid is a guess and Auto must stay conservative.
        let bpmTrust: Double = track.bpm == nil ? 0.15 : (track.bpmConfidence ?? 1.0)
        let keyTrust: Double = track.key == nil ? 0.2 : (track.keyConfidence ?? 1.0)
        let durationTrust: Double = track.durationSeconds == nil ? 0.4 : 1.0
        let metadataConfidence = min(1, max(0, bpmTrust * 0.55 + keyTrust * 0.20 + durationTrust * 0.25))
        // Real measurements raise (or lower) trust; metadata alone never
        // reaches the certainty of an analyzed waveform.
        let confidence: Double
        if let signal {
            confidence = min(1, max(0, metadataConfidence * 0.4 + signal.overallConfidence * 0.6))
        } else {
            confidence = metadataConfidence
        }

        // Texture: MEASURED transient/low-band values when available.
        // The seeded fallback is cosmetic only — the planner requires
        // signal evidence before making any structural cut.
        let drumStrength: Double
        let bassDensity: Double
        if let signal, !signal.bassEnergyCurve.isEmpty {
            drumStrength = signal.drumConfidence
            bassDensity = signal.bassEnergyCurve.reduce(0, +) / Double(signal.bassEnergyCurve.count)
        } else {
            drumStrength = min(1, max(0, 0.62 + 0.25 * pseudoNoise(index: 7, seed: seed)))
            bassDensity = min(1, max(0, 0.58 + 0.28 * pseudoNoise(index: 13, seed: seed)))
        }

        return SongAnalysis(
            bpm: bpm,
            bpmIsReal: track.bpm != nil,
            bpmConfidence: track.bpmConfidence,
            key: track.key,
            keyConfidence: track.keyConfidence,
            durationSeconds: duration,
            beatGrid: beatGrid,
            downbeats: downbeats,
            phraseBoundaries: phrases,
            sectionCandidates: sections,
            introCandidate: intro,
            verseCandidates: verses,
            chorusOrDropCandidates: [chorus1, chorus2],
            buildCandidates: builds,
            bridgeCandidate: bridge,
            outroCandidate: outro,
            instrumentalCandidates: instrumentals,
            energyCurve: energy,
            vocalDensityCurve: vocals,
            mixInPoints: mixIn.sorted(),
            mixOutPoints: mixOut.sorted(),
            lyricOrVocalMoments: [],   // integration point: vocal/lyric detection
            hookMoments: [chorus1.startSeconds, chorus2.startSeconds],
            drumStrength: drumStrength,
            bassDensity: bassDensity,
            analysisConfidence: confidence,
            signal: signal
        )
    }

    // MARK: Curve builders

    private static func buildEnergyCurve(
        duration: Double,
        intro: SongSection,
        outro: SongSection,
        choruses: [SongSection],
        bridge: SongSection?,
        seed: UInt64
    ) -> [Double] {
        (0..<curveSamples).map { i in
            let t = Double(i) / Double(curveSamples - 1) * duration
            var value = 0.55

            if intro.contains(t) {
                value = 0.30 + 0.20 * ((t - intro.startSeconds) / max(intro.durationSeconds, 1))
            }
            if outro.contains(t) {
                value = 0.45 - 0.30 * ((t - outro.startSeconds) / max(outro.durationSeconds, 1))
            }
            for chorus in choruses where chorus.contains(t) {
                value = 0.92
            }
            if let bridge, bridge.contains(t) {
                value = 0.42
            }

            // Deterministic per-song wobble so no two maps are identical.
            value += 0.05 * pseudoNoise(index: i, seed: seed)
            return min(1, max(0, value))
        }
    }

    private static func buildVocalCurve(
        duration: Double,
        intro: SongSection,
        outro: SongSection,
        choruses: [SongSection],
        bridge: SongSection?,
        verses: [SongSection],
        seed: UInt64
    ) -> [Double] {
        (0..<curveSamples).map { i in
            let t = Double(i) / Double(curveSamples - 1) * duration
            var value = 0.55

            if intro.contains(t) || outro.contains(t) { value = 0.15 }
            for verse in verses where verse.contains(t) { value = 0.80 }
            for chorus in choruses where chorus.contains(t) { value = 0.90 }
            if let bridge, bridge.contains(t) { value = 0.35 }

            value += 0.06 * pseudoNoise(index: i &+ 31, seed: seed)
            return min(1, max(0, value))
        }
    }

    // MARK: Helpers

    /// Nearest-index resample of a measured curve onto `count` samples.
    private static func resample(_ curve: [Double], to count: Int) -> [Double] {
        guard !curve.isEmpty, count > 1 else { return curve }
        return (0..<count).map { i in
            let idx = Int(Double(i) / Double(count - 1) * Double(curve.count - 1))
            return curve[min(curve.count - 1, max(0, idx))]
        }
    }

    private static func snapOr(_ t: Double, _ phrases: [Double]) -> Double {
        phrases.last { $0 <= t && $0 > 0 } ?? t
    }

    private static func stableSeed(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return hash
    }

    /// Deterministic -1…1 noise.
    private static func pseudoNoise(index: Int, seed: UInt64) -> Double {
        var x = UInt64(bitPattern: Int64(index)) &+ seed &* 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x % 2000) / 1000.0 - 1.0
    }
}

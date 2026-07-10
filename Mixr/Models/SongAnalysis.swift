import CoreGraphics
import Foundation

// MARK: - Song Section

struct SongSection: Equatable, Sendable {
    enum Kind: String, Sendable {
        case intro
        case verse
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
    var key: String?
    var durationSeconds: Double

    var beatGrid: [Double]
    var downbeats: [Double]
    /// 8-bar phrase starts — the musically safe edit points.
    var phraseBoundaries: [Double]

    var sectionCandidates: [SongSection]
    var introCandidate: SongSection?
    var verseCandidates: [SongSection]
    var chorusOrDropCandidates: [SongSection]
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
    /// when known (metadata or MixrAudioAnalyzer) plus deterministic
    /// heuristics seeded by the track so different songs get different maps.
    static func analyze(track: MixrTrack) -> SongAnalysis {
        let bpm = track.bpm.map(Double.init) ?? defaultBPM
        let duration = track.durationSeconds
            ?? track.clips.first.map { MixrTimeline.seconds(fromUnits: $0.length) * $0.playbackSpeed }
            ?? 60

        let beat = 60.0 / bpm
        let bar = beat * 4
        let phrase = bar * 8
        let seed = stableSeed(track.title + track.artist)

        let beatGrid = Array(stride(from: 0.0, to: duration, by: beat))
        let downbeats = Array(stride(from: 0.0, to: duration, by: bar))
        let phrases = Array(stride(from: 0.0, to: duration, by: phrase))

        // ── Section heuristics (phrase-snapped fractions of the song) ──
        func snap(_ t: Double) -> Double {
            phrases.last { $0 <= t } ?? 0
        }

        let introEnd = min(phrase * (duration > phrase * 6 ? 2 : 1), duration * 0.20)
        let intro = SongSection(kind: .intro, startSeconds: 0, endSeconds: max(4, snapOr(introEnd, phrases)))

        let outroStart = max(intro.endSeconds, snap(duration - phrase))
        let outro = SongSection(kind: .outro, startSeconds: outroStart, endSeconds: duration)

        let chorus1Start = max(intro.endSeconds, snap(duration * 0.28))
        let chorus1 = SongSection(
            kind: .chorus,
            startSeconds: chorus1Start,
            endSeconds: min(outro.startSeconds, chorus1Start + phrase)
        )
        let chorus2Start = max(chorus1.endSeconds, snap(duration * 0.60))
        let chorus2 = SongSection(
            kind: .chorus,
            startSeconds: chorus2Start,
            endSeconds: min(outro.startSeconds, chorus2Start + phrase)
        )

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

        var sections: [SongSection] = [intro] + verses + [chorus1, chorus2] + (bridge.map { [$0] } ?? []) + [outro]
        sections.sort { $0.startSeconds < $1.startSeconds }

        // ── Energy & vocal-density curves ──
        let energy = buildEnergyCurve(
            duration: duration,
            intro: intro, outro: outro,
            choruses: [chorus1, chorus2],
            bridge: bridge,
            seed: seed
        )
        let vocals = buildVocalCurve(
            duration: duration,
            intro: intro, outro: outro,
            choruses: [chorus1, chorus2],
            bridge: bridge,
            verses: verses,
            seed: seed
        )

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

        return SongAnalysis(
            bpm: bpm,
            bpmIsReal: track.bpm != nil,
            key: track.key,
            durationSeconds: duration,
            beatGrid: beatGrid,
            downbeats: downbeats,
            phraseBoundaries: phrases,
            sectionCandidates: sections,
            introCandidate: intro,
            verseCandidates: verses,
            chorusOrDropCandidates: [chorus1, chorus2],
            bridgeCandidate: bridge,
            outroCandidate: outro,
            instrumentalCandidates: instrumentals,
            energyCurve: energy,
            vocalDensityCurve: vocals,
            mixInPoints: mixIn.sorted(),
            mixOutPoints: mixOut.sorted(),
            lyricOrVocalMoments: []   // integration point: vocal/lyric detection
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

import Foundation

// DJ-quality regression gates for measured-structure Auto Remix — NOT part
// of the app target. Run from the repo root with:
//
//   Scripts/run_auto_remix_tests.sh dj
//
// Fixtures are deterministic, copyright-free SYNTHETIC SONGS with a known
// arrangement (kick/snare/hats, bass on chord roots, pads, a lead melody
// that repeats identically in every chorus), arbitrary tempo, and a
// pickup offset — so analysis and rendered-PCM results are checked
// against ground truth. Each gate also demonstrates that the PREVIOUS
// behavior fails the same measurement.

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

let SR = 22_050.0

// MARK: - Synthetic structured songs

struct SectionSpec {
    var label: String       // "intro", "verse", "pre", "chorus", "bridge", "outro"
    var bars: Int
    var chords: [Int]       // chord roots (semitones above A), one per bar, cycled
    var energy: Float       // 0…1
    var melody: [Int]?      // lead notes (semitones above A4) per beat, cycled; nil = no lead
}

struct SyntheticSong {
    var samples: [Float]
    var bpm: Double
    var firstDownbeat: Double
    var sections: [(label: String, startBar: Int, bars: Int)]
    var barSeconds: Double { 240 / bpm }
    func barTime(_ b: Int) -> Double { firstDownbeat + Double(b) * barSeconds }
}

struct Noise {
    var state: UInt64
    mutating func next() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(Double(z >> 11) / Double(1 << 53)) * 2 - 1
    }
}

func synthesize(bpm: Double, pickup: Double, sections: [SectionSpec], keyShift: Int = 0, seed: UInt64 = 7) -> SyntheticSong {
    let beat = 60 / bpm, bar = beat * 4
    let totalBars = sections.reduce(0) { $0 + $1.bars }
    let duration = pickup + Double(totalBars) * bar + 1.0
    let n = Int(duration * SR)
    var out = [Float](repeating: 0, count: n)
    var noise = Noise(state: seed)
    var map: [(String, Int, Int)] = []
    var barIndex = 0
    func hz(_ semis: Int, octave: Double) -> Double { 440 * pow(2, Double(semis + keyShift) / 12) * octave }

    for s in sections {
        map.append((s.label, barIndex, s.bars))
        for b in 0..<s.bars {
            let barStart = pickup + Double(barIndex) * bar
            let root = s.chords[b % s.chords.count]
            let e = s.energy
            for q in 0..<4 {
                let t0 = barStart + Double(q) * beat
                let i0 = Int(t0 * SR)
                // Kick on 1 and 3 (four-on-the-floor when energy is high).
                if q % 2 == 0 || e > 0.8 {
                    for j in 0..<Int(0.16 * SR) where i0 + j < n {
                        let t = Double(j) / SR
                        let f = 45 + 70 * exp(-t * 30)
                        out[i0 + j] += Float(0.9 * Double(e) * exp(-t * 18) * sin(2 * .pi * f * t))
                    }
                }
                // Snare / clap on 2 and 4.
                if q % 2 == 1, e > 0.25 {
                    var prev: Float = 0
                    for j in 0..<Int(0.12 * SR) where i0 + j < n {
                        let w = noise.next(); let hp = w - prev; prev = w
                        out[i0 + j] += 0.35 * e * hp * Float(exp(-Double(j) / SR * 28))
                    }
                }
                // Hats on 8ths.
                for h in 0..<2 where e > 0.4 {
                    let hi = i0 + Int(Double(h) * beat / 2 * SR)
                    var prev: Float = 0
                    for j in 0..<Int(0.03 * SR) where hi + j < n {
                        let w = noise.next(); let hp = w - prev; prev = w
                        out[hi + j] += 0.08 * e * hp * Float(exp(-Double(j) / SR * 120))
                    }
                }
                // Bass on the chord root, one note per beat.
                let bassHz = hz(root, octave: 1.0 / 8)
                for j in 0..<Int(beat * 0.9 * SR) where i0 + j < n {
                    let t = Double(j) / SR
                    let env = min(1, t * 200) * exp(-t * 2)
                    out[i0 + j] += Float(0.32 * Double(e) * env * (sin(2 * .pi * bassHz * t) + 0.3 * sin(4 * .pi * bassHz * t)))
                }
                // Lead melody.
                if let mel = s.melody {
                    let note = mel[(b * 4 + q) % mel.count]
                    let f = hz(note, octave: 1)
                    for j in 0..<Int(beat * 0.95 * SR) where i0 + j < n {
                        let t = Double(j) / SR
                        let vib = 1 + 0.004 * sin(2 * .pi * 5.5 * t)
                        let env = min(1, t * 40) * min(1, (beat * 0.95 - t) * 40)
                        out[i0 + j] += Float(0.16 * env * (sin(2 * .pi * f * vib * t) + 0.4 * sin(4 * .pi * f * vib * t)))
                    }
                }
            }
            // Pad: triad on the chord for the whole bar.
            let i0 = Int(barStart * SR)
            for j in 0..<Int(bar * SR) where i0 + j < n {
                let t = Double(j) / SR
                var v = 0.0
                for (k, iv) in [0, 3, 7].enumerated() {
                    v += sin(2 * .pi * hz(root + iv, octave: 0.5) * t + Double(k))
                }
                out[i0 + j] += Float(0.05 * Double(0.4 + e) * v)
            }
            barIndex += 1
        }
    }
    // Master like a real release: peak at −3 dBFS.
    let peak = out.map { abs($0) }.max() ?? 1
    if peak > 0 { let g = 0.708 / peak; for i in out.indices { out[i] *= g } }
    return SyntheticSong(samples: out, bpm: bpm, firstDownbeat: pickup,
                         sections: map.map { (label: $0.0, startBar: $0.1, bars: $0.2) })
}

/// A radio-style song: intro, verse, pre, CHORUS, verse, pre, CHORUS,
/// bridge, CHORUS, outro. Chorus melody identical each time.
func popSong(bpm: Double, pickup: Double, keyShift: Int = 0, seed: UInt64 = 7) -> SyntheticSong {
    let verse = [0, 8, 3, 10]          // Am F C G
    let chorus = [8, 10, 0, 3]         // F G Am C
    let hook = [12, 12, 15, 17, 15, 12, 10, 12, 8, 10, 12, 15, 17, 15, 12, 12]
    let verseMel = [7, 7, 5, 3, 5, 7, 5, 3]
    return synthesize(bpm: bpm, pickup: pickup, sections: [
        SectionSpec(label: "intro", bars: 16, chords: verse, energy: 0.3, melody: nil),
        SectionSpec(label: "verse", bars: 16, chords: verse, energy: 0.55, melody: verseMel),
        SectionSpec(label: "pre", bars: 4, chords: [5, 7], energy: 0.6, melody: [10, 12]),
        SectionSpec(label: "chorus", bars: 16, chords: chorus, energy: 1.0, melody: hook),
        SectionSpec(label: "verse", bars: 16, chords: verse, energy: 0.55, melody: verseMel),
        SectionSpec(label: "pre", bars: 4, chords: [5, 7], energy: 0.6, melody: [10, 12]),
        SectionSpec(label: "chorus", bars: 16, chords: chorus, energy: 1.0, melody: hook),
        SectionSpec(label: "bridge", bars: 8, chords: [5, 7], energy: 0.3, melody: nil),
        SectionSpec(label: "pre", bars: 4, chords: [5, 7], energy: 0.6, melody: [10, 12]),
        SectionSpec(label: "chorus", bars: 16, chords: chorus, energy: 1.0, melody: hook),
        SectionSpec(label: "outro", bars: 12, chords: verse, energy: 0.3, melody: nil),
    ], keyShift: keyShift, seed: seed)
}

/// Club structure: long DJ intro, breakdown → build → DROP twice, outro.
/// The drops sit where a fraction-of-duration guess does not look.
func clubSong(bpm: Double, pickup: Double) -> SyntheticSong {
    let drop = [0, 0, 8, 10]
    let hook = [12, 15, 12, 17, 15, 12, 10, 12]
    return synthesize(bpm: bpm, pickup: pickup, sections: [
        SectionSpec(label: "intro", bars: 32, chords: [0], energy: 0.45, melody: nil),
        SectionSpec(label: "breakdown", bars: 16, chords: [8, 10, 0, 3], energy: 0.25, melody: [7, 5, 3, 5]),
        SectionSpec(label: "build", bars: 8, chords: [7], energy: 0.5, melody: [12]),
        SectionSpec(label: "chorus", bars: 16, chords: drop, energy: 1.0, melody: hook),
        SectionSpec(label: "breakdown", bars: 16, chords: [8, 10, 0, 3], energy: 0.25, melody: [7, 5, 3, 5]),
        SectionSpec(label: "build", bars: 8, chords: [7], energy: 0.5, melody: [12]),
        SectionSpec(label: "chorus", bars: 16, chords: drop, energy: 1.0, melody: hook),
        SectionSpec(label: "outro", bars: 24, chords: [0], energy: 0.45, melody: nil),
    ], seed: 21)
}

func track(_ title: String, _ song: SyntheticSong, bpm: Int? = nil, key: String? = nil) -> MixrTrack {
    let duration = Double(song.samples.count) / SR
    return MixrTrack(
        id: UUID(), title: title, artist: "Fixture", duration: "--:--", durationSeconds: duration,
        bpm: bpm, bpmConfidence: nil, key: key, keyConfidence: nil, color: .pink, volume: 1.0,
        isMuted: false, url: nil, artworkData: nil,
        clips: [MixrClip(id: UUID(), start: 0, length: MixrTimeline.units(fromSeconds: min(duration, 180)))]
    )
}

// MARK: - Meters

func dB(_ x: Double) -> Double { 20 * log10(max(x, 1e-12)) }

/// RMS level (dBFS) of [a, b) seconds.
func level(_ x: [Float], _ a: Double, _ b: Double, sr: Double = SR) -> Double {
    let lo = max(0, Int(a * sr)), hi = min(x.count, Int(b * sr))
    guard hi > lo else { return -120 }
    var s = 0.0
    for i in lo..<hi { s += Double(x[i]) * Double(x[i]) }
    return dB((s / Double(hi - lo)).squareRoot())
}

/// Worst trough at a join (dB, positive = hole): the quietest 400 ms
/// window within ±0.6 s of the join versus the quietest 400 ms window of
/// the 3 s context on either side — so a song's own beat-to-beat
/// modulation cancels out and only a transition-made dip remains.
func joinTrough(_ x: [Float], at t: Double) -> Double {
    func quietest(_ a: Double, _ b: Double) -> Double {
        var m = 120.0, w = a
        while w + 0.4 <= b + 1e-9 { m = min(m, level(x, w, w + 0.4)); w += 0.05 }
        return m
    }
    let context = min(quietest(t - 3.6, t - 0.6), quietest(t + 0.6, t + 3.6))
    return context - quietest(t - 0.6, t + 0.6)
}

/// One-pole low-pass (bass band) of a signal.
func lowBand(_ x: [Float], cutoff: Double = 150) -> [Float] {
    let a = Float(1 - exp(-2 * .pi * cutoff / SR))
    var y: Float = 0, z: Float = 0
    return x.map { v in y += (v - y) * a; z += (y - z) * a; return z }
}

func samplePeak(_ x: [Float]) -> Double { Double(x.map { abs($0) }.max() ?? 0) }

// MARK: - Shared fixtures

let songA = popSong(bpm: 123.4, pickup: 0.37)
let songB = popSong(bpm: 118.0, pickup: 0.52, keyShift: 5, seed: 11)
let featuresA = SongSignalAnalyzer.extract(samples: songA.samples, sampleRate: SR)
let featuresB = SongSignalAnalyzer.extract(samples: songB.samples, sampleRate: SR)

// MARK: - 1. Measured beat grid (float tempo, real downbeats)

do {
    guard let st = featuresA.structure else {
        check("Analysis: structure measured on a synthetic song", false)
        fatalError("no structure")
    }
    check("Analysis: tempo measured as a float (123.4 BPM)", abs(st.bpm - 123.4) < 0.05, String(format: "%.3f", st.bpm))
    // Grid accuracy at the END of the song (drift accumulates).
    let lastBar = songA.sections.reduce(0) { $0 + $1.bars } - 1
    let lastTrue = songA.barTime(lastBar)
    let nearest = st.downbeats.min { abs($0 - lastTrue) < abs($1 - lastTrue) } ?? 0
    check("Analysis: bar grid still on the downbeat at the last bar (≤ 25 ms)", abs(nearest - lastTrue) < 0.025,
          String(format: "error %.1f ms", abs(nearest - lastTrue) * 1000))
    // PREVIOUS behavior: an integer BPM grid (metadata / MixrAudioAnalyzer
    // rounding) from the first downbeat drifts off the beat.
    let intGrid = songA.firstDownbeat + Double(lastBar) * 240 / 123.0
    check("Previous integer-BPM grid FAILS the same drift gate", abs(intGrid - lastTrue) > 0.25,
          String(format: "drift %.0f ms", abs(intGrid - lastTrue) * 1000))
    // Downbeat phase: true bar lines matched.
    let truth = (0...lastBar).map { songA.barTime($0) }
    let matched = truth.filter { t in st.downbeats.contains { abs($0 - t) < 0.03 } }.count
    check("Analysis: downbeats land on true bar lines (≥ 90%)", Double(matched) / Double(truth.count) >= 0.9,
          "\(matched)/\(truth.count)")
    check("Analysis: first downbeat is not assumed at t = 0", (st.downbeats.first(where: { $0 >= 0.2 }) ?? 0) > 0.3)
}

// MARK: - 2. Measured sections (chorus / drop found where it is)

for (name, song) in [("pop", songA), ("club", clubSong(bpm: 126, pickup: 0.2))] {
    let features = name == "pop" ? featuresA : SongSignalAnalyzer.extract(samples: song.samples, sampleRate: SR)
    guard let st = features.structure else { check("Sections (\(name)): structure measured", false); continue }
    let songA = song
    let trueChorusBars = songA.sections.filter { $0.label == "chorus" }.flatMap { $0.startBar..<($0.startBar + $0.bars) }
    func barOf(_ t: Double) -> Int { Int(((t - songA.firstDownbeat) / songA.barSeconds).rounded()) }
    let measuredChorusBars = Set(st.sections(.chorus).flatMap { barOf($0.start)..<barOf($0.end) })
    let hit = trueChorusBars.filter { measuredChorusBars.contains($0) }.count
    check("Sections (\(name)): measured payoff covers the true choruses/drops (≥ 75%)", Double(hit) / Double(trueChorusBars.count) >= 0.75,
          "\(hit)/\(trueChorusBars.count) bars")
    let precision = Double(measuredChorusBars.filter { trueChorusBars.contains($0) }.count) / Double(max(1, measuredChorusBars.count))
    check("Sections (\(name)): measured payoff is mostly chorus/drop (precision ≥ 70%)", precision >= 0.7, String(format: "%.2f", precision))
    // PREVIOUS behavior: chorus = 28% / 60% of the duration, 8 bars.
    let duration = Double(songA.samples.count) / SR
    let old = [0.28, 0.60].map { barOf(duration * $0) }.flatMap { $0..<($0 + 8) }
    let oldHit = Double(old.filter { trueChorusBars.contains($0) }.count) / Double(old.count)
    if name == "club" {
        check("Previous fraction-of-duration chorus guess FAILS precision (club)", oldHit < 0.7, String(format: "precision %.2f", oldHit))
    }
}

// MARK: - 3. One-song DJ edit (high confidence)

let trackA = track("Synthetic A", songA)
let remixPlan: AutoRemixPlan = {
    let (draft, profiles) = AutoRemixPlanner.makePlan(tracks: [trackA], seed: 1, signals: [trackA.id: featuresA])!
    return AutoRemixValidator.validate(draft, profiles: profiles, tuning: .standard)
}()
let remixRender = AutoOfflineMixdown.render(plan: remixPlan, sources: [trackA.id: .init(samples: songA.samples, sampleRate: SR)], sampleRate: SR)

do {
    let plan = remixPlan
    let kinds = Set(plan.decisions.map(\.kind))
    let zones = [kinds.contains(.hookPreview) || kinds.contains(.trimmedIntro)
                    || plan.decisions.contains { $0.detail?.contains("filter intro") == true },
                 kinds.contains(.removedRedundantRepeat),
                 plan.decisions.contains { $0.detail?.contains("breakdown") == true },
                 kinds.contains(.extendedBuild) || kinds.contains(.addedRiserIntoDrop),
                 kinds.contains(.echoOutEnding) || kinds.contains(.shortenedOutro)].filter { $0 }.count
    check("Remix: 3–5 transformation zones on a confident song", (3...5).contains(zones), "\(zones) zones")
    let nonSFX = [kinds.contains(.removedRedundantRepeat), kinds.contains(.extendedBuild),
                  kinds.contains(.hookPreview) || kinds.contains(.trimmedIntro),
                  plan.placements.contains { $0.fadeIn.filter != nil || $0.fadeOut.filter != nil }].filter { $0 }.count
    check("Remix: ≥ 2 non-SFX transformations", nonSFX >= 2, "\(nonSFX)")
    // Every source discontinuity carries a masked, confident cut record.
    let dom = plan.placements.sorted { $0.timelineStart < $1.timelineStart }
    var unrecorded = 0, noOverlap = 0
    for (a, b) in zip(dom, dom.dropFirst()) where !b.continuesPrevious {
        let recorded = plan.cutRecords.contains { abs($0.timelineAt - b.timelineStart) < 0.1 && $0.confidence >= 0.5 }
        if !recorded { unrecorded += 1 }
        if b.timelineStart >= a.timelineEnd - 0.005 { noOverlap += 1 }
    }
    check("Remix: every internal cut has a confident cut record", unrecorded == 0, "\(unrecorded) unrecorded")
    check("Remix: every internal cut is a real overlap (no sequential fade hole)", noOverlap == 0, "\(noOverlap)")
    // A complete chorus survives untouched in one continuous run.
    let chorus = songA.sections.first { $0.label == "chorus" }!
    let cStart = songA.barTime(chorus.startBar), cEnd = songA.barTime(chorus.startBar + chorus.bars)
    var runs: [(Double, Double)] = []
    for p in dom {
        if p.continuesPrevious, var last = runs.last { last.1 = p.sourceEnd; runs[runs.count - 1] = last } else { runs.append((p.sourceStart, p.sourceEnd)) }
    }
    check("Remix: a complete chorus plays continuously", runs.contains { $0.0 <= cStart + 0.05 && $0.1 >= cEnd - 0.05 })
    check("Remix: a substantial continuous passage (≥ 45 s) survives", runs.contains { $0.1 - $0.0 >= 45 })
    // Drops: riser ENDS on the drop downbeat, impact ON it.
    for drop in plan.payoffTimes {
        let riser = plan.sfxEvents.first { $0.assetID == "riser" && abs($0.timelineEnd - drop) < 0.01 }
        let impact = plan.sfxEvents.first { $0.assetID == "impact" && abs($0.timelineStart - drop) < 0.01 }
        if riser != nil || impact != nil {
            check(String(format: "Remix: build SFX land on the %.1fs drop downbeat", drop), riser != nil && impact != nil)
        }
    }
}

do {
    let mix = remixRender.mix
    let joins = remixPlan.placements.filter { !$0.continuesPrevious && $0.timelineStart > 0.5 }
        .map { $0.timelineStart + $0.overlapsPreviousSeconds }
    let worst = joins.map { joinTrough(mix, at: $0) }.max() ?? 0
    check("Remix render: no join-centered loudness hole > 2 dB", worst <= 2.0, String(format: "worst %.2f dB", worst))
    check("Remix render: sample peak ≤ −1 dBFS", dB(samplePeak(mix)) <= -0.99, String(format: "%.2f dBFS", dB(samplePeak(mix))))
    check("Remix render: limiter is safety, not glue (≤ 3 dB)", remixRender.limiterGainReductionDB <= 3,
          String(format: "%.2f dB", remixRender.limiterGainReductionDB))
    // High-pass build really drains the low end, and the drop restores it.
    if let dropT = remixPlan.payoffTimes.first,
       let build = remixPlan.placements.first(where: { $0.fadeOut.filter == .highPassSweep }) {
        let low = lowBand(mix)
        let drained = level(low, build.timelineEnd - 1.0, build.timelineEnd - 0.1)
        let restored = level(low, dropT + 0.2, dropT + 1.2)
        check("Remix render: high-pass build drains the bass, drop restores it (≥ 10 dB)", restored - drained >= 10,
              String(format: "%.1f dB", restored - drained))
    }
}

// MARK: - 4. Mashup: beatmatched, bass-swapped, even airtime

let trackB = track("Synthetic B", songB)
let mashupPlan: AutoRemixPlan = {
    let signals = [trackA.id: featuresA, trackB.id: featuresB]
    let (draft, profiles) = AutoRemixPlanner.makePlan(tracks: [trackA, trackB], seed: 1, signals: signals)!
    return AutoRemixValidator.validate(draft, profiles: profiles, tuning: .standard)
}()
let mashupSources: [UUID: AutoOfflineMixdown.Source] = [
    trackA.id: .init(samples: songA.samples, sampleRate: SR),
    trackB.id: .init(samples: songB.samples, sampleRate: SR),
]
let mashupRender = AutoOfflineMixdown.render(plan: mashupPlan, sources: mashupSources, sampleRate: SR)

do {
    let plan = mashupPlan
    check("Mashup: ≥ 3 song handoffs", plan.handoffCount >= 3, "\(plan.handoffCount)")
    check("Mashup: both songs beatmatched (123.4 vs 118 BPM meet in the middle)",
          Set(plan.placements.map { ($0.tempoRatio * 1000).rounded() }).count == 2
            && plan.placements.allSatisfy { abs($0.tempoRatio - 1) <= 0.08 })
    check("Mashup: uses a bass-swap blend", plan.placements.contains { $0.fadeIn.filter == .bassSwap })
    // Even airtime.
    var airtime: [UUID: Double] = [:]
    for p in plan.placements { airtime[p.songID, default: 0] += p.timelineDuration }
    let shares = airtime.values.map { $0 / airtime.values.reduce(0, +) }
    check("Mashup: even airtime (each song 35–65%)", shares.allSatisfy { (0.35...0.65).contains($0) },
          shares.map { String(format: "%.2f", $0) }.joined(separator: " / "))
    // A turn is a full phrase: at least 8 bars at the mix tempo.
    let eightBars = 8 * 240 / plan.targetBPM
    check("Mashup: each turn is a full phrase (≥ 8 bars)", plan.placements.allSatisfy { $0.timelineDuration >= eightBars - 0.1 },
          String(format: "shortest %.1fs (8 bars = %.1fs)", plan.placements.map(\.timelineDuration).min() ?? 0, eightBars))
    // Handoffs never leave a hole.
    let dom = plan.placements.sorted { $0.timelineStart < $1.timelineStart }
    let holes = zip(dom, dom.dropFirst()).filter { $1.timelineStart > $0.timelineEnd + 0.005 }.count
    check("Mashup: every handoff overlaps or pre-rolls (no silence)", holes == 0, "\(holes) holes")
}

do {
    let mix = mashupRender.mix
    let joins = mashupPlan.placements.sorted { $0.timelineStart < $1.timelineStart }.dropFirst().map(\.timelineStart)
    let worst = joins.map { joinTrough(mix, at: $0) }.max() ?? 0
    check("Mashup render: no handoff loudness hole > 2 dB", worst <= 2.0, String(format: "worst %.2f dB", worst))
    // Bass swap: during a blend, the low band never stacks both basslines.
    if let incoming = mashupPlan.placements.first(where: { $0.fadeIn.filter == .bassSwap }),
       let outgoing = mashupPlan.placements.first(where: { $0.songID != incoming.songID && abs($0.timelineEnd - incoming.timelineStart - incoming.fadeIn.duration * 60 / incoming.envelopeBPM) < 0.05 }) {
        let blendEnd = outgoing.timelineEnd
        let low = lowBand(mix)
        let during = level(low, incoming.timelineStart + 0.5, blendEnd - 0.5)
        let before = level(low, incoming.timelineStart - 3.5, incoming.timelineStart - 0.5)
        let after = level(low, blendEnd + 0.5, blendEnd + 3.5)
        check("Mashup render: bass swap keeps the low end at one song's level (≤ +1 dB)", during - max(before, after) <= 1.0,
              String(format: "%+.2f dB", during - max(before, after)))

        // PREVIOUS behavior on the same blend: equal-power with NO bass
        // swap stacks both basslines.
        var noSwap = mashupPlan
        for i in noSwap.placements.indices {
            noSwap.placements[i].fadeIn.filter = nil
            noSwap.placements[i].fadeOut.filter = nil
        }
        let old = AutoOfflineMixdown.render(plan: noSwap, sources: mashupSources, sampleRate: SR).mix
        let oldLow = lowBand(old)
        let oldDuring = level(oldLow, incoming.timelineStart + 0.5, blendEnd - 0.5)
        check("Previous no-swap blend carries more stacked low end", oldDuring - during >= 1.0,
              String(format: "%+.2f dB more low end", oldDuring - during))
    } else {
        check("Mashup render: found a bass-swap blend to measure", false)
    }
    // PREVIOUS behavior: butt-joined clips that fade out AND fade in at
    // the same boundary leave a hole.
    var holePlan = mashupPlan
    holePlan.placements.sort { $0.timelineStart < $1.timelineStart }
    let a = holePlan.placements[0], b = holePlan.placements[1]
    holePlan.placements = [a, b]
    holePlan.placements[1].timelineStart = a.timelineEnd
    holePlan.placements[0].fadeOut = ClipTransition(type: .fadeOut, duration: 4)
    holePlan.placements[1].fadeIn = ClipTransition(type: .crossfade, duration: 4)
    let hole = AutoOfflineMixdown.render(plan: holePlan, sources: mashupSources, sampleRate: SR, includeTail: false).mix
    check("Previous sequential fade-out/fade-in join FAILS the hole gate", joinTrough(hole, at: a.timelineEnd) > 3,
          String(format: "%.1f dB hole", joinTrough(hole, at: a.timelineEnd)))
    check("Mashup render: sample peak ≤ −1 dBFS", dB(samplePeak(mix)) <= -0.99, String(format: "%.2f", dB(samplePeak(mix))))
}

// MARK: - 4a. DJ turns: frequent handoffs, hook up front, high-energy material

do {
    var longForm = AutoTuning.standard
    longForm.mashupDJTurns = false
    let previousPlan: AutoRemixPlan = {
        let signals = [trackA.id: featuresA, trackB.id: featuresB]
        let (draft, profiles) = AutoRemixPlanner.makePlan(tracks: [trackA, trackB], tuning: longForm, seed: 1, signals: signals)!
        return AutoRemixValidator.validate(draft, profiles: profiles, tuning: longForm)
    }()
    // Pop + club (32-bar DJ intro, breakdowns before each drop): the
    // material that made long-form mashups slow to hit and quiet.
    let club = clubSong(bpm: 126, pickup: 0.2)
    let trackC = track("Synthetic Club", club)
    let clubSignals = [trackA.id: featuresA, trackC.id: SongSignalAnalyzer.extract(samples: club.samples, sampleRate: SR)]
    let clubSources: [UUID: AutoOfflineMixdown.Source] = [
        trackA.id: .init(samples: songA.samples, sampleRate: SR),
        trackC.id: .init(samples: club.samples, sampleRate: SR),
    ]
    func clubMashup(_ tuning: AutoTuning) -> (plan: AutoRemixPlan, mix: [Float]) {
        let (draft, profiles) = AutoRemixPlanner.makePlan(tracks: [trackA, trackC], tuning: tuning, seed: 1, signals: clubSignals)!
        let plan = AutoRemixValidator.validate(draft, profiles: profiles, tuning: tuning)
        return (plan, AutoOfflineMixdown.render(plan: plan, sources: clubSources, sampleRate: SR).mix)
    }
    let clubNew = clubMashup(.standard), clubOld = clubMashup(longForm)
    let fixtures = [trackA.id: songA, trackB.id: songB, trackC.id: club]

    /// Seconds between consecutive song entries (how long one song holds
    /// the floor before the next takes over), excluding the final turn.
    func turnLengths(_ plan: AutoRemixPlan) -> [Double] {
        let starts = plan.placements.sorted { $0.timelineStart < $1.timelineStart }.map(\.timelineStart)
        return zip(starts, starts.dropFirst()).map { $1 - $0 }
    }
    /// Ground truth: is source second `t` of `song` inside a chorus?
    func inChorus(_ song: SyntheticSong, _ t: Double) -> Bool {
        song.sections.contains { $0.label == "chorus" && t >= song.barTime($0.startBar) && t < song.barTime($0.startBar + $0.bars) }
    }
    /// Timeline seconds until the first chorus (lead hook) is heard, and
    /// the share of the mix that plays chorus material.
    func hookStats(_ plan: AutoRemixPlan) -> (first: Double, share: Double) {
        var first = Double.infinity, hits = 0, total = 0
        var t = 0.0
        while t < plan.targetDuration {
            total += 1
            let hit = plan.placements.contains { p in
                guard t >= p.timelineStart, t < p.timelineEnd, let song = fixtures[p.songID] else { return false }
                return inChorus(song, p.sourceStart + (t - p.timelineStart) * p.tempoRatio)
            }
            if hit { hits += 1; first = min(first, t) }
            t += 0.25
        }
        return (first, Double(hits) / Double(max(total, 1)))
    }
    /// Rendered PCM: share of 2 s windows more than 6 dB below the mix's
    /// 90th-percentile window (a quiet, low-energy stretch on the floor).
    /// Deliberate builds (riser spans: high-pass drains the low end on
    /// purpose before a drop) are not stretches.
    func quietShare(_ plan: AutoRemixPlan, _ mix: [Float]) -> Double {
        let builds = plan.sfxEvents.filter { $0.assetID == "riser" }.map { ($0.timelineStart, $0.timelineEnd) }
        let end = plan.targetDuration - 10    // an echo-out ending is meant to be quiet
        var levels: [Double] = []
        var t = 0.0
        while t + 2 <= end {
            if !builds.contains(where: { t < $0.1 && t + 2 > $0.0 }) { levels.append(level(mix, t, t + 2)) }
            t += 1
        }
        guard !levels.isEmpty else { return 1 }
        let p90 = levels.sorted()[Int(Double(levels.count - 1) * 0.9)]
        return Double(levels.filter { $0 < p90 - 6 }.count) / Double(levels.count)
    }

    let newTurns = turnLengths(mashupPlan), oldTurns = turnLengths(previousPlan)
    check("DJ turns: ≥ 5 handoffs between two confident songs", mashupPlan.handoffCount >= 5, "\(mashupPlan.handoffCount)")
    check("Previous long-form mashup FAILS the handoff gate", previousPlan.handoffCount < 5, "\(previousPlan.handoffCount)")
    check("DJ turns: no song holds the floor > 30 s", (newTurns.max() ?? 0) <= 30,
          String(format: "longest %.1f s", newTurns.max() ?? 0))
    check("Previous long-form mashup FAILS the turn-length gate", (oldTurns.max() ?? 0) > 30,
          String(format: "longest %.1f s", oldTurns.max() ?? 0))

    let bar = clubNew.plan.targetBPM > 0 ? 240 / clubNew.plan.targetBPM : songA.barSeconds
    let newHook = hookStats(clubNew.plan), oldHook = hookStats(clubOld.plan)
    check("DJ turns (pop + club): first hook within 4 bars of the start", newHook.first <= 4 * bar + 0.5,
          String(format: "%.1f s (4 bars = %.1f s)", newHook.first, 4 * bar))
    // (The long-form planner also reaches these synthetic hooks quickly —
    // this gate guards the turn opener, it is not a before/after claim.)
    check("DJ turns (pop + club): ≥ 75% of the mix is hook material", newHook.share >= 0.75, String(format: "%.0f%%", newHook.share * 100))
    check("Previous long-form mashup FAILS the hook-share gate", oldHook.share < 0.75, String(format: "%.0f%%", oldHook.share * 100))

    // Rendered PCM, ending excluded (an echo-out tail is meant to be quiet).
    let newQuiet = quietShare(clubNew.plan, clubNew.mix)
    let oldQuiet = quietShare(clubOld.plan, clubOld.mix)
    let clubJoins = clubNew.plan.placements.sorted { $0.timelineStart < $1.timelineStart }.dropFirst().map(\.timelineStart)
    let clubWorst = clubJoins.map { joinTrough(clubNew.mix, at: $0) }.max() ?? 0
    check("DJ turns render (pop + club): no handoff loudness hole > 2 dB", clubWorst <= 2.0, String(format: "worst %.2f dB", clubWorst))
    check("DJ turns render (pop + club): sample peak ≤ −1 dBFS", dB(samplePeak(clubNew.mix)) <= -0.99,
          String(format: "%.2f", dB(samplePeak(clubNew.mix))))
    check("DJ turns (pop + club): timeline within budget", clubNew.plan.targetDuration <= AutoTuning.standard.maxTimelineSeconds,
          String(format: "%.0f s", clubNew.plan.targetDuration))
    print("pop+club: " + clubNew.plan.sequence.joined(separator: " → ") + " · "
          + clubNew.plan.transitionsUsed.map(\.rawValue).joined(separator: ", "))
    check("DJ turns render (pop + club): ≤ 10% of the mix sits > 6 dB below its peak level", newQuiet <= 0.10,
          String(format: "%.0f%%", newQuiet * 100))
    print(String(format: "      (long-form render on the same songs: %.0f%% quiet)", oldQuiet * 100))
}

// MARK: - 4b. Grid discontinuities never sit inside a beatmatched overlap

do {
    // Splice a 150 ms phase jump into song B at bar 60 (an edit / a live
    // drummer's push): everything after it is off the earlier grid.
    var spliced = songB
    let cut = Int(songB.barTime(60) * SR)
    spliced.samples.removeSubrange(cut..<(cut + Int(0.15 * SR)))
    let fx = SongSignalAnalyzer.extract(samples: spliced.samples, sampleRate: SR)
    let splice = songB.barTime(60)
    let found = fx.structure?.gridBreaks.contains { abs($0 - splice) < songB.barSeconds * 1.5 } ?? false
    check("Grid: a spliced phase jump is detected as a grid break", found,
          fx.structure.map { $0.gridBreaks.map { String(format: "%.1f", $0) }.joined(separator: ",") } ?? "no structure")
    let tb = track("Spliced B", spliced)
    let (draft, profiles) = AutoRemixPlanner.makePlan(tracks: [trackA, tb], seed: 1,
                                                      signals: [trackA.id: featuresA, tb.id: fx])!
    let plan = AutoRemixValidator.validate(draft, profiles: profiles, tuning: .standard)
    let breaks = fx.structure?.gridBreaks ?? []
    var spanning = 0
    let dom = plan.placements.sorted { $0.timelineStart < $1.timelineStart }
    for (x, y) in zip(dom, dom.dropFirst()) where x.timelineEnd - y.timelineStart > 1 {
        for p in [x, y] where p.songID == tb.id {
            let a = p.sourceStart + (y.timelineStart - p.timelineStart) * p.tempoRatio
            let b = p.sourceStart + (x.timelineEnd - p.timelineStart) * p.tempoRatio
            if breaks.contains(where: { $0 > a && $0 < b }) { spanning += 1 }
        }
    }
    check("Grid: no beatmatched overlap spans a grid break", spanning == 0, "\(spanning)")
}

// MARK: - 5. Tempo target, echo throw, SFX lane

do {
    func profile(_ bpm: Int) -> AutoSongProfile {
        AutoSectionCatalog.profile(track: MixrTrack(
            id: UUID(), title: "T\(bpm)", artist: "", duration: "", durationSeconds: 200, bpm: bpm, key: nil,
            color: .pink, volume: 1, isMuted: false, url: nil, artworkData: nil,
            clips: [MixrClip(id: UUID(), start: 0, length: 10)]))
    }
    let p90 = profile(90), p100 = profile(100)
    let target = AutoTempo.targetBPM(profiles: [p90, p100], anchorID: p90.songID, maxStretch: 0.08)
    let both = [90.0, 100.0].allSatisfy { AutoTempo.fit(songBPM: $0, targetBPM: target, maxStretch: 0.08).gridAligned }
    check("Tempo: 90 + 100 BPM meet in the middle — both beatmatch", both, String(format: "target %.1f", target))
    check("Previous anchor-only target leaves 100 BPM unmatched",
          !AutoTempo.fit(songBPM: 100, targetBPM: 90, maxStretch: 0.08).gridAligned)
}

do {
    let throwEdge = ClipTransition(type: .echoOut, duration: 2)
    let g = AutoTransitionEnvelope.envelope(transitionIn: .none, transitionOut: throwEdge, clipStart: 0, clipEnd: 10,
                                            at: 9.95, bpm: 120).gain
    check("Echo throw keeps full level into the downbeat", g > 0.99, String(format: "%.2f", g))
    let bpm = AutoTransitionEnvelope.timelineBPM(trackBPM: 100, playbackSpeed: 1.2)
    let beats = AutoTransitionEnvelope.beats(forSeconds: 4.0, timelineBPM: bpm)
    check("Fade beats use the clip's timeline tempo (live/export/planner parity)", abs(beats * 60 / bpm - 4.0) < 1e-9
          && abs(bpm - 120) < 1e-9)
}

do {
    // Applier: a colliding SFX is dropped, never slid past its drop.
    let song = track("Lane", songA)
    var plan = remixPlan
    plan.sfxEvents = [
        AutoSFXEvent(assetID: "riser", timelineStart: 20, purpose: "a"),
        AutoSFXEvent(assetID: "snareBuild", timelineStart: 20, purpose: "b"),
    ]
    plan.placements = plan.placements.map { var p = $0; p.songID = song.id; return p }
    let applied = AutoRemixApplier.apply(plan, to: [song])
    let sfxClips = applied.tracks.first { $0.isSFXTrack }?.clips ?? []
    check("SFX lane: colliding build SFX dropped, not moved off the downbeat",
          sfxClips.count == 1 && abs(MixrTimeline.seconds(fromUnits: sfxClips[0].start) - 20) < 0.01,
          "\(sfxClips.count) clip(s)")
}

// MARK: - 6. Low confidence stays continuous

do {
    // Pulse-free drone: nothing to edit from.
    var drone = [Float](repeating: 0, count: Int(170 * SR))
    for i in drone.indices { let t = Double(i) / SR; drone[i] = Float(0.2 * sin(2 * .pi * 196 * t) * (0.8 + 0.2 * sin(0.3 * t))) }
    let features = SongSignalAnalyzer.extract(samples: drone, sampleRate: SR)
    let droneSong = SyntheticSong(samples: drone, bpm: 120, firstDownbeat: 0, sections: [])
    let t = track("Drone", droneSong)
    let (draft, profiles) = AutoRemixPlanner.makePlan(tracks: [t], seed: 1, signals: [t.id: features])!
    let plan = AutoRemixValidator.validate(draft, profiles: profiles, tuning: .standard)
    check("Low confidence: zero internal cuts, one continuous placement", plan.cutRecords.isEmpty && plan.placements.count == 1,
          "\(plan.placements.count) placements")
    check("Low confidence: no SFX", plan.sfxEvents.isEmpty)
}

// MARK: - Evidence (printed)

print("\n── DJ quality evidence ──")
if let st = featuresA.structure {
    print(String(format: "A: %.3f BPM, beat %.2f, downbeat %.2f, structure %.2f, stability %.2f",
                 st.bpm, st.beatConfidence, st.downbeatConfidence, st.structureConfidence, st.tempoStability))
    print("   sections:", st.sections.map { "\($0.label.rawValue)@\($0.startBar)+\($0.barCount)" }.joined(separator: " "))
}
print("remix decisions:"); remixPlan.decisions.forEach { print("  • \($0.userFacingSentence)") }
print("mashup:", mashupPlan.sequence.joined(separator: " → "), "·", mashupPlan.transitionsUsed.map(\.rawValue).joined(separator: ", "))
print(failures == 0 ? "\nALL PASSED" : "\nFAILED: \(failures)")
if failures > 0 { exit(1) }

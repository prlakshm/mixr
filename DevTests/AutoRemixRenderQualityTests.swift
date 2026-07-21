import Foundation

// Rendered-PCM quality gates for the one-song Auto Remix pipeline —
// NOT part of the app target. Run from the repo root with:
//
//   Scripts/run_auto_remix_tests.sh render
//
// These tests render plans to PCM through the portable reference mixdown
// (AutoOfflineMixdown — the same envelope/gain models live playback and
// export consume) and assert objective audio quality:
//
//   • preservation-first plan shape (zero default cuts, monotonic source,
//     no default silence, cut budget, structured cut records)
//   • no clipping, true peak ≤ −1 dBTP, limiter as safety not glue
//   • no join-centered loudness troughs > 3 dB, no unexplained > 4 dB jumps
//   • no unintended silence ≥ 100 ms below −45 dBFS inside musical content
//   • no fixed silent export tail
//   • equal-power crossfades with REAL temporal overlap
//   • signal-derived analysis (measured, never seeded)
//   • live/export automation parity (shared envelope model)
//
// Fixtures are fully synthetic (sine + shaped noise + steps) —
// deterministic and copyright-free.

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

let SR = 44_100.0

func dB(_ linear: Double) -> Double { 20 * log10(max(linear, 1e-12)) }

// MARK: - Fixtures

func makeSong(
    title: String,
    bpm: Int? = 124,
    key: String? = "Am",
    durationSeconds: Double = 160,
    bpmConfidence: Double? = nil,
    keyConfidence: Double? = nil
) -> MixrTrack {
    let length = MixrTimeline.units(fromSeconds: min(durationSeconds, 180))
    return MixrTrack(
        id: UUID(),
        title: title,
        artist: "Fixture",
        duration: "--:--",
        durationSeconds: durationSeconds,
        bpm: bpm,
        bpmConfidence: bpmConfidence,
        key: key,
        keyConfidence: keyConfidence,
        color: .pink,
        volume: 1.0,
        isMuted: false,
        url: nil,
        artworkData: nil,
        clips: [MixrClip(id: UUID(), start: 0, length: length)]
    )
}

/// Section-shaped amplitude profile mirroring the analyzer's structural
/// fractions, so montage-style plans land on contrasting levels the way
/// they do on real songs (quiet intro/bridge/outro, loud choruses).
func sectionAmplitude(at t: Double, duration: Double) -> Float {
    let phrase = (60.0 / 124.0) * 4 * 8
    func snap(_ x: Double) -> Double { (x / phrase).rounded(.down) * phrase }
    let introEnd = min(phrase * 2, duration * 0.20)
    let chorus1 = max(introEnd, snap(duration * 0.28))
    let chorus2 = max(chorus1 + phrase, snap(duration * 0.60))
    let bridge = max(chorus2 + phrase, snap(duration * 0.76))
    let outro = max(introEnd, snap(duration - phrase))

    if t < introEnd { return 0.14 }
    if t >= outro { return 0.18 }
    if t >= chorus1 && t < chorus1 + phrase { return 0.80 }
    if t >= chorus2 && t < chorus2 + phrase { return 0.80 }
    if t >= bridge && t < bridge + phrase { return 0.22 }
    return 0.50
}

/// Deterministic synthetic song: 220 Hz body tone with beat clicks on the
/// BPM grid, section-shaped dynamics, optional silent edges and quiet
/// holes, and a configurable first-downbeat offset.
func syntheticSong(
    durationSeconds: Double,
    bpm: Double = 124,
    leadingSilence: Double = 0,
    trailingSilence: Double = 0,
    downbeatOffset: Double = 0,
    quietRegions: [(Double, Double)] = [],
    flatAmplitude: Float? = nil,
    sampleRate: Double = SR
) -> [Float] {
    let n = Int(durationSeconds * sampleRate)
    var out = [Float](repeating: 0, count: n)
    let beat = 60.0 / bpm
    let clickLen = Int(0.006 * sampleRate)

    for i in 0..<n {
        let t = Double(i) / sampleRate
        guard t >= leadingSilence, t < durationSeconds - trailingSilence else { continue }
        var amp = flatAmplitude ?? sectionAmplitude(at: t, duration: durationSeconds)
        for q in quietRegions where t >= q.0 && t < q.1 { amp *= 0.05 }
        out[i] = amp * Float(sin(2 * .pi * 220.0 * t))
    }
    // Beat clicks from the first downbeat (offset), 2 kHz shaped bursts.
    var clickT = leadingSilence + downbeatOffset
    while clickT < durationSeconds - trailingSilence {
        let start = Int(clickT * sampleRate)
        for j in 0..<clickLen {
            let idx = start + j
            guard idx >= 0, idx < n else { continue }
            let x = Double(j) / Double(clickLen)
            let window = Float(0.5 * (1 - cos(2 * .pi * x)))
            let amp = flatAmplitude ?? sectionAmplitude(at: clickT, duration: durationSeconds)
            out[idx] += 0.45 * amp * window * Float(sin(2 * .pi * 2000.0 * (Double(j) / sampleRate)))
        }
        clickT += beat
    }
    return out
}

/// Hand-built signal features for plan-level tests (independent of the
/// extractor): a song with silent edges and a confident beat grid.
func makeFeatures(
    duration: Double,
    leadingSilence: Double,
    trailingSilence: Double,
    bpm: Double = 124,
    confidence: Double = 0.85
) -> SongSignalFeatures {
    let hop = SongSignalAnalyzer.hopSeconds
    let hops = Int(duration / hop)
    var rms = [Double](repeating: -12, count: hops)
    var energy = [Double](repeating: 0.7, count: hops)
    for i in 0..<hops {
        let t = Double(i) * hop
        if t < leadingSilence || t >= duration - trailingSilence {
            rms[i] = -80
            energy[i] = 0
        }
    }
    return SongSignalFeatures(
        sampleRate: SR,
        durationSeconds: duration,
        rmsCurveDB: rms,
        onsetStrength: [Double](repeating: 0.5, count: hops),
        hopSeconds: hop,
        downbeatOffsetSeconds: leadingSilence,
        beatConfidence: confidence,
        leadingSilenceSeconds: leadingSilence,
        trailingSilenceSeconds: trailingSilence,
        quietRegions: [],
        energyCurve: energy,
        bassEnergyCurve: [Double](repeating: 0.6, count: hops),
        vocalPresenceCurve: [Double](repeating: 0.5, count: hops),
        noveltyCurve: [Double](repeating: 0.2, count: hops),
        drumConfidence: 0.8,
        overallConfidence: confidence
    )
}

func justifiedReturns(_ plan: AutoRemixPlan) -> [Double] {
    plan.cutRecords.filter { $0.reason == .hookReturn }.map(\.timelineAt)
}

// MARK: - 1. Meter self-tests (instrumentation must be trustworthy)

do {
    let tone = (0..<Int(SR * 2)).map { Float(0.25 * sin(2 * .pi * 440 * Double($0) / SR)) }
    let level = AutoRemixDiagnostics.meanLoudnessDB(samples: tone, sampleRate: SR, from: 0.2, to: 1.8)
    check("Meter: RMS of 0.25 sine ≈ −15 dBFS", abs(level - dB(0.25 / 2.0.squareRoot())) < 0.3,
          String(format: "%.2f dB", level))

    var holed = tone
    for i in Int(SR * 0.9)..<Int(SR * 1.2) { holed[i] = 0 }
    let runs = AutoRemixDiagnostics.silenceRuns(samples: holed, sampleRate: SR, thresholdDB: -45, minSeconds: 0.1)
    check("Meter: silence detector finds a 300 ms hole",
          runs.contains { abs($0.start - 0.9) < 0.05 && abs($0.end - 1.2) < 0.05 },
          "\(runs.map { ($0.start, $0.end) })")

    var stepped = [Float](repeating: 0, count: 4410)
    for i in 2205..<4410 { stepped[i] = 0.9 }
    let jump = AutoRemixDiagnostics.maxAdjacentSampleJump(samples: stepped, sampleRate: SR)
    check("Meter: click detector finds a 0.9 step", abs(jump.jump - 0.9) < 0.001)

    // fs/4 sine at 45°: samples all ±0.707 but the waveform reaches 1.0
    // between samples — the true-peak meter must see it.
    let isp = (0..<4096).map { Float(sin(.pi / 2 * Double($0) + .pi / 4)) }
    let spDB = dB(Double(AutoRemixDiagnostics.samplePeak(isp)))
    let tpDB = AutoRemixDiagnostics.truePeakDB(samples: isp, sampleRate: SR)
    check("Meter: true peak sees inter-sample peaks", tpDB > spDB + 2,
          String(format: "sample %.2f dB, true %.2f dB", spDB, tpDB))

    let loud = AutoRemixDiagnostics.integratedLoudnessApproxDB(samples: tone, sampleRate: SR)
    check("Meter: integrated loudness of steady tone tracks RMS", abs(loud - (-15.05)) < 0.6,
          String(format: "%.2f dB", loud))
}

// MARK: - 2. Shared envelope model (live/export parity by construction)

do {
    let fade = ClipTransition(type: .crossfade, duration: 4, curve: AutoTransitionEnvelope.equalPowerCurveName)
    let clipStart = 10.0, clipEnd = 20.0, bpm = 120.0
    let fadeSeconds = 4 * 60.0 / bpm

    let midIn = AutoTransitionEnvelope.envelope(
        transitionIn: fade, transitionOut: .none,
        clipStart: clipStart, clipEnd: clipEnd,
        at: clipStart + fadeSeconds / 2, bpm: bpm
    ).gain
    check("Equal-power fade midpoint is −3 dB", abs(dB(midIn) - (-3.01)) < 0.1,
          String(format: "%.2f dB", dB(midIn)))

    var powerSumOK = true
    for i in 0...20 {
        let x = Double(i) / 20
        let inG = AutoTransitionEnvelope.fadeInGain(progress: x, curve: AutoTransitionEnvelope.equalPowerCurveName)
        let outG = AutoTransitionEnvelope.fadeOutGain(progress: 1 - x, curve: AutoTransitionEnvelope.equalPowerCurveName)
        if abs(inG * inG + outG * outG - 1.0) > 1e-9 { powerSumOK = false }
    }
    check("Equal-power in²+out² ≡ 1 across the fade", powerSumOK)

    // Live tick (60 fps) and export blocks (1024 frames) sample the SAME
    // function: values at identical times must match exactly, and block
    // sampling introduces no step larger than the curve's own slope.
    var parityOK = true
    var maxBlockStep = 0.0
    let blockDT = 1024.0 / SR
    var t = clipStart
    var prev: Double?
    while t < clipStart + fadeSeconds {
        let live = AutoTransitionEnvelope.envelope(
            transitionIn: fade, transitionOut: .none,
            clipStart: clipStart, clipEnd: clipEnd, at: t, bpm: bpm
        ).gain
        let export = AutoTransitionEnvelope.envelope(
            transitionIn: fade, transitionOut: .none,
            clipStart: clipStart, clipEnd: clipEnd, at: t, bpm: bpm
        ).gain
        if live != export { parityOK = false }
        if let p = prev { maxBlockStep = max(maxBlockStep, abs(live - p)) }
        prev = live
        t += blockDT
    }
    check("Live and export share one envelope model", parityOK)
    check("Block-rate envelope steps stay ramp-sized",
          maxBlockStep < (.pi / 2) * blockDT / fadeSeconds + 1e-6,
          String(format: "max step %.5f", maxBlockStep))
}

// MARK: - 3. One-song plan shape: preservation-first (confident input)

var confidentPlan: AutoRemixPlan?
var confidentSong: MixrTrack?
do {
    let song = makeSong(title: "Confident Song")
    confidentSong = song
    let outcome = AutoRemixRunner.runEntireProject(tracks: [song], seed: 42)
    switch outcome {
    case .success(_, let plan, _):
        confidentPlan = plan
        let cuts = AutoRemixDiagnostics.internalCutBoundaries(placements: plan.placements)
        check("One song: zero internal cuts by default", cuts.isEmpty, "got \(cuts.count) cuts")

        let minutes = max(plan.targetDuration / 60.0, 0.01)
        check("One song: cut budget ≤ 2 per minute",
              Double(cuts.count) <= 2.0 * minutes + 0.001,
              String(format: "%d cuts in %.1f min", cuts.count, minutes))

        check("One song: every internal cut has a structured record",
              cuts.allSatisfy { cut in
                  plan.cutRecords.contains { abs($0.timelineAt - cut) < 0.1 }
              },
              "\(cuts.count) cuts, \(plan.cutRecords.count) records")

        check("One song: source order monotonic unless a justified return",
              AutoRemixDiagnostics.sourceOrderIsMonotonic(
                  placements: plan.placements,
                  justifiedReturnStarts: justifiedReturns(plan)
              ))

        check("One song: no automatic pre-drop silence", plan.intentionalGaps.isEmpty,
              "\(plan.intentionalGaps.count) gaps")

        let pitched = plan.placements.filter { $0.effects.pitchAmount > 0.005 }
        check("One song: no random pitch section by default", pitched.isEmpty,
              "\(pitched.count) pitched placements")

        let dominants = plan.placements.filter { $0.role == .dominant }
        check("One song: far fewer clip boundaries than the montage",
              dominants.count <= 6, "got \(dominants.count) placements")

        check("One song: plan records the usable source range",
              plan.usableSourceRange != nil)

        let sfxPerMinute = Double(plan.sfxEvents.count) / minutes
        check("One song: SFX density bounded by musical need (≤ 3/min)",
              sfxPerMinute <= 3.0 + 0.001,
              String(format: "%.1f events/min", sfxPerMinute))
    case .failure(let message):
        check("Confident one-song remix plans", false, message)
    }
}

// MARK: - 4. Rendered PCM gates (confident one-song plan)

if let plan = confidentPlan, let song = confidentSong {
    let source = AutoOfflineMixdown.Source(
        samples: syntheticSong(durationSeconds: song.durationSeconds ?? 160),
        sampleRate: SR
    )
    let result = AutoOfflineMixdown.render(
        plan: plan,
        sources: [song.id: source],
        sampleRate: SR
    )
    let pcm = result.mix
    let contentStart = plan.placements.map(\.timelineStart).min() ?? 0
    let contentEnd = plan.placements.map(\.timelineEnd).max() ?? 0

    check("Render: no clipped samples in pre-encode PCM",
          AutoRemixDiagnostics.clippedSampleCount(pcm) == 0)

    let truePeak = AutoRemixDiagnostics.truePeakDB(samples: pcm, sampleRate: SR)
    check("Render: true peak ≤ −1 dBTP",
          truePeak <= AutoGainPolicy.truePeakCeilingDB + 0.2,
          String(format: "%.2f dBTP", truePeak))

    check("Render: limiter is safety, not glue (GR ≤ 3 dB)",
          result.limiterGainReductionDB <= AutoGainPolicy.maxSustainedLimiterReductionDB,
          String(format: "%.1f dB reduction", result.limiterGainReductionDB))

    let silences = AutoRemixDiagnostics.silenceRuns(
        samples: pcm, sampleRate: SR, thresholdDB: -45, minSeconds: 0.1
    ).filter { $0.start > contentStart + 0.5 && $0.end < contentEnd - 0.5 }
    check("Render: no unintended silence ≥ 100 ms inside musical content",
          silences.isEmpty,
          silences.prefix(4).map { String(format: "%.2f–%.2fs", $0.start, $0.end) }.joined(separator: ", "))

    let cutBoundaries = AutoRemixDiagnostics.internalCutBoundaries(placements: plan.placements)
    var worstTrough = 0.0
    var worstUnexplainedJump = 0.0
    for boundary in cutBoundaries {
        let b = AutoRemixDiagnostics.boundaryLoudness(samples: pcm, sampleRate: SR, boundarySeconds: boundary)
        worstTrough = max(worstTrough, b.centerTroughDB)
        let explained = plan.cutRecords.contains {
            abs($0.timelineAt - boundary) < 0.1 && abs($0.expectedEnergyDeltaDB) + 2.0 >= b.jumpDB
        }
        if !explained { worstUnexplainedJump = max(worstUnexplainedJump, b.jumpDB) }
    }
    check("Render: no join-centered trough > 3 dB",
          worstTrough <= 3.0, String(format: "worst %.1f dB", worstTrough))
    check("Render: no unexplained join jump > 4 dB",
          worstUnexplainedJump <= 4.0, String(format: "worst %.1f dB", worstUnexplainedJump))

    let click = AutoRemixDiagnostics.maxAdjacentSampleJump(samples: pcm, sampleRate: SR)
    check("Render: no sample discontinuity above click threshold",
          click.jump <= 0.5,
          String(format: "%.3f at %.2fs", click.jump, click.atSeconds))

    // The export must never end in silence: either the tail is audible
    // effect decay, or the file stops when the tail dies.
    let tailStart = max(0.0, Double(pcm.count) / SR - 0.25)
    let tailLevel = AutoRemixDiagnostics.meanLoudnessDB(
        samples: pcm, sampleRate: SR, from: tailStart, to: Double(pcm.count) / SR
    )
    check("Render: no fixed silent export tail",
          tailLevel > AutoGainPolicy.silentTailThresholdDB,
          String(format: "last 250 ms at %.1f dBFS", tailLevel))
}

// MARK: - 5. True equal-power crossfade with real overlap

do {
    let song = makeSong(title: "Overlap Song", durationSeconds: 60)
    let profiles = [song.id: AutoSectionCatalog.profile(track: song)]
    let equalPower = AutoTransitionEnvelope.equalPowerCurveName
    let bpm = 124.0
    let crossfade = 2.0
    let beats = crossfade / (60.0 / bpm)

    var plan = AutoRemixPlan(
        mode: .remix,
        targetBPM: bpm,
        targetDuration: 22,
        anchorSongIDs: [song.id],
        selectedSections: [],
        placements: [
            AutoClipPlacement(
                songID: song.id, sourceStart: 0, timelineStart: 0, timelineDuration: 12,
                tempoRatio: 1, volume: 0.9,
                fadeIn: .none,
                fadeOut: ClipTransition(type: .crossfade, duration: beats, curve: equalPower),
                effects: ClipEffectSettings(), role: .dominant, slotIndex: 0
            ),
            AutoClipPlacement(
                songID: song.id, sourceStart: 30, timelineStart: 10, timelineDuration: 12,
                tempoRatio: 1, volume: 0.9,
                fadeIn: ClipTransition(type: .crossfade, duration: beats, curve: equalPower),
                fadeOut: .none,
                effects: ClipEffectSettings(), role: .dominant, slotIndex: 1,
                overlapsPreviousSeconds: crossfade
            ),
        ],
        sfxEvents: [],
        handoffCount: 0,
        songLetters: [song.id: "A"],
        sequence: ["A", "A"],
        transitionsUsed: [],
        decisions: [],
        warnings: [],
        confidence: 0.9,
        randomSeed: 1
    )
    plan.cutRecords = [
        AutoCutRecord(
            timelineAt: 10, sourceFrom: 12, sourceTo: 30,
            reason: .redundantRepeat, confidence: 0.9,
            expectedEnergyDeltaDB: 0,
            masking: .equalPowerCrossfade(seconds: crossfade)
        )
    ]

    // The validator must PRESERVE a declared equal-power overlap.
    let validated = AutoRemixValidator.validate(plan, profiles: profiles, tuning: .standard)
    let sorted = validated.placements.sorted { $0.timelineStart < $1.timelineStart }
    let overlapKept = sorted.count == 2
        && abs(sorted[0].timelineEnd - 12.0) < 0.05
        && abs(sorted[1].timelineStart - 10.0) < 0.05
    check("Validator preserves a declared same-song crossfade overlap", overlapKept,
          sorted.map { String(format: "[%.2f–%.2f]", $0.timelineStart, $0.timelineEnd) }.joined(separator: " "))
    check("Validator keeps the cut record for the masked cut",
          !validated.cutRecords.isEmpty)

    // Rendered: constant-level material through an equal-power crossfade
    // must not dip at the join center.
    let flat = AutoOfflineMixdown.Source(
        samples: syntheticSong(durationSeconds: 60, flatAmplitude: 0.5),
        sampleRate: SR
    )
    let rendered = AutoOfflineMixdown.render(
        plan: plan, sources: [song.id: flat], sampleRate: SR, includeTail: false
    )
    let boundary = AutoRemixDiagnostics.boundaryLoudness(
        samples: rendered.mix, sampleRate: SR, boundarySeconds: 11.0
    )
    check("Equal-power overlap holds level through the join (≤ 1.2 dB)",
          boundary.centerTroughDB <= 1.2,
          String(format: "trough %.2f dB", boundary.centerTroughDB))
}

// MARK: - 6. Dual fade-to-silence at one boundary is repaired

do {
    let song = makeSong(title: "Dual Fade Song", durationSeconds: 60)
    let profiles = [song.id: AutoSectionCatalog.profile(track: song)]
    let plan = AutoRemixPlan(
        mode: .remix,
        targetBPM: 124,
        targetDuration: 24,
        anchorSongIDs: [song.id],
        selectedSections: [],
        placements: [
            AutoClipPlacement(
                songID: song.id, sourceStart: 0, timelineStart: 0, timelineDuration: 12,
                tempoRatio: 1, volume: 0.9,
                fadeIn: .none,
                fadeOut: ClipTransition(type: .fadeOut, duration: 4),
                effects: ClipEffectSettings(), role: .dominant, slotIndex: 0
            ),
            AutoClipPlacement(
                songID: song.id, sourceStart: 30, timelineStart: 12, timelineDuration: 12,
                tempoRatio: 1, volume: 0.9,
                fadeIn: ClipTransition(type: .crossfade, duration: 4),
                fadeOut: .none,
                effects: ClipEffectSettings(), role: .dominant, slotIndex: 1
            ),
        ],
        sfxEvents: [],
        handoffCount: 0,
        songLetters: [song.id: "A"],
        sequence: ["A", "A"],
        transitionsUsed: [],
        decisions: [],
        warnings: [],
        confidence: 0.9,
        randomSeed: 1
    )

    let validated = AutoRemixValidator.validate(plan, profiles: profiles, tuning: .standard)
    let sorted = validated.placements.sorted { $0.timelineStart < $1.timelineStart }
    var holeFree = true
    for pair in zip(sorted, sorted.dropFirst()) {
        let sequential = pair.1.timelineStart >= pair.0.timelineEnd - 0.05
        let outFades = [ClipTransitionType.fadeOut, .crossfade, .auto].contains(pair.0.fadeOut.type)
            && pair.0.fadeOut.duration > 0.5
        let inFades = [ClipTransitionType.crossfade, .auto].contains(pair.1.fadeIn.type)
            && pair.1.fadeIn.duration > 0.5
        if sequential && outFades && inFades && pair.1.overlapsPreviousSeconds <= 0 {
            holeFree = false
        }
    }
    check("Validator repairs sequential fade-out + fade-in (level hole)", holeFree)
}

// MARK: - 7. Signal analysis is measured, not seeded

do {
    let bpm = 120.0
    let samples = syntheticSong(
        durationSeconds: 30,
        bpm: bpm,
        leadingSilence: 3.0,
        downbeatOffset: 0.37,
        quietRegions: [(15.0, 16.2)],
        flatAmplitude: 0.5
    )
    let features = SongSignalAnalyzer.extract(samples: samples, sampleRate: SR, bpmHint: bpm)

    check("Analysis: energy curve is measured (non-empty)", !features.energyCurve.isEmpty)
    check("Analysis: leading silence detected",
          abs(features.leadingSilenceSeconds - 3.0) < 0.4,
          String(format: "%.2fs", features.leadingSilenceSeconds))
    check("Analysis: first downbeat found away from t = 0",
          features.downbeatOffsetSeconds.map { abs($0 - 3.37) < 0.1 } ?? false,
          features.downbeatOffsetSeconds.map { String(format: "%.3fs", $0) } ?? "nil")
    check("Analysis: beat grid carries confidence",
          features.beatConfidence > 0.5,
          String(format: "%.2f", features.beatConfidence))
    check("Analysis: interior quiet region detected",
          features.quietRegions.contains { abs($0.start - 15.0) < 0.4 && abs($0.end - 16.2) < 0.4 },
          "\(features.quietRegions.map { ($0.start, $0.end) })")
    check("Analysis: overall confidence reflects clean fixture",
          features.overallConfidence > 0.5,
          String(format: "%.2f", features.overallConfidence))

    let again = SongSignalAnalyzer.extract(samples: samples, sampleRate: SR, bpmHint: bpm)
    check("Analysis: extraction is deterministic",
          features.energyCurve == again.energyCurve
              && features.downbeatOffsetSeconds == again.downbeatOffsetSeconds)
}

// MARK: - 8. Evidence-based edge trimming (no phrase amputation)

do {
    let song = makeSong(title: "Padded Song", durationSeconds: 160)
    let features = makeFeatures(duration: 160, leadingSilence: 6, trailingSilence: 4)
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 7, signals: [song.id: features]
    )
    switch outcome {
    case .success(_, let plan, _):
        let dominants = plan.placements
            .filter { $0.role == .dominant }
            .sorted { $0.timelineStart < $1.timelineStart }
        let firstSource = dominants.first?.sourceStart ?? -1
        let lastSource = dominants.last?.sourceEnd ?? -1
        check("Trim: leading silence removed without cutting music",
              firstSource >= 5.2 && firstSource <= 7.5,
              String(format: "starts at %.2fs", firstSource))
        check("Trim: trailing silence removed, song body kept",
              lastSource >= 148.0 && lastSource <= 156.5,
              String(format: "ends at %.2fs", lastSource))
        check("Trim: usable range recorded",
              plan.usableSourceRange.map { $0.lowerBound >= 5.0 && $0.upperBound <= 157.0 } ?? false)
    case .failure(let message):
        check("Padded song plans", false, message)
    }
}

// MARK: - 9. Low confidence → nearly continuous, minimal processing

do {
    let song = makeSong(title: "Unknown Tempo", bpm: nil, key: nil, durationSeconds: 150)
    let outcome = AutoRemixRunner.runEntireProject(tracks: [song], seed: 11)
    switch outcome {
    case .success(_, let plan, _):
        let cuts = AutoRemixDiagnostics.internalCutBoundaries(placements: plan.placements)
        check("Low confidence: zero internal cuts", cuts.isEmpty, "got \(cuts.count)")
        check("Low confidence: nearly continuous (≤ 3 placements)",
              plan.placements.filter { $0.role == .dominant }.count <= 3,
              "got \(plan.placements.count)")
        check("Low confidence: no intentional silence", plan.intentionalGaps.isEmpty)
        check("Low confidence: minimal SFX (≤ 1)", plan.sfxEvents.count <= 1,
              "got \(plan.sfxEvents.count)")
    case .failure(let message):
        check("Low-confidence one-song input still produces a remix", false, message)
    }
}

// MARK: - 10. Multi-edit path: measured lift → segments + SFX (end-to-end)
//
// Guards against trivially-green results: the planner must still make
// MEANINGFUL edits (source-continuous effect segments, coordinated SFX)
// when the signal supports them — and those edits must pass the same
// continuity and loudness gates as the untouched path.

do {
    let song = makeSong(title: "Lift Song", durationSeconds: 160)
    let pcm = syntheticSong(durationSeconds: 160, leadingSilence: 2.0)
    let features = SongSignalAnalyzer.extract(samples: pcm, sampleRate: SR, bpmHint: 124)
    check("Multi-edit: extractor trusts the clean fixture",
          features.overallConfidence > 0.5 && features.beatConfidence > 0.4,
          String(format: "overall %.2f beat %.2f", features.overallConfidence, features.beatConfidence))

    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 33, signals: [song.id: features]
    )
    switch outcome {
    case .success(_, let plan, _):
        let dominants = plan.placements
            .filter { $0.role == .dominant }
            .sorted { $0.timelineStart < $1.timelineStart }

        // The system must actually DO something here: multiple
        // interventions, every source discontinuity recorded and masked.
        check("Multi-edit: planner makes multiple interventions",
              dominants.count >= 3, "got \(dominants.count)")
        let cuts = AutoRemixDiagnostics.internalCutBoundaries(placements: plan.placements)
        check("Multi-edit: every cut carries a structured record",
              cuts.allSatisfy { cut in plan.cutRecords.contains { abs($0.timelineAt - cut) < 0.1 } },
              "\(cuts.count) cuts, \(plan.cutRecords.count) records")
        check("Multi-edit: structural budget respected",
              (plan.remixRecipe?.structuralCount ?? 0) <= 2)
        check("Multi-edit: SFX only riser/impact, bound to zones",
              plan.sfxEvents.allSatisfy {
                  ["riser", "impact"].contains($0.assetID) && $0.transformationID != nil
              },
              "\(plan.sfxEvents.map(\.assetID))")
        let minutes = max(plan.targetDuration / 60, 0.01)
        check("Multi-edit: SFX density still bounded",
              Double(plan.sfxEvents.count) / minutes <= 3.0)
        check("Multi-edit: meaningful transformations selected",
              (plan.remixRecipe?.meaningfulCount ?? 0) >= 1,
              "got \(plan.remixRecipe?.meaningfulCount ?? 0)")

        let result = AutoOfflineMixdown.render(
            plan: plan, sources: [song.id: AutoOfflineMixdown.Source(samples: pcm, sampleRate: SR)],
            sampleRate: SR
        )
        let mix = result.mix

        check("Multi-edit: no clipped samples with SFX in the mix",
              AutoRemixDiagnostics.clippedSampleCount(mix) == 0)
        let truePeak = AutoRemixDiagnostics.truePeakDB(samples: mix, sampleRate: SR)
        check("Multi-edit: true peak ≤ −1 dBTP with SFX",
              truePeak <= AutoGainPolicy.truePeakCeilingDB + 0.2,
              String(format: "%.2f dBTP", truePeak))
        check("Multi-edit: limiter stays a safety layer with SFX",
              result.limiterGainReductionDB <= AutoGainPolicy.maxSustainedLimiterReductionDB,
              String(format: "%.1f dB", result.limiterGainReductionDB))

        // Every internal boundary — continuous split or masked cut —
        // must hold level through its center.
        var worstSplitTrough = 0.0
        for p in dominants.dropFirst() {
            let boundary = p.overlapsPreviousSeconds > 0
                ? p.timelineStart + p.overlapsPreviousSeconds / 2
                : p.timelineStart
            let b = AutoRemixDiagnostics.boundaryLoudness(
                samples: mix, sampleRate: SR, boundarySeconds: boundary
            )
            worstSplitTrough = max(worstSplitTrough, b.centerTroughDB)
        }
        check("Multi-edit: segment splits hold level (trough ≤ 3 dB)",
              worstSplitTrough <= 3.0, String(format: "worst %.1f dB", worstSplitTrough))

        let contentStart = dominants.first?.timelineStart ?? 0
        let contentEnd = dominants.last?.timelineEnd ?? 0
        let silences = AutoRemixDiagnostics.silenceRuns(
            samples: mix, sampleRate: SR, thresholdDB: -45, minSeconds: 0.1
        ).filter { $0.start > contentStart + 0.5 && $0.end < contentEnd - 0.5 }
        check("Multi-edit: no silence holes with edits present", silences.isEmpty)

        // Join-click gate on the SONG bus (synthetic noise SFX have large
        // legitimate sample deltas; the click gate targets song joins).
        let click = AutoRemixDiagnostics.maxAdjacentSampleJump(samples: result.songBus, sampleRate: SR)
        check("Multi-edit: no click at segment boundaries (song bus)",
              click.jump <= 0.5, String(format: "%.3f at %.2fs", click.jump, click.atSeconds))
    case .failure(let message):
        check("Multi-edit lift fixture plans", false, message)
    }
}

// MARK: - 11. Multi-edit path: masked internal cut passes the full battery

do {
    let song = makeSong(title: "Masked Cut Song", durationSeconds: 80)
    let profiles = [song.id: AutoSectionCatalog.profile(track: song)]
    let equalPower = AutoTransitionEnvelope.equalPowerCurveName
    let bpm = 124.0
    let beatSec = 60.0 / bpm
    let crossfade = 1.5
    let beats = crossfade / beatSec

    var echoFX = ClipEffectSettings()
    echoFX.setLevel(15, for: MixrEffect.echo.rawValue)

    var plan = AutoRemixPlan(
        mode: .remix,
        targetBPM: bpm,
        targetDuration: 38.5,
        anchorSongIDs: [song.id],
        selectedSections: [],
        placements: [
            AutoClipPlacement(
                songID: song.id, sourceStart: 0, timelineStart: 0, timelineDuration: 20,
                tempoRatio: 1, volume: 0.9,
                fadeIn: .none,
                fadeOut: ClipTransition(type: .crossfade, duration: beats, curve: equalPower),
                effects: ClipEffectSettings(), role: .dominant, slotIndex: 0
            ),
            AutoClipPlacement(
                songID: song.id, sourceStart: 40, timelineStart: 18.5, timelineDuration: 11.5,
                tempoRatio: 1, volume: 0.9,
                fadeIn: ClipTransition(type: .crossfade, duration: beats, curve: equalPower),
                fadeOut: .none,
                effects: ClipEffectSettings(), role: .dominant, slotIndex: 1,
                overlapsPreviousSeconds: crossfade
            ),
            AutoClipPlacement(
                songID: song.id, sourceStart: 51.5, timelineStart: 30, timelineDuration: 8.5,
                tempoRatio: 1, volume: 0.9,
                fadeIn: .none, fadeOut: .none,
                effects: AutoSupportedEffects.sanitize(echoFX), role: .dominant, slotIndex: 2,
                continuesPrevious: true
            ),
        ],
        sfxEvents: [
            AutoSFXEvent(assetID: "riser", timelineStart: 14.5, purpose: "riser masking the cut"),
            AutoSFXEvent(assetID: "impact", timelineStart: 18.5, purpose: "impact on the incoming downbeat"),
        ],
        handoffCount: 0,
        songLetters: [song.id: "A"],
        sequence: ["A", "A", "A"],
        transitionsUsed: [],
        decisions: [],
        warnings: [],
        confidence: 0.9,
        randomSeed: 2
    )
    plan.cutRecords = [
        AutoCutRecord(
            timelineAt: 18.5, sourceFrom: 20, sourceTo: 40,
            reason: .redundantRepeat, confidence: 0.9,
            expectedEnergyDeltaDB: 0,
            masking: .equalPowerCrossfade(seconds: crossfade)
        )
    ]

    let validated = AutoRemixValidator.validate(plan, profiles: profiles, tuning: .standard)
    check("Masked cut: validator keeps all three placements",
          validated.placements.filter { $0.role == .dominant }.count == 3,
          "got \(validated.placements.count)")
    let cuts = AutoRemixDiagnostics.internalCutBoundaries(placements: validated.placements)
    check("Masked cut: exactly one internal cut survives",
          cuts.count == 1 && abs((cuts.first ?? 0) - 18.5) < 0.1, "\(cuts)")
    check("Masked cut: record retained by the validator",
          !validated.cutRecords.isEmpty)

    let source = AutoOfflineMixdown.Source(
        samples: syntheticSong(durationSeconds: 80, flatAmplitude: 0.5),
        sampleRate: SR
    )
    let result = AutoOfflineMixdown.render(
        plan: validated, sources: [song.id: source], sampleRate: SR
    )
    let mix = result.mix

    check("Masked cut: no clipped samples",
          AutoRemixDiagnostics.clippedSampleCount(mix) == 0)
    check("Masked cut: limiter GR ≤ 3 dB",
          result.limiterGainReductionDB <= 3.0,
          String(format: "%.1f dB", result.limiterGainReductionDB))

    var worstTrough = 0.0
    var worstUnexplained = 0.0
    for cut in cuts {
        let b = AutoRemixDiagnostics.boundaryLoudness(samples: mix, sampleRate: SR, boundarySeconds: cut)
        worstTrough = max(worstTrough, b.centerTroughDB)
        let explained = validated.cutRecords.contains {
            abs($0.timelineAt - cut) < 0.1 && abs($0.expectedEnergyDeltaDB) + 2.0 >= b.jumpDB
        }
        if !explained { worstUnexplained = max(worstUnexplained, b.jumpDB) }
    }
    // The continuity split at t=30 must hold level too.
    let split = AutoRemixDiagnostics.boundaryLoudness(samples: mix, sampleRate: SR, boundarySeconds: 30)
    worstTrough = max(worstTrough, split.centerTroughDB)

    check("Masked cut: crossfaded join holds level (trough ≤ 3 dB)",
          worstTrough <= 3.0, String(format: "worst %.1f dB", worstTrough))
    check("Masked cut: join jump explained by its record (≤ 4 dB unexplained)",
          worstUnexplained <= 4.0, String(format: "worst %.1f dB", worstUnexplained))

    let silences = AutoRemixDiagnostics.silenceRuns(
        samples: mix, sampleRate: SR, thresholdDB: -45, minSeconds: 0.1
    ).filter { $0.start > 0.5 && $0.end < 38.0 }
    check("Masked cut: no silence holes through cut and split", silences.isEmpty)

    let click = AutoRemixDiagnostics.maxAdjacentSampleJump(samples: result.songBus, sampleRate: SR)
    check("Masked cut: no click at join or split (song bus)",
          click.jump <= 0.5, String(format: "%.3f at %.2fs", click.jump, click.atSeconds))
}

// MARK: - 12. Ducking policy shape (unit)

do {
    let events = [AutoSFXEvent(assetID: "impact", timelineStart: 10.0, purpose: "")]
    let floorGain = pow(10.0, -AutoGainPolicy.duckDepthDB / 20.0)

    check("Duck: unity before the attack window",
          AutoGainPolicy.duckGain(at: 9.9, sfxEvents: events) > 0.999)
    let atImpact = AutoGainPolicy.duckGain(at: 10.0, sfxEvents: events)
    check("Duck: full depth at the impact",
          abs(atImpact - floorGain) < 0.01,
          String(format: "%.3f vs %.3f", atImpact, floorGain))
    check("Duck: fully released after hold + release",
          AutoGainPolicy.duckGain(at: 10.0 + AutoGainPolicy.duckHoldSeconds + AutoGainPolicy.duckReleaseSeconds + 0.01, sfxEvents: events) > 0.999)

    var maxStep = 0.0
    var t = 9.8
    var prev = AutoGainPolicy.duckGain(at: t, sfxEvents: events)
    while t < 10.7 {
        t += 0.005
        let g = AutoGainPolicy.duckGain(at: t, sfxEvents: events)
        maxStep = max(maxStep, abs(g - prev))
        prev = g
    }
    check("Duck: ramp is smooth (≤ 0.05 per 5 ms)", maxStep <= 0.05,
          String(format: "max step %.3f", maxStep))
}

// MARK: - Structured-pop fixture (transformation-layer tests)
//
// A deterministic pop arrangement with real measured structure: distinct
// per-section levels, bass, vocal-band activity patterns, and transient
// density, so similarity / hook differentiation / vocal protection are
// exercised against MEASURED curves, never hard-coded song knowledge.

struct PopSection {
    var name: String
    var bars: Int
    var level: Float          // body tone amplitude factor
    var bass: Float           // 80 Hz band factor
    var vocal: Float          // 800 Hz "vocal" band factor
    var vocalPattern: Int     // 0 = none; else 8th-note activity mask id
    var hitsPerBar: Int       // transient hits per bar
}

let popBPM = 132.0

let vocalMasks: [[Int]] = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [1, 0, 1, 1, 0, 1, 0, 0],   // verse phrasing
    [1, 1, 0, 0, 1, 0, 1, 0],   // pre-chorus phrasing
    [1, 1, 1, 0, 1, 1, 0, 1],   // chorus phrasing (dense)
]

func defaultPopScript() -> [PopSection] {
    [
        PopSection(name: "intro",   bars: 8,  level: 0.35, bass: 0.20, vocal: 0.00, vocalPattern: 0, hitsPerBar: 4),
        PopSection(name: "verse1",  bars: 8,  level: 0.50, bass: 0.40, vocal: 0.50, vocalPattern: 1, hitsPerBar: 4),
        PopSection(name: "pre1",    bars: 8,  level: 0.55, bass: 0.30, vocal: 0.40, vocalPattern: 2, hitsPerBar: 4),
        PopSection(name: "chorus1", bars: 16, level: 0.70, bass: 0.70, vocal: 0.60, vocalPattern: 3, hitsPerBar: 8),
        PopSection(name: "post1",   bars: 8,  level: 0.65, bass: 0.60, vocal: 0.00, vocalPattern: 0, hitsPerBar: 8),
        PopSection(name: "verse2",  bars: 8,  level: 0.50, bass: 0.40, vocal: 0.50, vocalPattern: 1, hitsPerBar: 4),
        PopSection(name: "pre2",    bars: 8,  level: 0.55, bass: 0.30, vocal: 0.40, vocalPattern: 2, hitsPerBar: 4),
        PopSection(name: "chorus2", bars: 16, level: 0.70, bass: 0.70, vocal: 0.60, vocalPattern: 3, hitsPerBar: 8),
        PopSection(name: "post2",   bars: 8,  level: 0.65, bass: 0.60, vocal: 0.00, vocalPattern: 0, hitsPerBar: 8),
        PopSection(name: "bridge",  bars: 8,  level: 0.25, bass: 0.15, vocal: 0.30, vocalPattern: 1, hitsPerBar: 4),
        PopSection(name: "chorus3", bars: 16, level: 0.875, bass: 0.80, vocal: 0.75, vocalPattern: 3, hitsPerBar: 8),
        PopSection(name: "outro",   bars: 12, level: 0.30, bass: 0.20, vocal: 0.00, vocalPattern: 0, hitsPerBar: 4),
    ]
}

/// Verses identical, choruses DIFFERENTIATED, single post-chorus — the
/// only near-duplicate pair is vocal-heavy.
func vocalRepeatScript() -> [PopSection] {
    [
        PopSection(name: "intro",   bars: 8,  level: 0.35, bass: 0.20, vocal: 0.00, vocalPattern: 0, hitsPerBar: 4),
        PopSection(name: "verse1",  bars: 16, level: 0.50, bass: 0.40, vocal: 0.55, vocalPattern: 1, hitsPerBar: 4),
        PopSection(name: "pre1",    bars: 8,  level: 0.55, bass: 0.30, vocal: 0.40, vocalPattern: 2, hitsPerBar: 4),
        PopSection(name: "chorus1", bars: 16, level: 0.70, bass: 0.70, vocal: 0.60, vocalPattern: 3, hitsPerBar: 8),
        PopSection(name: "verse2",  bars: 16, level: 0.50, bass: 0.40, vocal: 0.55, vocalPattern: 1, hitsPerBar: 4),
        PopSection(name: "chorus2", bars: 16, level: 0.85, bass: 0.80, vocal: 0.72, vocalPattern: 3, hitsPerBar: 8),
        PopSection(name: "outro",   bars: 12, level: 0.30, bass: 0.20, vocal: 0.00, vocalPattern: 0, hitsPerBar: 4),
    ]
}

/// Short, homogeneous, with a dull bridge: few valid opportunities.
func sparsePopScript() -> [PopSection] {
    [
        PopSection(name: "intro",   bars: 8,  level: 0.35, bass: 0.20, vocal: 0.00, vocalPattern: 0, hitsPerBar: 4),
        PopSection(name: "verse1",  bars: 16, level: 0.50, bass: 0.40, vocal: 0.50, vocalPattern: 1, hitsPerBar: 4),
        PopSection(name: "chorus1", bars: 16, level: 0.70, bass: 0.70, vocal: 0.60, vocalPattern: 3, hitsPerBar: 8),
        PopSection(name: "bridge",  bars: 8,  level: 0.12, bass: 0.06, vocal: 0.10, vocalPattern: 1, hitsPerBar: 2),
        PopSection(name: "chorus2", bars: 16, level: 0.85, bass: 0.80, vocal: 0.72, vocalPattern: 3, hitsPerBar: 8),
        PopSection(name: "outro",   bars: 8,  level: 0.30, bass: 0.20, vocal: 0.00, vocalPattern: 0, hitsPerBar: 4),
    ]
}

/// Default structure but the FINAL chorus is a near-duplicate and the
/// tempo drifts +2% from the bridge onward.
func driftPopScript() -> (script: [PopSection], driftAfterBar: Int) {
    var script = defaultPopScript()
    script[10] = PopSection(name: "chorus3", bars: 16, level: 0.70, bass: 0.70, vocal: 0.60, vocalPattern: 3, hitsPerBar: 8)
    let barsBeforeBridge = script.prefix(9).reduce(0) { $0 + $1.bars }
    return (script, barsBeforeBridge)
}

/// Bar length in seconds at bar index (drift-aware).
func popBarSeconds(_ barIndex: Int, bpm: Double, driftAfterBar: Int?, driftFactor: Double) -> Double {
    let base = 240.0 / bpm
    if let driftAfterBar, barIndex >= driftAfterBar { return base * driftFactor }
    return base
}

/// Source-second range of a named section occurrence.
func popSectionRange(
    _ sections: [PopSection],
    name: String,
    bpm: Double = popBPM,
    leadingSilence: Double = 1.0,
    driftAfterBar: Int? = nil,
    driftFactor: Double = 1.0
) -> (start: Double, end: Double) {
    var t = leadingSilence
    var barIndex = 0
    for section in sections {
        let start = t
        for _ in 0..<section.bars {
            t += popBarSeconds(barIndex, bpm: bpm, driftAfterBar: driftAfterBar, driftFactor: driftFactor)
            barIndex += 1
        }
        if section.name == name { return (start, t) }
    }
    return (0, 0)
}

func popSong(
    _ sections: [PopSection],
    bpm: Double = popBPM,
    leadingSilence: Double = 1.0,
    driftAfterBar: Int? = nil,
    driftFactor: Double = 1.0,
    sampleRate: Double = SR
) -> [Float] {
    var out = [Float](repeating: 0, count: Int(leadingSilence * sampleRate))
    var phase220 = 0.0, phase80 = 0.0, phase800 = 0.0
    let w220 = 2 * Double.pi * 220.0 / sampleRate
    let w80 = 2 * Double.pi * 80.0 / sampleRate
    let w800 = 2 * Double.pi * 800.0 / sampleRate
    let rampSamples = max(1, Int(0.008 * sampleRate))
    var clickSpots: [(index: Int, level: Float)] = []
    var barIndex = 0

    for section in sections {
        let mask = vocalMasks[min(section.vocalPattern, vocalMasks.count - 1)]
        for _ in 0..<section.bars {
            let barLen = popBarSeconds(barIndex, bpm: bpm, driftAfterBar: driftAfterBar, driftFactor: driftFactor)
            let barSamples = max(8, Int(barLen * sampleRate))
            let eighth = barSamples / 8
            let barStart = out.count

            for i in 0..<barSamples {
                let eighthIdx = min(7, i / eighth)
                let inEighth = i - eighthIdx * eighth
                var vocalEnv: Double = Double(mask[eighthIdx])
                if mask[eighthIdx] == 1 {
                    if inEighth < rampSamples {
                        vocalEnv = 0.5 - 0.5 * cos(.pi * Double(inEighth) / Double(rampSamples))
                    } else if inEighth > eighth - rampSamples {
                        vocalEnv = 0.5 - 0.5 * cos(.pi * Double(eighth - inEighth) / Double(rampSamples))
                    }
                }
                phase220 += w220
                phase80 += w80
                phase800 += w800
                let sample = 0.4 * Double(section.level) * sin(phase220)
                    + 0.3 * Double(section.bass) * sin(phase80)
                    + 0.25 * Double(section.vocal) * vocalEnv * sin(phase800)
                out.append(Float(sample))
            }

            for h in 0..<max(1, section.hitsPerBar) {
                clickSpots.append((barStart + h * barSamples / max(1, section.hitsPerBar), section.level))
            }
            barIndex += 1
        }
    }

    // Transient clicks (2 kHz shaped bursts) at the hit grid.
    let clickLen = Int(0.006 * sampleRate)
    for spot in clickSpots {
        for j in 0..<clickLen {
            let idx = spot.index + j
            guard idx < out.count else { continue }
            let x = Double(j) / Double(clickLen)
            let window = Float(0.5 * (1 - cos(2 * .pi * x)))
            out[idx] += 0.45 * spot.level * window * Float(sin(2 * .pi * 2000.0 * Double(j) / sampleRate))
        }
    }
    return out
}

func zonesOverlap(_ aStart: Double, _ aEnd: Double, _ bStart: Double, _ bEnd: Double) -> Bool {
    max(aStart, bStart) < min(aEnd, bEnd) - 0.01
}

// MARK: - 13. Structure map: classes, hooks, differentiation (measured)

var popPlanForAudit: AutoRemixPlan?
var popSongTrack: MixrTrack?
var popPCM: [Float] = []
do {
    let script = defaultPopScript()
    popPCM = popSong(script)
    let duration = Double(popPCM.count) / SR
    let song = makeSong(title: "Structured Pop", bpm: Int(popBPM), durationSeconds: duration)
    popSongTrack = song
    let features = SongSignalAnalyzer.extract(samples: popPCM, sampleRate: SR, bpmHint: popBPM)
    let analysis = SongAnalyzer.analyze(track: song, signal: features)
    let usable = max(0, features.leadingSilenceSeconds - 0.15)...duration
    let map = AutoRemixStructureMapBuilder.build(analysis: analysis, usableRange: usable)

    check("Structure: phrase grid covers the song", map.phrases.count >= 24,
          "got \(map.phrases.count) phrases")
    check("Structure: hook family found with ≥ 3 instances",
          map.hookInstances.count >= 3, "got \(map.hookInstances.count)")
    check("Structure: first hook instance protected",
          map.hookInstances.first?.isProtected == true)

    let chorus2 = popSectionRange(script, name: "chorus2")
    let chorus3 = popSectionRange(script, name: "chorus3")
    let nearDup = map.hookInstances.first {
        zonesOverlap($0.startSeconds, $0.endSeconds, chorus2.start, chorus2.end)
    }
    check("Structure: duplicate mid chorus classified nearDuplicate",
          nearDup?.differentiation == .nearDuplicate,
          nearDup.map { "\($0.differentiation)" } ?? "not found")
    let finalHook = map.hookInstances.first {
        zonesOverlap($0.startSeconds, $0.endSeconds, chorus3.start, chorus3.end)
    }
    check("Structure: intensified final chorus is NOT near-duplicate",
          finalHook.map { $0.differentiation == .intensified } ?? false,
          finalHook.map { "\($0.differentiation)" } ?? "not found")

    let verse2 = popSectionRange(script, name: "verse2")
    check("Structure: verses classified vocalDistinct (never removable)",
          map.phrase(at: verse2.start + 2)?.removability == .vocalDistinct,
          map.phrase(at: verse2.start + 2).map { "\($0.removability)" } ?? "no phrase")
    let post1 = popSectionRange(script, name: "post1")
    check("Structure: post-chorus classified instrumental",
          map.phrase(at: post1.start + 2)?.removability == .instrumental,
          map.phrase(at: post1.start + 2).map { "\($0.removability)" } ?? "no phrase")

    check("Structure: ≥ 3 regions for distribution", map.regions.count >= 3)
    check("Structure: grid windows measured across the song",
          map.gridWindows.count >= 4, "got \(map.gridWindows.count)")
    check("Structure: steady fixture shows low grid drift",
          map.gridDriftFractionOfBeat <= 0.1,
          String(format: "%.3f of a beat", map.gridDriftFractionOfBeat))
}

// MARK: - 14. Distributed recipe: multiple interventions, hard guarantees

do {
    guard let song = popSongTrack else { fatalError("pop fixture missing") }
    let script = defaultPopScript()
    let features = SongSignalAnalyzer.extract(samples: popPCM, sampleRate: SR, bpmHint: popBPM)
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 44, signals: [song.id: features]
    )
    switch outcome {
    case .success(_, let plan, _):
        popPlanForAudit = plan
        guard let recipe = plan.remixRecipe else {
            check("Recipe: plan carries a transformation recipe", false, "remixRecipe is nil")
            break
        }
        check("Recipe: plan carries a transformation recipe", true)
        check("Recipe: 3–5 transformation zones selected",
              (3...5).contains(recipe.selected.count), "got \(recipe.selected.count)")
        check("Recipe: ≥ 2 meaningful (non-SFX) transformations",
              recipe.meaningfulCount >= 2, "got \(recipe.meaningfulCount)")
        check("Recipe: 1–2 structural interventions used",
              (1...2).contains(recipe.structuralCount), "got \(recipe.structuralCount)")

        let regions = Set(recipe.selected.map(\.region))
        check("Recipe: zones span ≥ 3 structural regions",
              regions.count >= 3, "regions \(regions.sorted())")
        let anchors = recipe.selected.map(\.anchorDownbeat).sorted()
        check("Recipe: zones distributed (span ≥ 60 s)",
              (anchors.last ?? 0) - (anchors.first ?? 0) >= 60,
              String(format: "span %.1fs", (anchors.last ?? 0) - (anchors.first ?? 0)))

        // Protected first hook untouched by any transformation.
        let chorus1 = popSectionRange(script, name: "chorus1")
        // The first hook is never STRUCTURALLY removed/restructured;
        // DSP enhancement over it is allowed (preserves identity).
        let hookStructurallyTouched = recipe.selected.contains {
            $0.kind.isStructural && zonesOverlap($0.zoneStart, $0.zoneEnd, chorus1.start, chorus1.end)
        }
        check("Recipe: first full hook never structurally removed", !hookStructurallyTouched)

        // One continuous ≥ 32-bar passage untouched.
        let barSec = 240.0 / popBPM
        let usable = plan.usableSourceRange ?? 0...1
        var edges = [usable.lowerBound]
        for z in recipe.selected.sorted(by: { $0.zoneStart < $1.zoneStart }) {
            edges.append(z.zoneStart)
            edges.append(z.zoneEnd)
        }
        edges.append(usable.upperBound)
        var longestGap = 0.0
        var i = 0
        while i + 1 < edges.count {
            longestGap = max(longestGap, edges[i + 1] - edges[i])
            i += 2
        }
        check("Recipe: a continuous ≥ 32-bar passage survives",
              longestGap >= 32 * barSec,
              String(format: "longest %.1f bars", longestGap / barSec))

        // Every selection independently passes its floors.
        check("Recipe: every selection meets its confidence floor",
              recipe.selected.allSatisfy { $0.confidence >= 0.45 })
        check("Recipe: every selection meets its audibility floor",
              recipe.selected.allSatisfy {
                  $0.audibility.predictedDelta >= $0.audibility.minimumRequiredDelta
              })
        check("Recipe: every selection carries measured evidence",
              recipe.selected.allSatisfy { sel in sel.evidence.contains { $0.measured } })

        // SFX only reinforce selected zones.
        let selectedIDs = Set(recipe.selected.map(\.id))
        check("Recipe: every SFX event supports a selected zone",
              plan.sfxEvents.allSatisfy { event in
                  event.transformationID.map(selectedIDs.contains) ?? false
              })

        // Ledgers: prediction filled, export PENDING, no audition claims.
        check("Recipe: ledger export stage is pending, audition unclaimed",
              recipe.selected.allSatisfy { sel in
                  let ledger = recipe.ledgers[sel.id]
                  return ledger != nil && ledger!.exportDelta == nil && ledger!.auditioned == false
              })

        // Cut integrity + full rendered battery on the transformed plan.
        let cuts = AutoRemixDiagnostics.internalCutBoundaries(placements: plan.placements)
        check("Recipe: every internal cut carries a record",
              cuts.allSatisfy { cut in plan.cutRecords.contains { abs($0.timelineAt - cut) < 0.1 } },
              "\(cuts.count) cuts, \(plan.cutRecords.count) records")

        let sources = [song.id: AutoOfflineMixdown.Source(samples: popPCM, sampleRate: SR)]
        let result = AutoOfflineMixdown.render(plan: plan, sources: sources, sampleRate: SR)
        let mix = result.mix
        check("Recipe render: no clipped samples",
              AutoRemixDiagnostics.clippedSampleCount(mix) == 0)
        let truePeak = AutoRemixDiagnostics.truePeakDB(samples: mix, sampleRate: SR)
        check("Recipe render: true peak ≤ −1 dBTP",
              truePeak <= AutoGainPolicy.truePeakCeilingDB + 0.2,
              String(format: "%.2f dBTP", truePeak))
        check("Recipe render: limiter GR ≤ 3 dB",
              result.limiterGainReductionDB <= 3.0,
              String(format: "%.1f dB", result.limiterGainReductionDB))

        var worstTrough = 0.0
        var worstUnexplained = 0.0
        for cut in cuts {
            let b = AutoRemixDiagnostics.boundaryLoudness(samples: mix, sampleRate: SR, boundarySeconds: cut)
            worstTrough = max(worstTrough, b.centerTroughDB)
            let explained = plan.cutRecords.contains {
                abs($0.timelineAt - cut) < 0.1 && abs($0.expectedEnergyDeltaDB) + 2.0 >= b.jumpDB
            }
            if !explained { worstUnexplained = max(worstUnexplained, b.jumpDB) }
        }
        check("Recipe render: no cut trough > 3 dB",
              worstTrough <= 3.0, String(format: "worst %.1f dB", worstTrough))
        check("Recipe render: no unexplained cut jump > 4 dB",
              worstUnexplained <= 4.0, String(format: "worst %.1f dB", worstUnexplained))

        let contentStart = plan.placements.map(\.timelineStart).min() ?? 0
        let contentEnd = plan.placements.map(\.timelineEnd).max() ?? 0
        let silences = AutoRemixDiagnostics.silenceRuns(
            samples: mix, sampleRate: SR, thresholdDB: -45, minSeconds: 0.1
        ).filter { $0.start > contentStart + 0.5 && $0.end < contentEnd - 0.5 }
        check("Recipe render: no silence holes", silences.isEmpty,
              silences.prefix(3).map { String(format: "%.2f–%.2fs", $0.start, $0.end) }.joined(separator: ", "))
        let click = AutoRemixDiagnostics.maxAdjacentSampleJump(samples: result.songBus, sampleRate: SR)
        check("Recipe render: no clicks on the song bus",
              click.jump <= 0.5, String(format: "%.3f at %.2fs", click.jump, click.atSeconds))

        // Determinism of the transformation layer.
        let again = AutoRemixRunner.runEntireProject(
            tracks: [song], seed: 44, signals: [song.id: features]
        )
        if case .success(_, let planB, _) = again, let recipeB = planB.remixRecipe {
            let sameSelection = recipe.selected.count == recipeB.selected.count
                && zip(recipe.selected, recipeB.selected).allSatisfy {
                    $0.kind == $1.kind && abs($0.anchorDownbeat - $1.anchorDownbeat) < 0.001
                }
            check("Recipe: same seed → identical transformation selection", sameSelection)
        } else {
            check("Recipe: same seed → identical transformation selection", false, "second run failed")
        }
    case .failure(let message):
        check("Structured pop fixture plans", false, message)
    }
}

// MARK: - 15. Structural cut from repeat evidence, phrase-aligned

do {
    if let plan = popPlanForAudit, let recipe = plan.remixRecipe {
        let script = defaultPopScript()
        let structuralZones = recipe.selected.filter { $0.kind.isStructural }
        check("Repeat evidence: ≥ 1 structural intervention proposed",
              !structuralZones.isEmpty)

        // Structural removals must live in near-duplicate hook, repeated
        // instrumental, or outro material — never verses.
        let verse1 = popSectionRange(script, name: "verse1")
        let verse2 = popSectionRange(script, name: "verse2")
        let versesTouched = structuralZones.contains {
            zonesOverlap($0.zoneStart, $0.zoneEnd, verse1.start, verse1.end)
                || zonesOverlap($0.zoneStart, $0.zoneEnd, verse2.start, verse2.end)
        }
        check("Repeat evidence: no structural edit touches a verse", !versesTouched)

        // Phrase alignment: cut boundaries land within a beat of the
        // measured downbeat grid.
        let beat = 60.0 / popBPM
        let cuts = AutoRemixDiagnostics.internalCutBoundaries(placements: plan.placements)
        var aligned = true
        for cut in cuts {
            guard let record = plan.cutRecords.first(where: { abs($0.timelineAt - cut) < 0.1 })
            else { aligned = false; continue }
            let sourceJoin = record.sourceTo
            let usableStart = plan.usableSourceRange?.lowerBound ?? 0
            let phase = (sourceJoin - usableStart).truncatingRemainder(dividingBy: beat)
            if min(phase, beat - phase) > beat * 0.5 { aligned = false }
        }
        check("Repeat evidence: cut joins land on the beat grid", aligned)
    } else {
        check("Repeat evidence: ≥ 1 structural intervention proposed", false, "no recipe")
    }
}

// MARK: - 16. Vocal similarity is NOT redundancy

do {
    let script = vocalRepeatScript()
    let pcm = popSong(script)
    let duration = Double(pcm.count) / SR
    let song = makeSong(title: "Vocal Repeat Pop", bpm: Int(popBPM), durationSeconds: duration)
    let features = SongSignalAnalyzer.extract(samples: pcm, sampleRate: SR, bpmHint: popBPM)
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 45, signals: [song.id: features]
    )
    switch outcome {
    case .success(_, let plan, _):
        guard let recipe = plan.remixRecipe else {
            check("Vocal protection: recipe exists", false, "remixRecipe nil")
            break
        }
        check("Vocal protection: recipe exists", true)
        let verse1 = popSectionRange(script, name: "verse1")
        let verse2 = popSectionRange(script, name: "verse2")
        let structural = recipe.selected.filter { $0.kind.isStructural }
        let verseRemoved = structural.contains {
            zonesOverlap($0.zoneStart, $0.zoneEnd, verse1.start, verse1.end)
                || zonesOverlap($0.zoneStart, $0.zoneEnd, verse2.start, verse2.end)
        }
        check("Vocal protection: similar vocal verses are never removed", !verseRemoved)
        check("Vocal protection: rejection recorded for the vocal candidate",
              recipe.rejected.contains { $0.reason == .vocalProtection })
    case .failure(let message):
        check("Vocal repeat fixture plans", false, message)
    }
}

// MARK: - 17. Intensified final hook protected; audibility floors bind

do {
    if let plan = popPlanForAudit, let recipe = plan.remixRecipe {
        let script = defaultPopScript()
        let chorus3 = popSectionRange(script, name: "chorus3")
        let structural = recipe.selected.filter { $0.kind.isStructural }
        let finalHookRemoved = structural.contains {
            zonesOverlap($0.zoneStart, $0.zoneEnd, chorus3.start, chorus3.end)
        }
        check("Hook differentiation: intensified final chorus never removed",
              !finalHookRemoved)
    } else {
        check("Hook differentiation: intensified final chorus never removed", false, "no recipe")
    }

    // Portable A/B: every selected DSP transformation must measurably
    // change its contracted feature.
    if let plan = popPlanForAudit, let recipe = plan.remixRecipe, let song = popSongTrack {
        let sources = [song.id: AutoOfflineMixdown.Source(samples: popPCM, sampleRate: SR)]
        let dsp = recipe.selected.filter {
            !$0.kind.isStructural && $0.kind != .sfxAccent
        }
        check("Audibility: ≥ 2 DSP transformations to verify", dsp.count >= 2,
              "got \(dsp.count)")
        var allAudible = true
        var detail = ""
        for transformation in dsp {
            // A selected DSP transformation with a renderable feature MUST
            // produce a measurable delta — a nil here means it emitted no
            // audible placement (a silent no-op), which is a failure, not
            // a skip.
            let renderable = transformation.audibility.measuredFeature != .durationChange
                && transformation.audibility.measuredFeature != .rhythmDensity
            let delta = AutoRemixDiagnostics.portableAudibilityDelta(
                plan: plan, transformation: transformation, sources: sources, sampleRate: SR
            )
            if renderable, delta == nil {
                allAudible = false
                detail += "\(transformation.kind.rawValue) produced no audible placement; "
                continue
            }
            if let delta, delta < transformation.audibility.minimumRequiredDelta {
                allAudible = false
                detail += String(format: "%@ %.1f<%.1f ", transformation.kind.rawValue,
                                 delta, transformation.audibility.minimumRequiredDelta)
            }
        }
        check("Audibility: portable render confirms every DSP transformation",
              allAudible, detail)
    }
}

// MARK: - 18. Weak opportunities rejected; targets are not quotas

do {
    let script = sparsePopScript()
    let pcm = popSong(script)
    let duration = Double(pcm.count) / SR
    let song = makeSong(title: "Sparse Pop", bpm: Int(popBPM), durationSeconds: duration)
    let features = SongSignalAnalyzer.extract(samples: pcm, sampleRate: SR, bpmHint: popBPM)
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 46, signals: [song.id: features]
    )
    switch outcome {
    case .success(_, let plan, _):
        guard let recipe = plan.remixRecipe else {
            check("Sparse: recipe exists", false, "remixRecipe nil")
            break
        }
        check("Sparse: some valid transformation still selected",
              !recipe.selected.isEmpty)
        check("Sparse: no selection below its floors",
              recipe.selected.allSatisfy {
                  $0.confidence >= 0.45
                      && $0.audibility.predictedDelta >= $0.audibility.minimumRequiredDelta
              })
        check("Sparse: unmet targets reported instead of padded",
              recipe.selected.count >= 3 || !recipe.unmetTargets.isEmpty,
              "selected \(recipe.selected.count), unmet \(recipe.unmetTargets)")
        check("Sparse: weak candidates visible as audibility/confidence rejections",
              recipe.selected.count >= 3 || recipe.rejected.contains {
                  $0.reason == .belowAudibilityFloor || $0.reason == .belowConfidence
              })
    case .failure(let message):
        check("Sparse pop fixture plans", false, message)
    }
}

// MARK: - 19. Grid drift blocks late structural edits

do {
    let (script, driftBar) = driftPopScript()
    let pcm = popSong(script, driftAfterBar: driftBar, driftFactor: 1.02)
    let duration = Double(pcm.count) / SR
    let song = makeSong(title: "Drifting Pop", bpm: Int(popBPM), durationSeconds: duration)
    let features = SongSignalAnalyzer.extract(samples: pcm, sampleRate: SR, bpmHint: popBPM)

    check("Drift: windowed beat phases measured", features.beatPhaseWindows.count >= 4,
          "got \(features.beatPhaseWindows.count)")
    check("Drift: phase deviation detected", features.gridDriftFractionOfBeat > 0.1,
          String(format: "%.3f of a beat", features.gridDriftFractionOfBeat))

    let driftOnset = popSectionRange(
        script, name: "bridge", driftAfterBar: driftBar, driftFactor: 1.02
    ).start
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 47, signals: [song.id: features]
    )
    switch outcome {
    case .success(_, let plan, _):
        guard let recipe = plan.remixRecipe else {
            check("Drift: recipe exists", false, "remixRecipe nil")
            break
        }
        let lateStructural = recipe.selected.filter {
            $0.kind.isStructural && $0.anchorDownbeat >= driftOnset - 1
        }
        check("Drift: no structural edit in the drifting region",
              lateStructural.isEmpty,
              lateStructural.map { "\($0.kind.rawValue)@\(Int($0.anchorDownbeat))s" }.joined(separator: ", "))
        check("Drift: unstable candidates downgraded or rejected visibly",
              recipe.rejected.contains { $0.reason == .gridUnstable }
                  || recipe.selected.contains { !$0.kind.isStructural && $0.anchorDownbeat >= driftOnset - 1 })
    case .failure(let message):
        check("Drifting pop fixture plans", false, message)
    }
}

// MARK: - 20. Structural budget counts rewinds and loops (unit)

do {
    func structuralOpportunity(
        _ kind: AutoTransformationKind,
        anchor: Double,
        region: Int,
        score: Double
    ) -> AutoRemixOpportunity {
        AutoRemixOpportunity(
            kind: kind,
            zoneStart: anchor,
            zoneEnd: anchor + 14.5,
            anchorDownbeat: anchor,
            region: region,
            score: score,
            confidence: 0.9,
            vocalSafe: true,
            evidence: [AutoRemixEvidence(name: "repeatSimilarity", value: 0.95, measured: true)],
            audibility: AudibilityContract(
                musicalJustification: "unit fixture",
                expectedConsequence: "bars removed",
                measuredFeature: .durationChange,
                predictedDelta: 8,
                minimumRequiredDelta: 4
            )
        )
    }
    func dspOpportunity(_ kind: AutoTransformationKind, anchor: Double, region: Int) -> AutoRemixOpportunity {
        AutoRemixOpportunity(
            kind: kind,
            zoneStart: anchor,
            zoneEnd: anchor + 7.2,
            anchorDownbeat: anchor + 7.2,
            region: region,
            score: 0.7,
            confidence: 0.8,
            vocalSafe: true,
            evidence: [AutoRemixEvidence(name: "energyRise", value: 0.4, measured: true)],
            audibility: AudibilityContract(
                musicalJustification: "unit fixture",
                expectedConsequence: "HF sweep",
                measuredFeature: .hfEnergy,
                predictedDelta: 8,
                minimumRequiredDelta: 3
            )
        )
    }

    var map = AutoRemixStructureMap.empty
    map.usableRange = 0...220
    map.regions = [0...73, 73.001...146, 146.001...220]
    map.gridDriftFractionOfBeat = 0.02
    map.beatSecondsHint = 60 / popBPM
    map.gridWindows = [
        AutoRemixGridWindow(centerSeconds: 30, phase: 0.1, confidence: 0.9),
        AutoRemixGridWindow(centerSeconds: 110, phase: 0.1, confidence: 0.9),
        AutoRemixGridWindow(centerSeconds: 190, phase: 0.1, confidence: 0.9),
    ]

    let opportunities = [
        structuralOpportunity(.shortenRepeat, anchor: 40, region: 0, score: 0.9),
        structuralOpportunity(.hookReturn, anchor: 120, region: 1, score: 0.85),
        structuralOpportunity(.loopStutter, anchor: 190, region: 2, score: 0.8),
        dspOpportunity(.filteredBuild, anchor: 70, region: 0),
        dspOpportunity(.echoThrow, anchor: 150, region: 2),
    ]
    let recipe = AutoRemixRecipePlanner.recipe(
        from: opportunities, structure: map, seed: 5
    )
    check("Budget: at most two structural interventions selected",
          recipe.structuralCount == 2, "got \(recipe.structuralCount)")
    check("Budget: rewinds and loops count against the budget",
          recipe.selected.filter { $0.kind == .hookReturn || $0.kind == .loopStutter }.count
              + recipe.selected.filter { $0.kind == .shortenRepeat }.count
              == recipe.structuralCount)
    check("Budget: overflow rejected with budgetExhausted",
          recipe.rejected.contains { $0.reason == .budgetExhausted })
    check("Budget: DSP zones still selected alongside",
          recipe.selected.contains { !$0.kind.isStructural })
}

// MARK: - 21. Low-confidence path unchanged by the transformation layer

do {
    guard let song = popSongTrack else { fatalError("pop fixture missing") }
    let outcome = AutoRemixRunner.runEntireProject(tracks: [song], seed: 48)
    switch outcome {
    case .success(_, let plan, _):
        check("Layer: no signal → still one continuous placement",
              plan.placements.filter { $0.role == .dominant }.count == 1,
              "got \(plan.placements.count)")
        check("Layer: no signal → no transformations invented",
              (plan.remixRecipe?.selected.isEmpty ?? true))
    case .failure(let message):
        check("Low-confidence pop plans", false, message)
    }
}

// MARK: - 22. Duo mashup: preservation-first, compatibility-driven
//
// The tempo-INCOMPATIBLE design pair (Cut-to-the-Feeling ~115 BPM ×
// good-4-u ~85 BPM). The join must be a filled tempo bridge, the
// incoming song at native tempo (never on the anchor's bar grid), one
// handoff, identities preserved, no pre-drop silence, and the render
// must pass every audio gate.

func makeMashupSong(
    title: String, bpm: Int, key: String, durationSeconds: Double
) -> MixrTrack {
    MixrTrack(
        id: UUID(), title: title, artist: "Fixture", duration: "--:--",
        durationSeconds: durationSeconds, bpm: bpm, bpmConfidence: nil,
        key: key, keyConfidence: nil, color: .pink, volume: 1.0, isMuted: false,
        url: nil, artworkData: nil,
        clips: [MixrClip(id: UUID(), start: 0, length: MixrTimeline.units(fromSeconds: min(durationSeconds, 180)))]
    )
}

do {
    // Compatibility decision on the real tempo pair (metadata BPM).
    let cut = makeMashupSong(title: "Cut To The Feeling", bpm: 115, key: "A", durationSeconds: 150)
    let g4u = makeMashupSong(title: "good 4 u", bpm: 85, key: "F#m", durationSeconds: 150)
    let cutProfile = AutoSectionCatalog.profile(track: cut)
    let g4uProfile = AutoSectionCatalog.profile(track: g4u)
    let decision = AutoMashupCompatibility.decide(anchor: cutProfile, incoming: g4uProfile, tuning: .standard)
    check("Mashup: tempo-incompatible pair chooses a filled tempo bridge",
          decision.strategy == .tempoBridge, "\(decision.strategy)")
    check("Mashup: incompatible incoming song kept at native tempo",
          abs(decision.incomingTempoRatio - 1.0) < 0.001,
          String(format: "ratio %.3f", decision.incomingTempoRatio))
    check("Mashup: relative major/minor scored harmonically compatible",
          decision.harmonicScore >= 0.85, String(format: "%.2f", decision.harmonicScore))

    let outcome = AutoRemixRunner.runEntireProject(tracks: [cut, g4u], seed: 20)
    switch outcome {
    case .success(let tracks, let plan, _):
        check("Mashup: preservation-first duo (≤ 2 handoffs)",
              plan.handoffCount <= 2, "got \(plan.handoffCount)")
        check("Mashup: no automatic pre-drop silence", plan.intentionalGaps.isEmpty)

        // Incoming song placed at native tempo (ratio 1.0), never on the
        // anchor's bar grid.
        let bPlacements = plan.placements.filter { $0.songID == g4u.id }
        check("Mashup: incoming placements at native tempo",
              bPlacements.allSatisfy { abs($0.tempoRatio - 1.0) < 0.001 },
              "ratios \(bPlacements.map { String(format: "%.2f", $0.tempoRatio) })")

        // Each song's run is internally contiguous — no unmasked internal
        // cut within a song.
        let cutsA = AutoRemixDiagnostics.internalCutBoundaries(
            placements: plan.placements.filter { $0.songID == cut.id })
        let cutsB = AutoRemixDiagnostics.internalCutBoundaries(placements: bPlacements)
        check("Mashup: no unmasked internal cut inside either song",
              cutsA.isEmpty && cutsB.isEmpty, "A \(cutsA.count), B \(cutsB.count)")

        // Identity runway: song A starts at its beginning, not a teaser
        // jump; song B starts near its beginning too.
        let aFirst = plan.placements.filter { $0.songID == cut.id }
            .min { $0.timelineStart < $1.timelineStart }
        check("Mashup: anchor preserves its opening (starts near source 0)",
              (aFirst?.sourceStart ?? 99) < 8, String(format: "src %.1fs", aFirst?.sourceStart ?? -1))
        let bFirst = bPlacements.min { $0.timelineStart < $1.timelineStart }
        check("Mashup: incoming preserves its opening identity",
              (bFirst?.sourceStart ?? 99) < 40, String(format: "src %.1fs", bFirst?.sourceStart ?? -1))

        // SFX present but bounded, and a riser lands the bridge.
        check("Mashup: coordinated SFX present", !plan.sfxEvents.isEmpty)
        let minutes = max(plan.targetDuration / 60, 0.01)
        check("Mashup: SFX density bounded (≤ 8/min)",
              Double(plan.sfxEvents.count) / minutes <= 8.0,
              String(format: "%.1f/min", Double(plan.sfxEvents.count) / minutes))
        check("Mashup: a riser carries the tempo bridge",
              plan.sfxEvents.contains { $0.assetID == "riser" })

        // ── Rendered PCM gates on the two-song mix ──
        let sources = [
            cut.id: AutoOfflineMixdown.Source(samples: syntheticSong(durationSeconds: 150, bpm: 115, flatAmplitude: 0.5), sampleRate: SR),
            g4u.id: AutoOfflineMixdown.Source(samples: syntheticSong(durationSeconds: 150, bpm: 85, flatAmplitude: 0.5), sampleRate: SR),
        ]
        let result = AutoOfflineMixdown.render(plan: plan, sources: sources, sampleRate: SR)
        let mix = result.mix
        check("Mashup render: no clipped samples",
              AutoRemixDiagnostics.clippedSampleCount(mix) == 0)
        let truePeak = AutoRemixDiagnostics.truePeakDB(samples: mix, sampleRate: SR)
        check("Mashup render: true peak ≤ −1 dBTP",
              truePeak <= AutoGainPolicy.truePeakCeilingDB + 0.2, String(format: "%.2f dBTP", truePeak))
        check("Mashup render: limiter GR ≤ 3 dB (headroom preserved)",
              result.limiterGainReductionDB <= 3.0, String(format: "%.1f dB", result.limiterGainReductionDB))

        let contentStart = plan.placements.map(\.timelineStart).min() ?? 0
        let contentEnd = plan.placements.map(\.timelineEnd).max() ?? 0
        let silences = AutoRemixDiagnostics.silenceRuns(
            samples: mix, sampleRate: SR, thresholdDB: -45, minSeconds: 0.1
        ).filter { $0.start > contentStart + 0.5 && $0.end < contentEnd - 0.5 }
        check("Mashup render: no silence holes (bridge is filled)", silences.isEmpty,
              silences.prefix(3).map { String(format: "%.1f–%.1fs", $0.start, $0.end) }.joined(separator: ", "))

        // The A→B handoff boundary must not dip toward silence.
        let handoffT = bFirst?.timelineStart ?? 0
        let hb = AutoRemixDiagnostics.boundaryLoudness(samples: mix, sampleRate: SR, boundarySeconds: handoffT)
        check("Mashup render: handoff holds level (trough ≤ 3 dB)",
              hb.centerTroughDB <= 3.0, String(format: "trough %.1f dB", hb.centerTroughDB))

        let click = AutoRemixDiagnostics.maxAdjacentSampleJump(samples: result.songBus, sampleRate: SR)
        check("Mashup render: no click at the join (song bus)",
              click.jump <= 0.5, String(format: "%.3f at %.1fs", click.jump, click.atSeconds))

        _ = tracks
    case .failure(let message):
        check("Tempo-incompatible duo mashup plans", false, message)
    }
}

// MARK: - 23. Duo mashup: tempo-COMPATIBLE pair uses a true overlap

do {
    let a = makeMashupSong(title: "Anchor Compat", bpm: 124, key: "Am", durationSeconds: 150)
    let b = makeMashupSong(title: "Feature Compat", bpm: 126, key: "C", durationSeconds: 150)
    let aP = AutoSectionCatalog.profile(track: a)
    let bP = AutoSectionCatalog.profile(track: b)
    let decision = AutoMashupCompatibility.decide(anchor: aP, incoming: bP, tuning: .standard)
    check("Mashup: beatmatchable pair chooses a true crossfade",
          decision.strategy == .tempoCrossfade, "\(decision.strategy)")

    let outcome = AutoRemixRunner.runEntireProject(tracks: [a, b], seed: 21)
    if case .success(_, let plan, _) = outcome {
        // A real overlap: the incoming song's first placement starts
        // BEFORE the anchor's last placement ends (both play together).
        let aLast = plan.placements.filter { $0.songID == a.id }.max { $0.timelineEnd < $1.timelineEnd }
        let bFirst = plan.placements.filter { $0.songID == b.id }.min { $0.timelineStart < $1.timelineStart }
        let overlap = (aLast?.timelineEnd ?? 0) - (bFirst?.timelineStart ?? 0)
        check("Mashup: compatible join has real temporal overlap",
              overlap > 0.5, String(format: "%.2fs overlap", overlap))
        check("Mashup: incoming beatmatched to the grid (ratio ≠ 1)",
              plan.placements.filter { $0.songID == b.id }.allSatisfy { abs($0.tempoRatio - 1.0) > 0.001 }
                  || abs(decision.incomingTempoRatio - 1.0) < 0.001)
    } else {
        check("Compatible duo mashup plans", false)
    }
}

// MARK: - 25. Real-audio confidence levels still produce transformations
//
// Regression for the calibration bug that made real songs (Levitating,
// Heat Waves) return untouched: (a) opportunity confidence must not be
// the compounding product overallConfidence×beatConfidence (two ~0.6
// signals → 0.36, below every floor), and (b) a confident but gentle
// song with smooth dynamics must still get a DSP floor.

do {
    // Structured song, but confidences forced to REAL-AUDIO levels where
    // the old overall×beat product (0.72×0.50 = 0.36) fell below floors.
    let base = SongSignalAnalyzer.extract(samples: popPCM, sampleRate: SR, bpmHint: popBPM)
    var real = base
    real.overallConfidence = 0.72
    real.beatConfidence = 0.50            // both individually clear the tier gate
    let song = makeSong(title: "Real-Confidence Pop", bpm: Int(popBPM),
                        durationSeconds: Double(popPCM.count) / SR)
    let outcome = AutoRemixRunner.runEntireProject(tracks: [song], seed: 70, signals: [song.id: real])
    if case .success(_, let plan, _) = outcome, let recipe = plan.remixRecipe {
        check("Real-conf: full tier still selects transformations (no compounding to zero)",
              recipe.selected.count >= 2, "got \(recipe.selected.count) selected")
        check("Real-conf: at least one audible effect placement",
              plan.placements.contains { $0.effects.hasAnyActiveEffect })
        check("Real-conf: coordinated SFX present", !plan.sfxEvents.isEmpty)
    } else {
        check("Real-conf: full tier still selects transformations (no compounding to zero)",
              false, "no recipe")
    }
}

do {
    // Confident but GENTLE: high confidence, nearly flat energy (few
    // rises). Must still get the safe-DSP floor, not an untouched song.
    let duration = 150.0
    let hop = SongSignalAnalyzer.hopSeconds
    let hops = Int(duration / hop)
    var energy = [Double](repeating: 0.55, count: hops)
    // one gentle swell only — below the old absolute rise threshold
    for i in 0..<hops where Double(i) * hop >= 80 && Double(i) * hop < 110 { energy[i] = 0.62 }
    let gentle = SongSignalFeatures(
        sampleRate: SR, durationSeconds: duration,
        rmsCurveDB: [Double](repeating: -14, count: hops),
        onsetStrength: [Double](repeating: 0.4, count: hops), hopSeconds: hop,
        downbeatOffsetSeconds: 0.5, beatConfidence: 0.9,
        leadingSilenceSeconds: 0, trailingSilenceSeconds: 0, quietRegions: [],
        energyCurve: energy, bassEnergyCurve: [Double](repeating: 0.5, count: hops),
        vocalPresenceCurve: [Double](repeating: 0.4, count: hops),
        noveltyCurve: [Double](repeating: 0.1, count: hops),
        drumConfidence: 0.8, overallConfidence: 0.95,
        beatPhaseWindows: [], gridDriftFractionOfBeat: 0.05)
    let song = makeSong(title: "Gentle Song", bpm: 120, key: "C", durationSeconds: duration)
    let outcome = AutoRemixRunner.runEntireProject(tracks: [song], seed: 71, signals: [song.id: gentle])
    if case .success(_, let plan, _) = outcome {
        check("Gentle-but-confident: still gets a DSP floor (not untouched)",
              plan.placements.contains { $0.effects.hasAnyActiveEffect },
              "\(plan.placements.filter { $0.effects.hasAnyActiveEffect }.count) effected")
        check("Gentle-but-confident: no clipping in render", {
            let src = AutoOfflineMixdown.Source(samples: syntheticSong(durationSeconds: duration, flatAmplitude: 0.5), sampleRate: SR)
            return AutoRemixDiagnostics.clippedSampleCount(
                AutoOfflineMixdown.render(plan: plan, sources: [song.id: src], sampleRate: SR).mix) == 0
        }())
    } else {
        check("Gentle-but-confident: plans", false)
    }
}

// MARK: - 24. Moderate confidence → safe DSP edits, never a cut
//
// The fix for "Auto did nothing on a real song": when the signal is
// trustworthy but beat/structure confidence is below the structural bar,
// the planner still applies source-continuous effect treatments (no
// cuts) so the result has audible movement — instead of collapsing to a
// single untouched placement.

do {
    let duration = 150.0
    let hop = SongSignalAnalyzer.hopSeconds
    let hops = Int(duration / hop)
    // Energy curve with two clear rises; beat confidence deliberately LOW.
    var energy = [Double](repeating: 0.5, count: hops)
    for i in 0..<hops {
        let t = Double(i) * hop
        if t >= 40 && t < 70 { energy[i] = 0.85 }   // rise at ~40s
        if t >= 100 && t < 130 { energy[i] = 0.9 }  // rise at ~100s
    }
    let moderateFeatures = SongSignalFeatures(
        sampleRate: SR, durationSeconds: duration,
        rmsCurveDB: [Double](repeating: -12, count: hops),
        onsetStrength: [Double](repeating: 0.3, count: hops), hopSeconds: hop,
        downbeatOffsetSeconds: nil,
        beatConfidence: 0.25,             // < 0.4 → structural edits withheld
        leadingSilenceSeconds: 0, trailingSilenceSeconds: 0, quietRegions: [],
        energyCurve: energy,
        bassEnergyCurve: [Double](repeating: 0.6, count: hops),
        vocalPresenceCurve: [Double](repeating: 0.5, count: hops),
        noveltyCurve: [Double](repeating: 0.2, count: hops),
        drumConfidence: 0.3,
        overallConfidence: 0.5,           // ≥ 0.35 → safe-effects tier
        beatPhaseWindows: [], gridDriftFractionOfBeat: 1.0
    )
    let song = makeSong(title: "Moderate Song", bpm: 120, key: "C", durationSeconds: duration)
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 60, signals: [song.id: moderateFeatures]
    )
    switch outcome {
    case .success(_, let plan, _):
        // The key fix: NOT empty. It makes audible effect edits.
        let dspPlacements = plan.placements.filter { $0.effects.hasAnyActiveEffect }
        check("Moderate: produces audible effect treatments (not nothing)",
              !dspPlacements.isEmpty, "\(dspPlacements.count) effected placements")
        check("Moderate: at least one coordinated SFX",
              !plan.sfxEvents.isEmpty, "\(plan.sfxEvents.count) SFX")

        // But NEVER a cut — structural edits are withheld at this tier.
        let cuts = AutoRemixDiagnostics.internalCutBoundaries(placements: plan.placements)
        check("Moderate: zero internal cuts (structural withheld)", cuts.isEmpty,
              "got \(cuts.count)")
        check("Moderate: source order stays monotonic",
              AutoRemixDiagnostics.sourceOrderIsMonotonic(placements: plan.placements))
        check("Moderate: reports why structural edits were withheld",
              plan.warnings.contains { $0.contains("safe-effects") }
                  || (plan.remixRecipe?.unmetTargets.contains { $0.contains("structural edits withheld") } ?? false))

        // Render must still pass the audio gates.
        let source = AutoOfflineMixdown.Source(
            samples: syntheticSong(durationSeconds: duration, flatAmplitude: 0.5), sampleRate: SR)
        let result = AutoOfflineMixdown.render(plan: plan, sources: [song.id: source], sampleRate: SR)
        check("Moderate render: no clipping", AutoRemixDiagnostics.clippedSampleCount(result.mix) == 0)
        check("Moderate render: true peak ≤ −1 dBTP",
              AutoRemixDiagnostics.truePeakDB(samples: result.mix, sampleRate: SR) <= AutoGainPolicy.truePeakCeilingDB + 0.2)
        let cStart = plan.placements.map(\.timelineStart).min() ?? 0
        let cEnd = plan.placements.map(\.timelineEnd).max() ?? 0
        let sil = AutoRemixDiagnostics.silenceRuns(samples: result.mix, sampleRate: SR, thresholdDB: -45, minSeconds: 0.1)
            .filter { $0.start > cStart + 0.5 && $0.end < cEnd - 0.5 }
        check("Moderate render: no silence holes", sil.isEmpty)
    case .failure(let message):
        check("Moderate-confidence one-song plans", false, message)
    }
}

// MARK: - Diagnostics evidence (printed, not asserted)

if let plan = confidentPlan, let song = confidentSong {
    let source = AutoOfflineMixdown.Source(
        samples: syntheticSong(durationSeconds: song.durationSeconds ?? 160),
        sampleRate: SR
    )
    let result = AutoOfflineMixdown.render(plan: plan, sources: [song.id: source], sampleRate: SR)
    let report = AutoRemixDiagnostics.qualityReport(
        plan: plan,
        pcm: result.mix,
        sampleRate: SR,
        limiterGainReductionDB: result.limiterGainReductionDB
    )
    print("\n" + report.text)
}

// Remix report (items 1 & 2) is non-empty and audit-complete on the
// structured-pop fixture. Portable-render audibility (stage 2) filled;
// export + audition stay PENDING.
if let plan0 = popPlanForAudit {
    let sources = [popSongTrack!.id: AutoOfflineMixdown.Source(samples: popPCM, sampleRate: SR)]
    let plan = AutoRemixDiagnostics.fillingPortableAudibility(plan: plan0, sources: sources, sampleRate: SR)
    let report = AutoRemixDiagnostics.remixReport(plan: plan, bpm: popBPM)
    check("Remix report: lists selections", report.contains("Selected ("))
    check("Remix report: lists rejections", report.contains("Rejected ("))
    check("Remix report: shows removability classes",
          report.contains("vocalDistinct") && report.contains("hookFamily"))
    check("Remix report: shows hook differentiation", report.contains("Hook family ("))
    check("Remix report: shows budget usage", report.contains("Budget:"))
    check("Remix report: marks export/audition PENDING",
          report.contains("export PENDING") && report.contains("audition PENDING"))
    print("\n" + report)
}

print("\n\(failures == 0 ? "ALL PASSED" : "FAILED: \(failures)")")
exit(failures == 0 ? 0 : 1)

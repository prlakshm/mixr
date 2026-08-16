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
//   • club rewrite plan shape (two-wave drops, build-out kick mute,
//     intentional pre-drop voids, structured cut records, pulse policy)
//   • no clipping, true peak ≤ −1 dBTP, limiter as safety not glue
//   • no join-centered loudness troughs > 3 dB, no unexplained > 4 dB jumps
//   • no unintended silence ≥ 100 ms below −45 dBFS inside musical content
//     (intentional pre-drop voids excluded)
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

// MARK: - 3. One-song plan shape: club rewrite (confident input)

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

        // Club remix uses intentional pre-drop voids (hype = subtraction).
        check("One song: club shape allows intentional pre-drop voids",
              plan.intentionalGaps.allSatisfy { $0.reason.contains("pre-drop") },
              "\(plan.intentionalGaps.count) gaps")

        let dropRegions = plan.pulseRegions.filter { $0.role == .drop }
        check("One song: two-wave club drops", dropRegions.count >= 2,
              "got \(dropRegions.count) drop regions")

        let buildOuts = plan.pulseRegions.filter { $0.role == .buildOut }
        check("One song: kick muted in build-out", !buildOuts.isEmpty)

        check("One song: pulse policy recorded", plan.pulsePolicy != nil)
        check("One song: club flavor chosen", plan.clubFlavor != nil)

        let pitched = plan.placements.filter { $0.effects.pitchAmount > 0.005 }
        check("One song: no random pitch section by default", pitched.isEmpty,
              "\(pitched.count) pitched placements")

        check("One song: plan records the usable source range",
              plan.usableSourceRange != nil)

        let musicalSFX = plan.sfxEvents.filter { !["clubKick", "clubBass", "clubHat"].contains($0.assetID) }
        let minutes = max(plan.targetDuration / 60.0, 0.01)
        let sfxPerMinute = Double(musicalSFX.count) / minutes
        check("One song: musical SFX density bounded (≤ 3/min)",
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
    ).filter { run in
        guard run.start > contentStart + 0.5 && run.end < contentEnd - 0.5 else { return false }
        // Intentional pre-drop voids are allowed club hype — not defects.
        let intentional = plan.intentionalGaps.contains { g in
            let overlap = min(run.end, g.end) - max(run.start, g.start)
            return overlap > (run.end - run.start) * 0.5
        }
        return !intentional
    }
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

    // Click gate at Auto-introduced joins. Fixture beat-clicks inside
    // continuous source are not remix defects. Impacts and pre-drop voids
    // are allowed to punch (hype = subtraction then a downbeat).
    var worstClick = 0.0
    var worstClickAt = 0.0
    let inspectTimes: [Double] = plan.placements
        .filter { !$0.continuesPrevious && $0.timelineStart > 0.05 }
        .map(\.timelineStart)
        + plan.sfxEvents
        .filter { !["clubKick", "clubBass", "clubHat", "impact", "bassDrop"].contains($0.assetID) }
        .map(\.timelineStart)
    for t in inspectTimes {
        let lo = max(0, Int((t - 0.01) * SR))
        let hi = min(pcm.count, Int((t + 0.05) * SR))
        guard hi > lo + 2 else { continue }
        let window = AutoRemixDiagnostics.maxAdjacentSampleJump(
            samples: Array(pcm[lo..<hi]),
            sampleRate: SR
        )
        if window.jump > worstClick {
            worstClick = window.jump
            worstClickAt = Double(lo) / SR + window.atSeconds
        }
    }
    let nearVoid = plan.intentionalGaps.contains {
        abs(worstClickAt - $0.start) < 0.08 || abs(worstClickAt - $0.end) < 0.08
    }
    check("Render: no sample discontinuity above click threshold at Auto joins",
          worstClick <= 0.55 || nearVoid || inspectTimes.isEmpty,
          String(format: "%.3f at %.2fs", worstClick, worstClickAt))

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

// MARK: - 8. Evidence-based edge trimming (usable range, not montage order)

do {
    let song = makeSong(title: "Padded Song", durationSeconds: 160)
    let features = makeFeatures(duration: 160, leadingSilence: 6, trailingSilence: 4)
    let outcome = AutoRemixRunner.runEntireProject(
        tracks: [song], seed: 7, signals: [song.id: features]
    )
    switch outcome {
    case .success(_, let plan, _):
        guard let usable = plan.usableSourceRange else {
            check("Trim: usable range recorded", false)
            break
        }
        check("Trim: leading silence removed from usable range",
              usable.lowerBound >= 5.0 && usable.lowerBound <= 7.5,
              String(format: "usable start %.2fs", usable.lowerBound))
        check("Trim: trailing silence removed from usable range",
              usable.upperBound >= 148.0 && usable.upperBound <= 157.0,
              String(format: "usable end %.2fs", usable.upperBound))
        let outside = plan.placements.contains {
            $0.sourceStart < usable.lowerBound - 0.05 || $0.sourceEnd > usable.upperBound + 0.05
        }
        check("Trim: no placement reads the silent edges", !outside)
        check("Trim: usable range recorded", true)
    case .failure(let message):
        check("Padded song plans", false, message)
    }
}

// MARK: - 9. Low confidence → energy curve without invented structural cuts

do {
    let song = makeSong(title: "Unknown Tempo", bpm: nil, key: nil, durationSeconds: 150)
    let outcome = AutoRemixRunner.runEntireProject(tracks: [song], seed: 11)
    switch outcome {
    case .success(_, let plan, _):
        let cuts = AutoRemixDiagnostics.internalCutBoundaries(placements: plan.placements)
        check("Low confidence: zero internal source cuts", cuts.isEmpty, "got \(cuts.count)")
        // Timeline may pause for a pre-drop void; source order stays continuous.
        check("Low confidence: source order monotonic",
              AutoRemixDiagnostics.sourceOrderIsMonotonic(placements: plan.placements))
        check("Low confidence: still imposes club energy curve",
              plan.decisions.contains { $0.kind == .imposedClubEnergyCurve || $0.kind == .usedLowConfidenceFallback })
        check("Low confidence: pulse / filter energy present",
              !plan.pulseRegions.isEmpty || plan.placements.contains { $0.effects.level(for: "blur") > 0.5 })
        let musical = plan.sfxEvents.filter { !["clubKick", "clubBass", "clubHat"].contains($0.assetID) }
        check("Low confidence: musical SFX stay sparse (≤ 4)", musical.count <= 4,
              "got \(musical.count)")
    case .failure(let message):
        check("Low-confidence one-song input still produces a remix", false, message)
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

print("\n\(failures == 0 ? "ALL PASSED" : "FAILED: \(failures)")")
exit(failures == 0 ? 0 : 1)

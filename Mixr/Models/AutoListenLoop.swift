import Foundation

// MARK: - Auto Listen Loop
//
// The engine LISTENS to its own mix before handing it over.
//
// Every defect the owner caught by ear this cycle — the −4 st transpose, the
// dead-air holes, the loudness lurches, the 11 dB pre-drop dip — was invisible
// to the planner, because the planner writes intentions and never renders
// them. The fixes that stuck all worked the same way: render, measure against
// an invariant, repair. This module makes that loop part of the ALGORITHM:
//
//   plan → offline render → measure → (repair + re-render once) → residuals
//
// Measurements mirror the offline Python gates (analyze_smoothness /
// gate_drops / gate_loudness) in pure Swift over rendered PCM, so they run
// wherever the engine runs. Repairs re-invoke the validator's existing
// measured repairs; anything still failing after one repair round is reported
// as warnings — never silently shipped.
nonisolated enum AutoListenLoop {

    struct Violation: Sendable, Equatable {
        enum Kind: String, Sendable {
            case hole            // body dead air
            case loudnessStep    // adjacent-window programme lurch
            case dropDip         // approach falls into the drop
            case titleOverDrop   // title probe out-levels drop 1 (mastered)
        }
        var kind: Kind
        var t: Double
        var detail: String
        var durSeconds: Double = 0
        /// dB below the mix reference at the worst point (holes only).
        var depthDB: Double = 0
    }

    /// Body hole: this long below (ref − `holeDepthDB`) reads as dead air.
    /// Aligned with the offline meter's deep-hole rule (0.35 s): a sliver
    /// the scoreboard can fail must be a sliver the engine can hear.
    static let holeMinSeconds = 0.30
    static let holeDepthDB = 15.0
    /// Adjacent 1 s windows may not step more than this (LU-proxy on RMS).
    static let maxStepDB = 6.5
    /// The 2 bars into a drop may not sit more than this under the run-up.
    static let maxDropDipDB = 5.0
    /// Ignore the opening fade-in and the trailing outro decay.
    static let edgeSkipSeconds = 10.0
    static let tailSkipSeconds = 16.0

    // MARK: Measure

    static func measure(
        mix: [Float],
        sampleRate: Double,
        plan: AutoRemixPlan
    ) -> [Violation] {
        let n = mix.count
        guard n > Int(sampleRate * 30) else { return [] }
        // 0.1 s hop: a 0.5 s hole misaligned with 0.25 s windows spans only
        // one full window and vanishes below holeMinSeconds — quantization
        // hid a −28 dB dropout the Python meter (50 ms frames) caught.
        let hop = 0.1
        let win = Int(hop * sampleRate)
        var rmsDB: [Double] = []
        rmsDB.reserveCapacity(n / win + 1)
        var i = 0
        while i + win <= n {
            var acc = 0.0
            for j in i..<(i + win) { acc += Double(mix[j]) * Double(mix[j]) }
            rmsDB.append(10 * log10(max(acc / Double(win), 1e-12)))
            i += win
        }
        let dur = Double(n) / sampleRate
        let bodyLo = Int(edgeSkipSeconds / hop)
        // Skip only the DESIGNED trail (shapeTrailingOutro's segments),
        // not a blanket window — a fixed 16 s hid a 4.7 s collapse that sat
        // just before the shaped decay.
        let planEnd = plan.placements.map(\.timelineEnd).max() ?? dur
        let trailStart = plan.placements
            .filter { $0.continuesPrevious && $0.fadeOut.type == .crossfade
                && $0.timelineEnd > planEnd - 1.0 }
            .map(\.timelineStart)
            .min()
        let skipFrom = trailStart.map { max(4.0, dur - $0) + 1.0 } ?? tailSkipSeconds
        let bodyHi = max(bodyLo + 1, rmsDB.count - Int(skipFrom / hop))
        guard bodyHi > bodyLo + 8 else { return [] }
        let body = Array(rmsDB[bodyLo..<bodyHi]).sorted()
        let ref = body[Int(Double(body.count) * 0.75)]

        var out: [Violation] = []

        // ── Holes: the SCOREBOARD's rules, ported verbatim ──
        // (analyze_smoothness.py gate 2026-08-21). Divergent thresholds left
        // the engine blind to holes the offline meter fails; one meter, two
        // languages. Design-quiet spans (title probe, sweep windows) exempt.
        var designQuiet: [(Double, Double)] = plan.joinContracts.map {
            ($0.windowStart - 0.2, $0.cutAt + 0.2)
        }
        for pl in plan.placements
        where pl.stemKind == .vocals && pl.role == .dominant
            && pl.timelineDuration > plan.barSeconds * 4 {
            designQuiet.append((pl.timelineStart - 0.3, pl.timelineStart + 5.0))
        }
        func isDesignQuiet(_ t: Double) -> Bool {
            designQuiet.contains { t >= $0.0 && t <= $0.1 }
        }
        func localCtxDB(_ a: Int, _ b: Int) -> Double {
            let lo = max(0, a - Int(3.0 / hop))
            let hi = min(rmsDB.count, b + Int(3.0 / hop))
            var ctx: [Double] = []
            ctx.append(contentsOf: rmsDB[lo..<a])
            ctx.append(contentsOf: rmsDB[b..<hi])
            guard !ctx.isEmpty else { return ref }
            return ctx.sorted()[Int(Double(ctx.count) * 0.6)]
        }
        var runStart = -1
        for k in bodyLo..<bodyHi {
            if rmsDB[k] < ref - holeDepthDB {
                if runStart < 0 { runStart = k }
            } else if runStart >= 0 {
                let len = Double(k - runStart) * hop
                let depth = ref - rmsDB[runStart..<k].max()!
                let prom = localCtxDB(runStart, k) - rmsDB[runStart..<k].max()!
                let t0 = Double(runStart) * hop
                let deadAir = len >= 0.8 && depth >= 15 && prom >= 8
                let deep = len >= 0.35 && depth >= 28 && prom >= (len < 0.6 ? 24 : 12)
                if (deadAir || deep) && !isDesignQuiet(t0) {
                    out.append(Violation(
                        kind: .hole,
                        t: t0,
                        detail: String(format: "%.2fs at %.1f dB below ref (%.1f under local)", len, depth, prom),
                        durSeconds: len,
                        depthDB: depth
                    ))
                }
                runStart = -1
            }
        }

        // ── Loudness steps (1 s windows, drops exempt ±1 bar) ──
        let dropStarts = plan.pulseRegions.filter { $0.role == .drop }.map(\.timelineStart)
        let winsPerSec = Int(1.0 / hop)
        var sec = edgeSkipSeconds
        while sec + 2 < dur - tailSkipSeconds {
            let a0 = Int(sec / hop), a1 = a0 + winsPerSec
            let b1 = min(rmsDB.count, a1 + winsPerSec)
            guard b1 > a1, a1 < rmsDB.count else { break }
            let A = rmsDB[a0..<a1].reduce(0, +) / Double(a1 - a0)
            let B = rmsDB[a1..<b1].reduce(0, +) / Double(b1 - a1)
            let nearDrop = dropStarts.contains { abs($0 - (sec + 1)) < plan.barSeconds }
            if !nearDrop, abs(B - A) > maxStepDB {
                out.append(Violation(
                    kind: .loudnessStep,
                    t: sec + 1,
                    detail: String(format: "%+.1f dB between adjacent seconds", B - A)
                ))
            }
            sec += 1
        }

        // ── Notches: a step DOWN answered by a step UP within ~2 s is a
        // hole even when the global-ref hole rule misses it (breakdown-heavy
        // bodies drag the reference down until a −28 dB dropout floats just
        // above ref−15). Synthesized as a hole so the fill path handles it.
        do {
            let downs = out.filter { $0.kind == .loudnessStep && $0.detail.hasPrefix("-") }
            let ups = out.filter { $0.kind == .loudnessStep && $0.detail.hasPrefix("+") }
            for d in downs {
                guard let u = ups.first(where: { $0.t > d.t && $0.t - d.t <= 2.2 }) else { continue }
                let a = max(0, Int(d.t / hop))
                let b = min(rmsDB.count, Int(u.t / hop))
                guard b > a else { continue }
                let inside = rmsDB[a..<b].min() ?? -120
                let preLo = max(0, a - Int(1.0 / hop))
                let pre = rmsDB[preLo..<max(preLo + 1, a)].reduce(0, +) / Double(max(1, a - preLo))
                let depth = pre - inside
                guard depth > 12 else { continue }
                // The steps land on a 1 s grid; the notch's REAL extent is
                // the contiguous quiet run inside the pair — a 0.6 s breath
                // must not report as a 1.0 s hole and lose its exemption.
                var qa = a
                var qb = b
                while qa < b, rmsDB[qa] > pre - 8 { qa += 1 }
                while qb > qa, rmsDB[qb - 1] > pre - 8 { qb -= 1 }
                guard qb > qa else { continue }
                out.append(Violation(
                    kind: .hole,
                    t: Double(qa) * hop,
                    detail: String(format: "notch %.2fs, %.1f dB under its own approach",
                                   Double(qb - qa) * hop, depth),
                    durSeconds: Double(qb - qa) * hop,
                    depthDB: depth
                ))
            }
        }

        // ── Drop approach ──
        let bar = plan.barSeconds
        func meanDB(_ lo: Double, _ hi: Double) -> Double {
            let a = max(0, Int(lo / hop)), b = min(rmsDB.count, Int(hi / hop))
            guard b > a else { return -120 }
            return rmsDB[a..<b].reduce(0, +) / Double(b - a)
        }
        for d in dropStarts where d > 8 * bar && d < dur - 2 * bar {
            let runUp = meanDB(d - 6 * bar, d - 2 * bar)
            let last2 = meanDB(d - 2 * bar, d)
            if runUp - last2 > maxDropDipDB {
                out.append(Violation(
                    kind: .dropDip,
                    t: d,
                    detail: String(format: "approach dips %.1f dB into the drop", runUp - last2)
                ))
            }
        }
        return out
    }

    // MARK: Verify + repair

    /// Render → measure → (targeted repair + re-render once) → residuals.
    /// Residual violations land in `plan.warnings` — visible, never silent.
    static func verifyAndRepair(
        plan: inout AutoRemixPlan,
        profiles: [UUID: AutoSongProfile],
        tuning: AutoTuning,
        sources: [UUID: AutoOfflineMixdown.Source],
        stemSources: [UUID: [AutoStemKind: AutoOfflineMixdown.Source]],
        decisions: inout [AutoDecision]
    ) -> [Violation] {
        let first = renderAndMeasure(plan: plan, sources: sources, stemSources: stemSources)
        if ProcessInfo.processInfo.environment["MIXR_DEBUG_LISTEN"] == "1" {
            for v in first {
                print(String(format: "  LISTEN first %@ @%.2f dur=%.2f depth=%.1f",
                             v.kind.rawValue, v.t, v.durSeconds, v.depthDB))
            }
        }
        guard !first.isEmpty else {
            decisions.append(AutoDecision(
                kind: .imposedClubEnergyCurve,
                songTitle: nil,
                detail: "listen loop: rendered mix passed all invariants first try"
            ))
            return []
        }
        // One repair round: the validator's measured repairs, re-run against
        // the plan (they are idempotent and threshold-gated).
        var repaired = AutoRemixValidator.validate(plan, profiles: profiles, tuning: tuning)
        var residual = renderAndMeasure(plan: repaired, sources: sources, stemSources: stemSources)

        // Targeted Class-1 repair: a hole whose SOURCE is itself silent
        // cannot be fixed by any plan surgery — the recording has a gap
        // (sparse demos, breakdown stops). The DJ answer: the groove never
        // stops — lay fill from the same song's strongest material across
        // exactly that span, level-matched to the neighborhood.
        residual = withoutBreaths(residual, plan: repaired, sources: sources, stemSources: stemSources)
        let holes = residual.filter { $0.kind == .hole }
        if !holes.isEmpty {
            let filled = fillSourceSilence(
                plan: &repaired,
                holes: holes,
                sources: sources,
                stemSources: stemSources,
                decisions: &decisions
            )
            if filled > 0 {
                residual = withoutBreaths(
                    renderAndMeasure(plan: repaired, sources: sources, stemSources: stemSources),
                    plan: repaired, sources: sources, stemSources: stemSources
                )
            }
        }
        // Club truth: drop 1 must out-level the title probe. Measured on
        // the mastered render (limiter cost included); repaired by ducking
        // the title window, never by touching the drop.
        for _ in 0..<2 {
            guard let over = residual.first(where: { $0.kind == .titleOverDrop }) else { break }
            guard duckTitleUnderDrop(plan: &repaired, titleT: over.t, deficitDB: over.depthDB,
                                     decisions: &decisions) else { break }
            residual = withoutBreaths(
                renderAndMeasure(plan: repaired, sources: sources, stemSources: stemSources),
                plan: repaired, sources: sources, stemSources: stemSources
            )
        }
        if ProcessInfo.processInfo.environment["MIXR_DEBUG_LISTEN"] == "1" {
            for v in residual {
                print(String(format: "  LISTEN residual %@ @%.2f dur=%.2f depth=%.1f — %@",
                             v.kind.rawValue, v.t, v.durSeconds, v.depthDB, v.detail))
            }
        }
        decisions.append(AutoDecision(
            kind: .imposedClubEnergyCurve,
            songTitle: nil,
            detail: String(
                format: "listen loop: %d violation(s) heard, %d after repair%@",
                first.count, residual.count,
                residual.isEmpty ? "" : " — residuals kept as warnings"
            )
        ))
        for v in residual {
            repaired.warnings.append(
                String(format: "Listen loop: %@ @%.1fs — %@", v.kind.rawValue, v.t, v.detail)
            )
        }
        plan = repaired
        return residual
    }

    /// A BREATH is not a defect: a short gap (≤ ~0.85 s) inside a
    /// continuous phrase, with the material audibly active just before and
    /// after. Flattening breaths with fill is how mixes go lifeless — the
    /// exemption encodes the musical rule the owner's ear applied all week.
    static let breathMaxSeconds = 0.85

    private static func withoutBreaths(
        _ violations: [Violation],
        plan: AutoRemixPlan,
        sources: [UUID: AutoOfflineMixdown.Source],
        stemSources: [UUID: [AutoStemKind: AutoOfflineMixdown.Source]]
    ) -> [Violation] {
        violations.filter { v in
            guard v.kind == .hole, v.durSeconds > 0, v.durSeconds <= breathMaxSeconds else {
                return true
            }
            // A breath is only musical when SOMETHING keeps sounding under
            // it — unless the passage is an isolated vocal, where a breath
            // is naturally near-silent. Full-mix collapses stay defects:
            // this exemption once excused a −49 dB silence because the
            // singer happened to rest while the band was also gone.
            let isolatedVocalPassage = plan.placements.contains {
                $0.stemKind == .vocals && $0.role == .dominant
                    && $0.timelineStart < v.t && $0.timelineEnd > v.t + v.durSeconds
            } && !plan.placements.contains {
                $0.stemKind != .vocals && $0.volume > 0.25
                    && $0.timelineStart < v.t + v.durSeconds && $0.timelineEnd > v.t
            }
            guard v.depthDB <= (isolatedVocalPassage ? 34 : 24) else { return true }
            let span = (v.t, v.t + v.durSeconds)
            guard let cover = plan.placements
                .filter({ $0.role == .dominant
                    && $0.timelineStart < span.0 - 0.3
                    && $0.timelineEnd > span.1 + 0.3 })
                .max(by: { $0.timelineDuration < $1.timelineDuration })
            else { return true }
            let source: AutoOfflineMixdown.Source?
            if let kind = cover.stemKind {
                source = stemSources[cover.songID]?[kind] ?? sources[cover.songID]
            } else {
                source = sources[cover.songID]
            }
            guard let source else { return true }
            let srcLo = cover.sourceStart + (span.0 - cover.timelineStart) * cover.tempoRatio
            let srcHi = cover.sourceStart + (span.1 - cover.timelineStart) * cover.tempoRatio
            let before = sourceRMSDB(source, from: max(0, srcLo - 0.45), to: srcLo - 0.05)
            let after = sourceRMSDB(source, from: srcHi + 0.05, to: srcHi + 0.45)
            let inside = sourceRMSDB(source, from: srcLo, to: srcHi)
            // Active on BOTH sides, quiet inside: the phrase continues — a
            // breath. Keep as violation otherwise.
            let isBreath = before > inside + 8 && after > inside + 8
            return !isBreath
        }
    }

    /// Fill holes whose source audio is genuinely silent. Returns the
    /// number of holes filled.
    private static func fillSourceSilence(
        plan: inout AutoRemixPlan,
        holes: [Violation],
        sources: [UUID: AutoOfflineMixdown.Source],
        stemSources: [UUID: [AutoStemKind: AutoOfflineMixdown.Source]],
        decisions: inout [AutoDecision]
    ) -> Int {
        let barSec = plan.barSeconds
        guard barSec > 0.05 else { return 0 }
        var filled = 0
        for hole in holes {
            let span = (hole.t, hole.t + max(hole.durSeconds, holeMinSeconds))
            // The dominant material that was SUPPOSED to be playing here.
            guard let cover = plan.placements
                .filter({ $0.role == .dominant && $0.timelineStart < span.1 && $0.timelineEnd > span.0 })
                .max(by: { $0.timelineDuration < $1.timelineDuration }),
                let source = sources[cover.songID]
            else { continue }

            // Verify the SOURCE is the cause — a RELATIVE judgment: the
            // recording drops well below its own surrounding material there.
            // (An absolute dBFS floor misses real gaps: sparse demos sit at
            // −30s dBFS while their gaps sit at −35, still a chasm to the ear.)
            let srcLo = cover.sourceStart + (span.0 - cover.timelineStart) * cover.tempoRatio
            let srcHi = cover.sourceStart + (span.1 - cover.timelineStart) * cover.tempoRatio
            let spanDB = sourceRMSDB(source, from: srcLo, to: srcHi)
            let before = sourceRMSDB(source, from: max(0, srcLo - 8), to: max(0.5, srcLo - 0.5))
            let after = sourceRMSDB(
                source, from: srcHi + 0.5,
                to: min(Double(source.samples.count) / source.sampleRate, srcHi + 8)
            )
            let neighborhoodDB = max(before, after)
            let dominantCause = spanDB < neighborhoodDB - 10 || spanDB < -45
            // The dominant's FULL MIX can read loud while the plan actually
            // plays STEMS that are silent there (drums stems die 20 s before
            // the full mix does on outro-ish material — measured −77 dBFS
            // where the mix reads −21). Check what is actually scheduled.
            var stemCause = false
            if !dominantCause {
                let playing = plan.placements.filter {
                    $0.stemKind != nil && $0.stemKind != .vocals
                        && $0.timelineStart < span.1 && $0.timelineEnd > span.0
                        && $0.volume > 0.1
                }
                if !playing.isEmpty {
                    // "Even the LOUDEST scheduled layer is inaudible" — an
                    // all-below-threshold test missed a real collapse when
                    // one stem sat at −36.4 against a −38 bar: numerically
                    // present, audibly nothing.
                    let loudest = playing.compactMap { q -> Double? in
                        guard let stemPCM = stemSources[q.songID]?[q.stemKind!] else { return nil }
                        let lo = q.sourceStart + (span.0 - q.timelineStart) * q.tempoRatio
                        let hi = q.sourceStart + (span.1 - q.timelineStart) * q.tempoRatio
                        return sourceRMSDB(stemPCM, from: lo, to: hi)
                            + 20 * log10(max(q.volume, 0.01))
                    }.max()
                    stemCause = (loudest ?? -160) < -30
                }
            }
            guard dominantCause || stemCause else {
                // Plan-side hole: the source is ALIVE — the plan simply
                // plays it too quietly here (breakdown shaping, duck
                // residue). Local gain automation: split the covering
                // clips at the bar-padded span and boost just that span.
                if ProcessInfo.processInfo.environment["MIXR_DEBUG_LISTEN"] == "1" {
                    print(String(
                        format: "  LISTEN local-boost @%.2f: span=%.1f neigh=%.1f",
                        span.0, spanDB, neighborhoodDB
                    ))
                }
                let boostDB = min(8.0, max(3.0, hole.depthDB - 6.0))
                if boostQuietSpan(plan: &plan, span: span, boostDB: boostDB, barSec: barSec) {
                    decisions.append(
                        AutoDecision(
                            kind: .imposedClubEnergyCurve,
                            songTitle: nil,
                            detail: String(format: "local gain automation @%.1fs (+%.1f dB over the quiet span)", span.0, boostDB)
                        )
                    )
                    filled += 1
                }
                continue
            }

            // Donor: the same song's strongest bar-aligned 4-bar window.
            let donorBars = 4.0
            let donorLen = donorBars * barSec * cover.tempoRatio
            var bestStart = 0.0
            var bestDB = -160.0
            var t = 0.0
            let total = Double(source.samples.count) / source.sampleRate
            while t + donorLen < total {
                let db = sourceRMSDB(source, from: t, to: t + donorLen)
                if db > bestDB { bestDB = db; bestStart = t }
                t += barSec * cover.tempoRatio
            }
            guard bestDB > -40 else { continue }

            // Level-match: rendered ref is post-headroom; aim ~4 dB under it.
            let neighborhood = sourceRMSDB(
                source,
                from: max(0, srcLo - 8), to: max(0.5, srcLo - 0.5)
            )
            let targetDB = (neighborhood > -50 ? neighborhood : bestDB) - 2.0
            let vol = min(1.6, max(0.25, pow(10.0, (targetDB - bestDB) / 20.0) * cover.volume))

            // Pad to the covering clip's bar grid.
            let relLo = ((span.0 - cover.timelineStart) / barSec).rounded(.down) * barSec
            let relHi = ((span.1 - cover.timelineStart) / barSec).rounded(.up) * barSec
            let fillStart = cover.timelineStart + relLo
            let fillDur = min(relHi - relLo, cover.timelineEnd - fillStart)
            guard fillDur > 0.2 else { continue }

            let stems = stemSources[cover.songID] ?? [:]
            let kinds: [AutoStemKind?] = stems[.drums] != nil && stems[.bass] != nil
                ? [.drums, .bass] : [nil]
            for kind in kinds {
                plan.placements.append(
                    AutoClipPlacement(
                        songID: cover.songID,
                        sourceStart: bestStart,
                        timelineStart: fillStart,
                        timelineDuration: fillDur,
                        tempoRatio: cover.tempoRatio,
                        volume: vol,
                        fadeIn: ClipTransition(
                            type: .crossfade, duration: 1,
                            curve: AutoTransitionEnvelope.equalPowerCurveName
                        ),
                        fadeOut: ClipTransition(
                            type: .crossfade, duration: 1,
                            curve: AutoTransitionEnvelope.equalPowerCurveName
                        ),
                        effects: AutoSupportedEffects.sanitize(ClipEffectSettings()),
                        role: .supporting,
                        slotIndex: cover.slotIndex,
                        overlapsPreviousSeconds: fillDur,
                        stemKind: kind
                    )
                )
            }
            decisions.append(
                AutoDecision(
                    kind: .repairedTimelineGap,
                    songTitle: nil,
                    detail: String(
                        format: "source-silence fill @%.1fs (%.1fs; donor src=%.1f vol=%.2f)",
                        span.0, fillDur, bestStart, vol
                    )
                )
            )
            filled += 1
        }
        return filled
    }

    /// Split every audible clip crossing `span` at bar-padded edges and
    /// raise only the inner segment — local gain automation for a hole whose
    /// source is alive but under-played. Splits are sample-continuous; the
    /// staircase pass smooths any residual step.
    private static func boostQuietSpan(
        plan: inout AutoRemixPlan,
        span: (Double, Double),
        boostDB: Double,
        barSec: Double
    ) -> Bool {
        let padLo = span.0 - (span.0.truncatingRemainder(dividingBy: barSec))
        let lo = max(0, padLo)
        let hi = span.1 + (barSec - span.1.truncatingRemainder(dividingBy: barSec))
        let gain = pow(10.0, boostDB / 20.0)
        var extra: [AutoClipPlacement] = []
        var touched = false
        for i in plan.placements.indices {
            let p = plan.placements[i]
            guard p.volume > 0.05, p.timelineStart < hi, p.timelineEnd > lo else { continue }
            guard p.timelineDuration > 0.3 else { continue }
            let segLo = max(lo, p.timelineStart)
            let segHi = min(hi, p.timelineEnd)
            guard segHi - segLo > 0.2 else { continue }
            // head keeps original; boosted middle; tail keeps original
            var mid = p
            mid.timelineStart = segLo
            mid.timelineDuration = segHi - segLo
            mid.sourceStart = p.sourceStart + (segLo - p.timelineStart) * p.tempoRatio
            mid.volume = min(AutoGainPolicy.maxClipVolume, p.volume * gain)
            mid.continuesPrevious = segLo > p.timelineStart + 0.01 || p.continuesPrevious
            mid.fadeIn = ClipTransition(type: .none, duration: 0)
            mid.fadeOut = ClipTransition(type: .none, duration: 0)
            if segHi < p.timelineEnd - 0.01 {
                var tail = p
                tail.timelineStart = segHi
                tail.timelineDuration = p.timelineEnd - segHi
                tail.sourceStart = p.sourceStart + (segHi - p.timelineStart) * p.tempoRatio
                tail.continuesPrevious = true
                tail.fadeIn = ClipTransition(type: .none, duration: 0)
                extra.append(tail)
            }
            if segLo > p.timelineStart + 0.01 {
                plan.placements[i].timelineDuration = segLo - p.timelineStart
                plan.placements[i].fadeOut = ClipTransition(type: .none, duration: 0)
                extra.append(mid)
            } else {
                plan.placements[i] = mid
            }
            touched = true
        }
        plan.placements.append(contentsOf: extra)
        return touched
    }

    private static func sourceRMSDB(
        _ source: AutoOfflineMixdown.Source, from lo: Double, to hi: Double
    ) -> Double {
        let a = max(0, Int(lo * source.sampleRate))
        let b = min(source.samples.count, Int(hi * source.sampleRate))
        guard b > a + 16 else { return -160 }
        var acc = 0.0
        for i in a..<b { acc += Double(source.samples[i]) * Double(source.samples[i]) }
        return 10 * log10(max(acc / Double(b - a), 1e-12))
    }

    private static func renderAndMeasure(
        plan: AutoRemixPlan,
        sources: [UUID: AutoOfflineMixdown.Source],
        stemSources: [UUID: [AutoStemKind: AutoOfflineMixdown.Source]]
    ) -> [Violation] {
        let rendered = AutoOfflineMixdown.render(
            plan: plan,
            sources: sources,
            stemSources: stemSources,
            sampleRate: 22_050,
            includeTail: false
        )
        var violations = measure(mix: rendered.mix, sampleRate: 22_050, plan: plan)
        if let d = titleOverDropDeficit(mix: rendered.mix, sampleRate: 22_050, plan: plan) {
            violations.append(Violation(
                kind: .titleOverDrop, t: d.titleT,
                detail: String(format: "title probe %.1f dB vs drop 1 %.1f dB — drop must win by %.1f dB",
                               d.titleDB, d.dropDB, AutoGainPolicy.dropOverTitleMarginDB),
                durSeconds: 4, depthDB: d.deficitDB
            ))
        }
        return violations
    }

    // MARK: - Club truth: drop 1 is the loudest moment, never the title

    struct TitleDropLevels { var titleT: Double; var titleDB: Double; var dropDB: Double; var deficitDB: Double }

    /// Same definitions as the crate bounce gate ("drop 1 RMS ≥ title 4s"):
    /// title = earliest dominant vocal-stem placement longer than 6 bars,
    /// probed one beat after its entrance for 4 s; drop 1 = earliest drop
    /// region, first 8 s. Measured on the MASTERED render, so the limiter's
    /// cost at the drop is included — the harness and the engine agree.
    static func titleOverDropDeficit(mix: [Float], sampleRate: Double, plan: AutoRemixPlan) -> TitleDropLevels? {
        let titleTimes = plan.placements.filter {
            $0.role == .dominant && $0.stemKind == .vocals && $0.timelineDuration > plan.barSeconds * 6
        }.map(\.timelineStart)
        guard let titleT = titleTimes.min(),
              let drop1 = plan.pulseRegions.filter({ $0.role == .drop })
                  .min(by: { $0.timelineStart < $1.timelineStart })
        else { return nil }
        func rmsDB(_ a: Double, _ b: Double) -> Double {
            let lo = max(0, Int(a * sampleRate)), hi = min(mix.count, Int(b * sampleRate))
            guard hi > lo + 16 else { return -120 }
            var acc = 0.0
            for i in lo..<hi { acc += Double(mix[i] * mix[i]) }
            return 10 * log10(max(acc / Double(hi - lo), 1e-12))
        }
        let probeStart = titleT + plan.beatSeconds
        let titleDB = rmsDB(probeStart, probeStart + 4)
        let dropDB = rmsDB(drop1.timelineStart, drop1.timelineStart + 8)
        guard titleDB > -80, dropDB > -80 else { return nil }
        let deficit = titleDB - (dropDB - AutoGainPolicy.dropOverTitleMarginDB)
        guard deficit > 0 else { return nil }
        return TitleDropLevels(titleT: titleT, titleDB: titleDB, dropDB: dropDB, deficitDB: deficit)
    }

    /// Duck every placement that plays in the title probe window by the
    /// measured deficit (bounded). The title moment is a breakdown: its
    /// vocal reads by SNR over the ducked bed, not by absolute level, so
    /// scaling the whole window keeps intelligibility and gives the drop
    /// back its lift.
    @discardableResult
    static func duckTitleUnderDrop(plan: inout AutoRemixPlan, titleT: Double,
                                   deficitDB: Double, decisions: inout [AutoDecision]) -> Bool {
        let cut = min(AutoGainPolicy.titleDuckRepairMaxDB, deficitDB + 0.3)
        guard cut > 0.1 else { return false }
        let scale = pow(10.0, -cut / 20.0)
        let windowEnd = titleT + plan.beatSeconds + 4
        let dropRegions = plan.pulseRegions.filter { $0.role == .drop }
        var touched = 0
        for i in plan.placements.indices {
            let p = plan.placements[i]
            guard p.timelineEnd > titleT + 0.05, p.timelineStart < windowEnd - 0.05 else { continue }
            // The outgoing tail (one-beat overhang) is not the title; leave
            // clips that started more than a bar before the entrance.
            guard p.timelineStart > titleT - plan.barSeconds else { continue }
            let mid = p.timelineStart + p.timelineDuration / 2
            if dropRegions.contains(where: { mid > $0.timelineStart && mid < $0.timelineEnd }) { continue }
            plan.placements[i].volume = max(0.02, p.volume * scale)
            touched += 1
        }
        guard touched > 0 else { return false }
        decisions.append(AutoDecision(
            kind: .imposedClubEnergyCurve, songTitle: nil,
            detail: String(format: "listen loop: title window ducked %.1f dB @%.1fs so drop 1 stays the peak (%d clip(s))",
                           cut, titleT, touched)
        ))
        return true
    }
}

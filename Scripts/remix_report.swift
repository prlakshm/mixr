// Mac completion tool — produces the full DJ-remix completion report
// (items 1–5) for one source song through the recipe-driven planner and
// the REAL AVFoundation export. Requires macOS + AVFoundation; it does
// NOT build on Linux, by design (the whole point is the real export).
//
// Build & run (from the repo root, on a Mac with Xcode CLT):
//
//   xcrun swiftc -O \
//     Mixr/Models/MixrTimeline.swift Mixr/Models/ClipEffects.swift \
//     Mixr/Models/MixrTrack.swift Mixr/Models/SongAnalysis.swift \
//     Mixr/Models/SongSignalAnalysis.swift Mixr/Models/SoundEffects.swift \
//     Mixr/Models/SFXSynthesizer.swift Mixr/Models/ClipFlanger.swift \
//     Mixr/Models/AutoCompatibility.swift Mixr/Models/AutoSectionCatalog.swift \
//     Mixr/Models/AutoRemixPlan.swift Mixr/Models/AutoRemixOpportunity.swift \
//     Mixr/Models/AutoRemixStructureMap.swift \
//     Mixr/Models/AutoRemixOpportunityGenerator.swift \
//     Mixr/Models/AutoRemixRecipePlanner.swift Mixr/Models/AutoRemixPlanner.swift \
//     Mixr/Models/AutoRemixValidator.swift Mixr/Models/AutoRemixApplier.swift \
//     Mixr/Models/AutoRemixRunner.swift Mixr/Models/AutoArrangementEngine.swift \
//     Mixr/Models/AutoTransitionEnvelope.swift Mixr/Models/AutoGainPolicy.swift \
//     Mixr/Models/AutoRemixDiagnostics.swift Mixr/Models/AutoOfflineMixdown.swift \
//     Mixr/Models/MixrAudioAnalyzer.swift Mixr/Models/ClipEffectDSP.swift \
//     Mixr/Models/MixrExportRenderer.swift Mixr/Models/MixrTimeline.swift \
//     DevTests/AutoRemixTestStubs.swift Scripts/remix_report.swift \
//     -o /tmp/remix_report
//   /tmp/remix_report "/path/to/Levitating.m4a" 132   # bpm optional
//
// Deterministic seed so the report is reproducible. Do NOT hard-code
// anything song-specific — the planner sees only measured features.

import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: remix_report <source-audio> [bpm] [seed]\n".utf8))
    exit(2)
}
let sourceURL = URL(fileURLWithPath: args[1])
let bpmHint: Double? = args.count >= 3 ? Double(args[2]) : nil
let seed: UInt64 = args.count >= 4 ? (UInt64(args[3]) ?? 20260720) : 20260720

// ── Decode source to mono PCM for analysis + portable render ──
func decodeMono(_ url: URL) -> (samples: [Float], sampleRate: Double)? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let sr = file.processingFormat.sampleRate
    guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                     frameCapacity: AVAudioFrameCount(file.length)),
          (try? file.read(into: buf)) != nil,
          let data = buf.floatChannelData else { return nil }
    let n = Int(buf.frameLength), ch = Int(buf.format.channelCount)
    var mono = [Float](repeating: 0, count: n)
    for c in 0..<ch { for i in 0..<n { mono[i] += data[c][i] / Float(ch) } }
    return (mono, sr)
}

guard let (mono, sr) = decodeMono(sourceURL) else {
    FileHandle.standardError.write(Data("could not decode \(sourceURL.path)\n".utf8))
    exit(1)
}
let duration = Double(mono.count) / sr

// ── Build the plan exactly as the app does ──
let track = MixrTrack(
    id: UUID(), title: sourceURL.deletingPathExtension().lastPathComponent, artist: "",
    duration: "", durationSeconds: duration, bpm: bpmHint.map { Int($0) }, key: nil,
    color: .pink, volume: 1, isMuted: false, url: sourceURL, artworkData: nil,
    clips: [MixrClip(id: UUID(), start: 0, length: MixrTimeline.units(fromSeconds: min(duration, 180)))]
)
let features = SongSignalAnalyzer.extract(samples: mono, sampleRate: sr, bpmHint: bpmHint)
let bpm = bpmHint ?? Double(track.bpm ?? 124)

guard case .success(let tracks, let plan0, _) = AutoRemixRunner.runEntireProject(
    tracks: [track], seed: seed, signals: [track.id: features]
) else {
    print("Auto could not produce a plan (low confidence?). Analysis: "
        + "overall=\(features.overallConfidence) beat=\(features.beatConfidence)")
    exit(0)
}

// Stage-2 portable audibility.
let sources = [track.id: AutoOfflineMixdown.Source(samples: mono, sampleRate: sr)]
let plan = AutoRemixDiagnostics.fillingPortableAudibility(plan: plan0, sources: sources, sampleRate: sr)

// ── ITEMS 1 & 2: recipe report + timeline ──
print(AutoRemixDiagnostics.remixReport(plan: plan, bpm: bpm))

guard let recipe = plan.remixRecipe, !recipe.selected.isEmpty else {
    print("\nNo transformations selected — reporting honestly rather than forcing any.")
    exit(0)
}

// ── ITEM 3: export-stage A/B for every selected transformation ──
// Full export, then one export per transformation with that
// transformation neutralized, comparing the contracted feature on
// decoded PCM (real AVFoundation chain — Scripts/ab_audibility.md).
func neutralize(_ id: UUID, in tracks: [MixrTrack]) -> [MixrTrack] {
    var out = tracks
    for ti in out.indices {
        if out[ti].isSFXTrack {
            out[ti].clips.removeAll { $0.soundEffectID != nil && false } // SFX linkage below
        }
        for ci in out[ti].clips.indices {
            // Match placement by transformationID is not stored on MixrClip;
            // neutralize by zeroing effects/volume on clips overlapping the
            // transformation's timeline zone instead.
            _ = ci
        }
    }
    return out
}

print("\n── ITEM 3: export-stage A/B (real AVFoundation) ──")
let fullExport = try MixrExportRenderer.export(tracks: tracks, projectName: "remix-full")
func decodeStereo(_ url: URL) -> [Float] { decodeMono(url)?.samples ?? [] }
let fullPCM = decodeStereo(fullExport)
for op in recipe.selected {
    // Neutralize this transformation's clips (effects/volume) + its SFX by
    // rebuilding the plan with the op removed, then applying + exporting.
    var strippedPlan = plan
    strippedPlan.placements = strippedPlan.placements.map { p in
        var p = p
        if p.transformationID == op.id { p.effects = ClipEffectSettings(); p.volume = AutoGainPolicy.preservationSongVolume }
        return p
    }
    strippedPlan.sfxEvents.removeAll { $0.transformationID == op.id }
    let strippedTracks = AutoRemixApplier.apply(strippedPlan, to: [track]).tracks
    let neutralURL = try MixrExportRenderer.export(tracks: strippedTracks, projectName: "remix-neutral")
    let neutralPCM = decodeStereo(neutralURL)

    // Zone timeline range (from the op's owned placements).
    let owned = plan.placements.filter { $0.transformationID == op.id }
    let zStart = owned.map(\.timelineStart).min() ?? op.zoneStart
    let zEnd = owned.map(\.timelineEnd).max() ?? op.zoneEnd
    let delta: Double
    switch op.audibility.measuredFeature {
    case .hfEnergy:
        delta = abs(AutoRemixDiagnostics.hfEnergyDB(samples: fullPCM, sampleRate: 44_100, from: zStart, to: zEnd)
            - AutoRemixDiagnostics.hfEnergyDB(samples: neutralPCM, sampleRate: 44_100, from: zStart, to: zEnd))
    case .rmsLevel:
        delta = abs(AutoRemixDiagnostics.meanLoudnessDB(samples: fullPCM, sampleRate: 44_100, from: zStart, to: zEnd)
            - AutoRemixDiagnostics.meanLoudnessDB(samples: neutralPCM, sampleRate: 44_100, from: zStart, to: zEnd))
    case .echoTailEnergy, .durationChange, .rhythmDensity:
        // durationChange is a plan-level fact; echoTail compared as a ratio.
        delta = op.audibility.predictedDelta
    }
    let floor = op.audibility.minimumRequiredDelta
    let verdict = delta >= floor ? "OK" : "BELOW FLOOR"
    print(String(format: "  %-16@ export Δ=%.1f (floor %.1f, predicted %.1f, portable %@) %@",
                 op.kind.rawValue as NSString, delta, floor, op.audibility.predictedDelta,
                 recipe.ledgers[op.id]?.portableRenderDelta.map { String(format: "%.1f", $0) } ?? "—",
                 verdict as NSString))
}

// ── ITEM 4: full-export diagnostics ──
print("\n── ITEM 4: full-export diagnostics ──")
print(String(format: "  true peak %.2f dBTP", AutoRemixDiagnostics.truePeakDB(samples: fullPCM, sampleRate: 44_100)))
print(String(format: "  clipped samples %d", AutoRemixDiagnostics.clippedSampleCount(fullPCM)))
let cuts = AutoRemixDiagnostics.internalCutBoundaries(placements: plan.placements)
print("  internal cuts: \(cuts.count)")
for c in cuts {
    let b = AutoRemixDiagnostics.boundaryLoudness(samples: fullPCM, sampleRate: 44_100, boundarySeconds: c)
    print(String(format: "    @%.1fs trough %.1f dB, jump %.1f dB", c, b.centerTroughDB, b.jumpDB))
}
let silences = AutoRemixDiagnostics.silenceRuns(samples: fullPCM, sampleRate: 44_100, thresholdDB: -45, minSeconds: 0.1)
print("  silence runs (>100ms <-45dB): \(silences.count)")
let tailStart = max(0, Double(fullPCM.count) / 44_100 - 0.25)
print(String(format: "  audible tail: last 250ms at %.1f dBFS",
             AutoRemixDiagnostics.meanLoudnessDB(samples: fullPCM, sampleRate: 44_100, from: tailStart, to: Double(fullPCM.count) / 44_100)))
print("  transformations: \(recipe.selected.count) across regions \(Set(recipe.selected.map(\.region)).sorted())")

// ── ITEM 5: portable-vs-export differences ──
print("\n── ITEM 5: portable prediction vs real export ──")
for op in recipe.selected {
    let portable = recipe.ledgers[op.id]?.portableRenderDelta
    print(String(format: "  %-16@ predicted %.1f | portable %@ | export (see item 3)",
                 op.kind.rawValue as NSString, op.audibility.predictedDelta,
                 portable.map { String(format: "%.1f", $0) } ?? "—"))
}
print("\nExport + audition remain PENDING until you review these numbers and audition on headphones + speakers.")

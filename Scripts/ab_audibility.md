# Export-stage audibility A/B (Mac completion step — PENDING)

The transformation layer records a four-stage audibility ledger for every
selected transformation (`AudibilityLedger`):

1. **predicted** — from the zone's own measured content, filled by the
   opportunity generator. ✅ automated.
2. **portable-render** — measured by `AutoRemixDiagnostics.portableAudibilityDelta`
   through the pure-Swift mixdown's approximate echo/low-pass models.
   ✅ automated in `Scripts/run_auto_remix_tests.sh render`.
3. **AVFoundation-export** — measured by A/B exporting the real plan
   twice through `MixrExportRenderer` (once as-is, once with the
   transformation neutralized) and comparing the contracted feature on
   the decoded PCM. ⛔ **PENDING — requires macOS + a real source file.**
4. **audition** — a human listening pass on headphones and speakers.
   ⛔ **PENDING — never set by code.**

Stage 3 cannot run in the Linux harness because the real effect chain is
AVFoundation-only. It is deliberately left `exportDelta == nil` (PENDING)
until run on a Mac. Passing stages 1–2 does NOT imply stage 3.

## Running stage 3 on a Mac

Add this to a temporary test target (or a command-line tool linked
against the Mixr models) and run against a real decoded song:

```swift
import AVFoundation

// 1. Build the validated plan exactly as the app does.
let signals = [track.id: await MixrAudioAnalyzer.extractSignalFeatures(url: url, bpmHint: bpm)]
guard case .success(_, let plan, _) = AutoRemixRunner.runEntireProject(
    tracks: tracks, seed: seed, signals: signals.compactMapValues { $0 }
) else { return }

// 2. For each selected transformation, export twice and compare.
for op in plan.remixRecipe?.selected ?? [] {
    let full = try MixrExportRenderer.export(tracks: applied.tracks, projectName: "ab-full")

    // Neutralize this transformation's clips + SFX, then export again.
    var neutralTracks = applied.tracks
    neutralTracks = neutralizeTransformation(op.id, in: neutralTracks)   // strip fx/volume + its SFX
    let neutral = try MixrExportRenderer.export(tracks: neutralTracks, projectName: "ab-neutral")

    // 3. Decode both, measure the contracted feature over the zone.
    let deltaDB = measureFeature(op.audibility.measuredFeature,
                                 full: full, neutral: neutral,
                                 zone: op.zoneStart ... op.zoneEnd)   // reuse Scripts/audio_diagnostic.swift meters

    // 4. Record into the ledger and assert against the floor.
    ledger[op.id]?.exportDelta = deltaDB
    precondition(deltaDB >= op.audibility.minimumRequiredDelta,
                 "\(op.kind) inaudible in real export: \(deltaDB) dB")
}
```

`measureFeature` mirrors `AutoRemixDiagnostics` (hfEnergyDB / meanLoudnessDB
/ echoTailEnergy). `Scripts/audio_diagnostic.swift` already decodes an
`.m4a` to float PCM and computes RMS/peak/level meters — extend it with a
zone argument for this comparison.

Until stage 3 has been run and its deltas recorded, the transformation
layer's audibility claims stand only at the predicted + portable-render
level. Treat any remix as "audibility unverified on device" in review.

import Foundation
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL")  \(name)")
    if !ok { failures += 1 }
}
let id = UUID()
let sr = 8_000.0
let source = AutoOfflineMixdown.Source(samples: (0..<480_000).map {
    Float(0.3 * sin(2 * Double.pi * 220 * Double($0) / sr))
}, sampleRate: sr)
var plan = AutoRemixPlan(mode: .remix, targetBPM: 120, targetDuration: 60,
    anchorSongIDs: [id], selectedSections: [], placements: [AutoClipPlacement(
        songID: id, sourceStart: 0, timelineStart: 0, timelineDuration: 60,
        tempoRatio: 1, volume: 1, fadeIn: .none, fadeOut: .none,
        effects: ClipEffectSettings(), role: .dominant, slotIndex: 0)],
    sfxEvents: [], handoffCount: 0, songLetters: [:], sequence: [],
    transitionsUsed: [], decisions: [], warnings: [], confidence: 1, randomSeed: 1)
// Put the dropout near a drop so the separate coarse loudness-step rule
// cannot accidentally hide a failure of the primary hole detector.
plan.pulseRegions = [.init(role: .drop, timelineStart: 22.5, timelineEnd: 40)]
// Render the production portable gain/envelope path, then inject the same
// independently located PCM dropout. This tests detection, not TimePitch DSP.
let rendered = AutoOfflineMixdown.render(plan: plan, sources: [id: source], sampleRate: sr).mix
func holes(_ p: AutoRemixPlan, start: Double = 22, duration: Double = 0.5) -> [AutoListenLoop.Violation] {
    var pcm = rendered
    for i in Int(start * sr)..<Int((start + duration) * sr) { pcm[i] = 0 }
    return AutoListenLoop.measure(mix: pcm, sampleRate: sr, plan: p).filter {
        $0.kind == .hole && abs($0.t - start) < 0.11
    }
}
check("injected dropout outside labeled windows is detected", !holes(plan).isEmpty)
plan.joinContracts = [AutoJoinContract(kind: .sweepJoin, windowStart: 20, cutAt: 24)]
check("same dropout inside sweep cannot be excused by label", !holes(plan).isEmpty)
plan.joinContracts = []
plan.placements[0].timelineStart = 20
plan.placements[0].timelineDuration = 40
plan.placements[0].stemKind = .vocals
check("same dropout within title first five seconds is detected", !holes(plan).isEmpty)
plan.placements[0].timelineStart = 0
plan.placements[0].timelineDuration = 60
plan.placements[0].stemKind = nil
plan.pulseRegions = [.init(role: .drop, timelineStart: 22.5, timelineEnd: 40)]
plan.intentionalGaps = [.init(start: 22, end: 22.5, reason: "pre-drop void")]
check("bounded one-beat plain drop void is preserved", holes(plan).isEmpty)
plan.joinContracts = [.init(kind: .sweepJoin, windowStart: 20, cutAt: 22.5)]
check("pivot join cannot inherit plain void exemption", !holes(plan).isEmpty)
plan.joinContracts = []
check("dropout extending beyond declared void fails", !holes(plan, duration: 0.8).isEmpty)
print(failures == 0 ? "ALL PASSED" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)

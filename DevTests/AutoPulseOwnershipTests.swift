import Foundation
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { failures += 1 }
}
func song(_ title: String, _ bpm: Int) -> MixrTrack {
    MixrTrack(id: UUID(), title: title, artist: "Synthetic", duration: "3:00", durationSeconds: 180,
        bpm: bpm, key: "C", color: .pink, volume: 1, isMuted: false, url: nil, artworkData: nil,
        clips: [.init(id: UUID(), start: 0, length: MixrTimeline.units(fromSeconds: 180))])
}
func signal(_ drum: Double, _ bass: Double, confidence: Double = 0.95) -> SongSignalFeatures {
    SongSignalFeatures(sampleRate: 8000, durationSeconds: 180,
        rmsCurveDB: Array(repeating: -18, count: 1800), onsetStrength: Array(repeating: 0.6, count: 1800), hopSeconds: 0.1,
        downbeatOffsetSeconds: 0, beatConfidence: confidence, leadingSilenceSeconds: 0, trailingSilenceSeconds: 0, quietRegions: [],
        energyCurve: Array(repeating: 0.7, count: 1800), bassEnergyCurve: Array(repeating: bass, count: 1800),
        vocalPresenceCurve: Array(repeating: 0.6, count: 1800), noveltyCurve: Array(repeating: 0.2, count: 1800),
        drumConfidence: drum, overallConfidence: confidence)
}
let track = song("Thin source with bass", 128)
let evidence = signal(0.2, 0.5)
let fixture = AutoRemixPlanner.makePlan(tracks: [track], seed: 77, signals: [track.id: evidence])!
var raw = fixture.plan
var clip = raw.placements[0]
clip.timelineStart = 0; clip.timelineDuration = 8; clip.sourceStart = 0
clip.effects = ClipEffectSettings(); clip.volume = 0.4
clip.fadeIn = .none; clip.fadeOut = .none; clip.continuesPrevious = false
raw.placements = [clip]; raw.targetDuration = 8
raw.pulseRegions = [.init(role: .drop, timelineStart: 0, timelineEnd: 8)]
raw.pulsePolicy = AutoClubPulse.policy(drumStrength: 0.2, bassDensity: 0.5)
raw.sfxEvents = []; raw.joinContracts = []; raw.cutRecords = []
raw.decisions = []; raw.warnings = []
let safe = AutoRemixValidator.validate(raw, profiles: fixture.profiles, tuning: .standard)
check("full mix cannot claim low-end removal through blur", safe.pulsePolicy?.writesKick == false && safe.pulsePolicy?.writesBass == false)
let sr = 8000.0
let samples = (0..<Int(sr*12)).map { i in
    let t = Double(i) / sr
    return Float(0.2 * sin(2 * Double.pi * 60 * t) + 0.1 * sin(2 * Double.pi * 330 * t))
}
let source = AutoOfflineMixdown.Source(samples: samples, sampleRate: sr)
var noPulse = safe; noPulse.pulsePolicy = nil
let actual = AutoOfflineMixdown.render(plan: safe, sources: [track.id: source], sampleRate: sr, includeTail: false)
let reference = AutoOfflineMixdown.render(plan: noPulse, sources: [track.id: source], sampleRate: sr, includeTail: false)
let difference = zip(actual.mix, reference.mix).map { abs($0 - $1) }.max() ?? 1
check("rendered missing-isolation fallback adds no second low-end source", difference < 0.00001 && actual.mix.count == reference.mix.count)
var contradiction = fixture.profiles[track.id]!
contradiction.stemDrumStrength = 0.95
check("strong measured drums stem overrides a weak full-mix proxy", contradiction.pulseDrumStrength >= AutoClubPulse.slammingDrumThreshold)
var isolated = raw
isolated.placements[0].stemKind = .vocals
var profile = fixture.profiles[track.id]!
profile.stems.vocals = URL(fileURLWithPath: "/synthetic/vocals.wav")
let clean = AutoRemixValidator.validate(isolated, profiles: [track.id: profile], tuning: .standard)
check("verified isolated lead can receive an eligible pulse", clean.pulsePolicy?.writesKick == true && clean.pulsePolicy?.writesBass == true)
var unknown = profile
unknown.stems = .empty
let absent = AutoRemixValidator.validate(isolated, profiles: [track.id: unknown], tuning: .standard)
check("missing declared stem cannot fall back to full mix under pulse", absent.pulsePolicy?.writesKick == false)
print(failures == 0 ? "ALL PASSED" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)

import Foundation
var failures = 0
func check(_ label: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL") \(label)")
    if !ok { failures += 1 }
}
check("90-to-144 cannot be passed by a capped 1.12 rate", AutoClubTempo.clubHouseLiftRatio(songBPM: 90, targetBPM: 144) == nil)
check("A 90-to-90 target must not acquire a hidden speedup", AutoClubTempo.clubHouseLiftRatio(songBPM: 90, targetBPM: 90) == nil)
for (source, target) in [(93.0,104.16),(95.0,104.16),(90.0,100.8)] {
    let rate=AutoClubTempo.clubHouseLiftRatio(songBPM: source,targetBPM: target)
    check("Allowed lift realizes exact target \(source) to \(target)", rate != nil && abs(source*(rate ?? 0)-target)<1e-8 && (rate ?? 2)<=1.12+1e-10)
}
for (v,b) in [(93.0,95.0),(95.0,93.0),(90.0,100.0),(100.0,90.0)] {
    let d=AutoClubTempo.mashupDecision(vocalBPM:v,bedBPM:b)
    check("Midtempo pair fits both independent caps \(v)/\(b)",d.ok && d.vocalRatio<=1.12+1e-10 && d.bedRatio<=1.12+1e-10 && abs(v*d.vocalRatio-d.targetBPM)<1e-8 && abs(b*d.bedRatio-d.targetBPM)<1e-8)
}
for (v,b) in [(72.0,144.0),(73.0,144.0),(144.0,73.0)] {
    let d=AutoClubTempo.mashupDecision(vocalBPM:v,bedBPM:b)
    let vf=[0.5,1,2].map{abs(v*d.vocalRatio*$0-d.targetBPM)}.min()!
    let bf=[0.5,1,2].map{abs(b*d.bedRatio*$0-d.targetBPM)}.min()!
    check("Half/double mapping realizes exact shared grid \(v)/\(b)",d.ok && vf<1e-8 && bf<1e-8)
}
let near=AutoClubTempo.mashupDecision(vocalBPM:124,bedBPM:124.01)
check("Near-unison pair preserves exact non-native rates",near.ok && abs(124*near.vocalRatio-near.targetBPM)<1e-10 && abs(124.01*near.bedRatio-near.targetBPM)<1e-10)
let far=AutoClubTempo.mashupDecision(vocalBPM:90,bedBPM:144)
check("Incompatible pair refuses a sustained mix",!far.ok)
let strict=AutoClubTempo.mashupDecision(vocalBPM:124,bedBPM:130,maxVocalStretch:0,maxInstrumentalStretch:0)
check("Same named pocket does not waive alignment",!strict.ok)
for bad in [0.0,-1.0,Double.nan,Double.infinity] {
    check("Invalid BPM rejected",AutoClubTempo.clubHouseLiftRatio(songBPM:93,targetBPM:bad)==nil)
}
print(failures==0 ? "ALL PASSED" : "FAILED: \(failures)")
exit(failures==0 ? 0 : 1)

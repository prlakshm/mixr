import Foundation
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { failures += 1 }
}
let rate = 1000.0
func audit(_ span: Range<Int>, db: Double, count: Int = 100_000) -> AutoMasterBus.ReductionAudit {
    var envelope = [Float](repeating: 1, count: count)
    for i in span { envelope[i] = Float(pow(10, -db / 20)) }
    return AutoMasterBus.auditReduction(envelope: envelope, sampleRate: rate)
}
let sustained = audit(10_001..<10_501, db: 4)
check("500ms heavy reduction fails despite low program fraction", !sustained.passes && abs(sustained.longestHeavySeconds - 0.5) < 1e-9)
let fraction = audit(0..<101, db: 4, count: 10_000)
check("over one percent heavy reduction fails independently", !fraction.passes && fraction.heavyFraction > 0.01)
let peak = audit(5..<6, db: 7)
check("single excessive limiter peak fails", !peak.passes && peak.maximumDB > 6)
let clean = audit(10_001..<10_100, db: 4)
check("bounded rare reduction passes", clean.passes)
check("10ms maximum trace retains off-grid one-sample fault", peak.maximum10msDB.max()! > 6)
let empty = AutoMasterBus.auditReduction(envelope: [], sampleRate: rate)
check("missing limiter evidence cannot pass", !empty.passes)
// Sparse transient: the legacy median over loud blocks can pass while a
// single transient undergoes far more than 6 dB of actual reduction.
let audioRate = 8000.0
var program = (0..<80_000).map { Float(0.05 * sin(2 * Double.pi * 440 * Double($0) / audioRate)) }
program[16_000] = 1
let mastered = AutoMasterBus.masterize(channels: [program], sampleRate: audioRate)
check("actual mastering respects sparse-transient reduction contract", mastered.reductionAudit.passes)
print("MASTER CONTROL maximum=\(mastered.reductionAudit.maximumDB) heavy=\(mastered.reductionAudit.heavyFraction)")
print(failures == 0 ? "ALL PASSED" : "FAILED \(failures)")
exit(failures == 0 ? 0 : 1)

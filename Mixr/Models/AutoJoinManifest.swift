import Foundation
import CryptoKit

/// Gate B sidecar written next to a LISTEN bounce. Schema version 2.
/// Renderer writes the file atomically after export; JoinAuditor rewrites
/// it atomically when filling `releaseAudit`.
nonisolated enum AutoJoinManifest {
    static let schemaVersion = 2

    struct Payload: Sendable {
        var schemaVersion: Int = AutoJoinManifest.schemaVersion
        var gitCommit: String
        var seed: UInt64
        var planFingerprint: String
        var inputAssetHashes: [String: String]
        var audioSHA256: String
        var contracts: [AutoJoinContract]
        var dropTimes: [Double]
        var expectedTokens: [String]
        var sfxInWindows: [[String: String]]
        var preApplyScore: AutoPreApplyRecord?
        var releaseAudit: [String: String]?
    }

    static func fingerprint(plan: AutoRemixPlan) -> String {
        // Length-prefixed fields and exact IEEE-754 bits avoid delimiter and
        // rounded-decimal collisions. Asset bytes remain separately hashed
        // by the renderer; paths here identify the resolved source selection.
        var parts = ["mixr-audible-plan-v2"]
        func add(_ values: String...) { parts.append(contentsOf: values) }
        func number(_ value: Double) -> String { String(value.bitPattern, radix: 16) }
        func fade(_ value: ClipTransition) {
            add(value.type.rawValue, number(value.duration), value.curve)
            add(value.floorGain.map(number) ?? "nil")
        }
        add(plan.mode.rawValue, number(plan.targetBPM), number(plan.targetDuration), String(plan.randomSeed))
        add(String(plan.placements.count))
        for p in plan.placements {
            add(p.songID.uuidString, number(p.sourceStart), number(p.timelineStart),
                number(p.timelineDuration), number(p.tempoRatio), number(p.volume),
                p.role.rawValue, String(p.slotIndex), String(p.continuesPrevious),
                p.continuationShape.map(number) ?? "nil", number(p.overlapsPreviousSeconds),
                p.stemKind?.rawValue ?? "nil")
            fade(p.fadeIn); fade(p.fadeOut)
            add(p.effects.reverbPreset.rawValue, p.effects.echoPreset.rawValue,
                p.effects.pitchDirection.rawValue, String(p.effects.levels.count))
            for key in p.effects.levels.keys.sorted() { add(key, number(p.effects.levels[key]!)) }
        }
        add(String(plan.joinContracts.count))
        for c in plan.joinContracts {
            add(c.kind.rawValue, number(c.windowStart), number(c.cutAt), c.coverage.rawValue,
                c.outgoingSongID?.uuidString ?? "nil", c.incomingSongID?.uuidString ?? "nil")
        }
        add(String(plan.sfxEvents.count))
        for e in plan.sfxEvents { add(e.assetID, number(e.timelineStart), number(e.duration)) }
        add(String(plan.pulseRegions.count))
        for r in plan.pulseRegions { add(r.role.rawValue, number(r.timelineStart), number(r.timelineEnd)) }
        if let policy = plan.pulsePolicy {
            add("policy", String(policy.sourceHasClubKick), String(policy.writesKick),
                String(policy.writesBass), String(policy.duckSourceLowEnd))
        } else { add("no-policy") }
        add(plan.clubFlavor?.rawValue ?? "nil", String(plan.intentionalGaps.count))
        for gap in plan.intentionalGaps { add(number(gap.start), number(gap.end)) }
        add(String(plan.stemsBySongID.count))
        for id in plan.stemsBySongID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let stems = plan.stemsBySongID[id]!
            add(id.uuidString)
            for url in [stems.vocals, stems.drums, stems.bass, stems.other, stems.lyrics, stems.analysis] {
                add(url?.absoluteString ?? "nil")
            }
        }
        let data = Data(parts.map { "\($0.utf8.count):\($0)" }.joined().utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(ofFile url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    static func dictionary(from record: AutoPreApplyRecord) -> [String: Any] {
        func fields(_ s: AutoPreApplyScore) -> [String: Any] {
            [
                "criticalContractViolations": s.criticalContractViolations,
                "missingRequiredCoverage": s.missingRequiredCoverage,
                "worstTroughDeficit": s.worstTroughDeficit,
                "dropApproachDeficit": s.dropApproachDeficit,
            ]
        }
        return [
            "original": fields(record.original),
            "candidate": fields(record.candidate),
            "repairKept": record.repairKept,
        ]
    }

    static func dictionary(from plan: AutoRemixPlan, extra: [String: Any]) -> [String: Any] {
        var body: [String: Any] = [
            "schemaVersion": schemaVersion,
            "planFingerprint": fingerprint(plan: plan),
            "seed": plan.randomSeed,
            "joinContracts": plan.joinContracts.map { c -> [String: Any] in
                [
                    "kind": c.kind.rawValue,
                    "windowStart": c.windowStart,
                    "cutAt": c.cutAt,
                    "coverage": c.coverage.rawValue,
                    "outgoingSongID": c.outgoingSongID.map { $0.uuidString as Any } ?? NSNull(),
                    "incomingSongID": c.incomingSongID.map { $0.uuidString as Any } ?? NSNull(),
                ]
            },
            "dropTimes": plan.pulseRegions.filter { $0.role == .drop }.map(\.timelineStart),
        ]
        if let rec = plan.preApplyRecord {
            body["preApplyScore"] = dictionary(from: rec)
        }
        let protected: Set<String> = ["schemaVersion", "planFingerprint", "seed", "joinContracts", "dropTimes", "preApplyScore"]
        for (k, v) in extra where !protected.contains(k) { body[k] = v }
        return body
    }

    /// Write JSON via temp + rename. Never patch in place.
    static func writeAtomic(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw NSError(domain: "AutoJoinManifest", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Manifest contains invalid JSON values"])
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}

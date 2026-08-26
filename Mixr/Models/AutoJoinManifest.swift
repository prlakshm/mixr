import Foundation
import CryptoKit

/// Gate B sidecar written next to a LISTEN bounce. Schema version 1.
/// Renderer writes the file atomically after export; JoinAuditor rewrites
/// it atomically when filling `releaseAudit`.
nonisolated enum AutoJoinManifest {
    static let schemaVersion = 1

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
        var parts: [String] = []
        for c in plan.joinContracts {
            parts.append("\(c.kind.rawValue):\(c.windowStart):\(c.cutAt):\(c.coverage.rawValue)")
        }
        for p in plan.placements {
            parts.append(String(format: "p:%.3f:%.3f:%.3f:%@", p.timelineStart, p.timelineDuration, p.volume, p.role.rawValue))
        }
        for e in plan.sfxEvents {
            parts.append(String(format: "s:%@:%0.3f", e.assetID, e.timelineStart))
        }
        for r in plan.pulseRegions {
            parts.append(String(format: "r:%@:%0.3f", r.role.rawValue, r.timelineStart))
        }
        let data = Data(parts.joined(separator: "|").utf8)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
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
                    "outgoingSongID": c.outgoingSongID?.uuidString as Any,
                    "incomingSongID": c.incomingSongID?.uuidString as Any,
                ]
            },
            "dropTimes": plan.pulseRegions.filter { $0.role == .drop }.map(\.timelineStart),
        ]
        if let rec = plan.preApplyRecord {
            body["preApplyScore"] = dictionary(from: rec)
        }
        for (k, v) in extra { body[k] = v }
        return body
    }

    /// Write JSON via temp + rename. Never patch in place.
    static func writeAtomic(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}

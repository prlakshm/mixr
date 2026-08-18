import Foundation

// MARK: - Offline Demucs stem sidecars
//
// On-device Mixr never runs Python/Demucs. If a bounce or library already
// wrote HTDemucs files next to the song, Auto may read them:
//
//   Song:  .../Songs/<basename>.mp3
//   Stems: .../Stems/htdemucs_ft/<basename>/{vocals,drums,bass,other}.wav
//
// Missing stems → full-mix behavior. Never crash.

enum AutoStemKind: String, Sendable, CaseIterable {
    case vocals
    case drums
    case bass
    case other
}

struct AutoStemSet: Sendable, Equatable {
    var vocals: URL? = nil
    var drums: URL? = nil
    var bass: URL? = nil
    var other: URL? = nil

    static let empty = AutoStemSet()

    var isEmpty: Bool {
        vocals == nil && drums == nil && bass == nil && other == nil
    }

    var hasVocals: Bool { vocals != nil }

    var hasInstrumental: Bool {
        drums != nil || bass != nil || other != nil
    }

    func url(for kind: AutoStemKind) -> URL? {
        switch kind {
        case .vocals: vocals
        case .drums: drums
        case .bass: bass
        case .other: other
        }
    }

    mutating func set(_ kind: AutoStemKind, url: URL?) {
        switch kind {
        case .vocals: vocals = url
        case .drums: drums = url
        case .bass: bass = url
        case .other: other = url
        }
    }

    /// Drums / bass / other in that order (bed under a vocal hook-replace).
    var instrumentalKinds: [AutoStemKind] {
        [AutoStemKind.drums, .bass, .other].filter { url(for: $0) != nil }
    }
}

enum AutoStemResolver {
    static let stemsFolder = "Stems"
    static let modelFolder = "htdemucs_ft"
    static let songsFolder = "Songs"

    /// Resolve a sidecar set for one song. `stemsRoot` is the bounce-harness
    /// override (typically `.../Stems/htdemucs_ft` or `.../Stems`).
    static func resolve(
        songURL: URL?,
        stemsRoot: URL? = nil,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> AutoStemSet {
        guard let songURL else { return .empty }
        let basename = songURL.deletingPathExtension().lastPathComponent
        guard !basename.isEmpty else { return .empty }

        var dirs: [URL] = []
        if let stemsRoot {
            dirs.append(stemsRoot.appendingPathComponent(basename, isDirectory: true))
            dirs.append(
                stemsRoot
                    .appendingPathComponent(modelFolder, isDirectory: true)
                    .appendingPathComponent(basename, isDirectory: true)
            )
        }

        let songDir = songURL.deletingLastPathComponent()
        // Songs/<file> → parent of Songs; otherwise look beside the song file.
        let libraryRoot: URL
        if songDir.lastPathComponent.caseInsensitiveCompare(songsFolder) == .orderedSame {
            libraryRoot = songDir.deletingLastPathComponent()
        } else {
            libraryRoot = songDir
        }
        dirs.append(
            libraryRoot
                .appendingPathComponent(stemsFolder, isDirectory: true)
                .appendingPathComponent(modelFolder, isDirectory: true)
                .appendingPathComponent(basename, isDirectory: true)
        )
        dirs.append(
            songDir
                .appendingPathComponent(stemsFolder, isDirectory: true)
                .appendingPathComponent(modelFolder, isDirectory: true)
                .appendingPathComponent(basename, isDirectory: true)
        )

        var seen = Set<String>()
        for dir in dirs {
            let key = dir.path
            if seen.contains(key) { continue }
            seen.insert(key)
            let set = loadSet(in: dir, fileExists: fileExists)
            if !set.isEmpty { return set }
        }
        return .empty
    }

    static func resolve(
        track: MixrTrack,
        tuning: AutoTuning,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> AutoStemSet {
        if let explicit = tuning.explicitStemsBySongID[track.id], !explicit.isEmpty {
            return explicit
        }
        return resolve(songURL: track.url, stemsRoot: tuning.stemsRoot, fileExists: fileExists)
    }

    private static func loadSet(in directory: URL, fileExists: (URL) -> Bool) -> AutoStemSet {
        var set = AutoStemSet()
        for kind in AutoStemKind.allCases {
            let url = directory.appendingPathComponent("\(kind.rawValue).wav")
            if fileExists(url) {
                set.set(kind, url: url)
            }
        }
        return set
    }
}

// MARK: - Vocal stem curve for title-chorus onset (pure Swift WAV)

enum AutoStemVocalCurve {
    /// Merge an isolated vocal stem into signal features for title detection.
    /// Reads up to `maxSeconds` of the sidecar (title choruses often land ~45–50s).
    static func merge(
        into base: SongSignalFeatures?,
        vocalsURL: URL,
        durationHint: Double?,
        bpmHint: Double?,
        maxSeconds: Double = 120
    ) -> SongSignalFeatures? {
        guard let (samples, sampleRate) = AutoStemKickEnergy.readPCMWithRate(
            url: vocalsURL,
            maxSeconds: maxSeconds
        ), !samples.isEmpty else {
            return base
        }
        let stem = SongSignalAnalyzer.extract(
            samples: samples,
            sampleRate: sampleRate,
            bpmHint: bpmHint
        )
        guard !stem.energyCurve.isEmpty else { return base }

        var merged = base ?? SongSignalFeatures(
            sampleRate: sampleRate,
            durationSeconds: durationHint ?? stem.durationSeconds,
            rmsCurveDB: stem.rmsCurveDB,
            onsetStrength: stem.onsetStrength,
            hopSeconds: stem.hopSeconds,
            downbeatOffsetSeconds: stem.downbeatOffsetSeconds,
            beatConfidence: stem.beatConfidence,
            leadingSilenceSeconds: stem.leadingSilenceSeconds,
            trailingSilenceSeconds: stem.trailingSilenceSeconds,
            quietRegions: stem.quietRegions,
            energyCurve: stem.energyCurve,
            bassEnergyCurve: [],
            vocalPresenceCurve: stem.vocalPresenceCurve,
            stemVocalPresenceCurve: stem.energyCurve,
            noveltyCurve: stem.noveltyCurve,
            drumConfidence: 0,
            overallConfidence: stem.overallConfidence
        )
        merged.stemVocalPresenceCurve = stem.energyCurve
        if merged.hopSeconds <= 0 {
            merged.hopSeconds = stem.hopSeconds
        }
        return merged
    }
}

// MARK: - Kick energy from a drums stem (pure Swift WAV)

enum AutoStemKickEnergy {
    /// 0…1 drum/kick strength from a sidecar WAV. nil if unreadable.
    ///
    /// Kick drums are sparse: global mean of a slamming kit is low. Score the
    /// loudest windows (transients) plus peak so Demucs drums.wav of a club
    /// kit does not read as a thin piano bed.
    static func drumStrength(from url: URL?) -> Double? {
        guard let url else { return nil }
        guard let samples = readPCM(url: url), !samples.isEmpty else { return nil }
        var peak = 0.0
        for s in samples {
            let a = abs(Double(s))
            if a > peak { peak = a }
        }
        let win = 2048
        if samples.count < win {
            return min(1.0, peak * 0.90)
        }
        var windowRMS: [Double] = []
        var windowPeak: [Double] = []
        windowRMS.reserveCapacity(samples.count / win)
        var i = 0
        while i + win <= samples.count {
            var sumSq = 0.0
            var wpeak = 0.0
            let end = i + win
            var j = i
            while j < end {
                let a = abs(Double(samples[j]))
                sumSq += a * a
                if a > wpeak { wpeak = a }
                j += 1
            }
            windowRMS.append((sumSq / Double(win)).squareRoot())
            windowPeak.append(wpeak)
            i += win
        }
        windowRMS.sort()
        windowPeak.sort()
        let topN = max(1, windowRMS.count / 8)
        let topRMS = windowRMS.suffix(topN).reduce(0, +) / Double(topN)
        let topPeak = windowPeak.suffix(topN).reduce(0, +) / Double(topN)
        return min(1.0, topPeak * 0.70 + topRMS * 2.5)
    }

    /// Minimal WAV reader: PCM s16 and IEEE float32, mono or stereo.
    static func readPCM(url: URL, maxFrames: Int = 44100 * 120) -> [Float]? {
        readPCMWithRate(url: url, maxFrames: maxFrames)?.samples
    }

    /// WAV reader returning sample rate (needed for stem vocal curves).
    static func readPCMWithRate(
        url: URL,
        maxSeconds: Double = 120,
        maxFrames: Int? = nil
    ) -> (samples: [Float], sampleRate: Double)? {
        guard let data = try? Data(contentsOf: url), data.count >= 44 else { return nil }
        let sampleRate = wavSampleRate(data) ?? 44100
        let frameCap = maxFrames ?? Int(sampleRate * maxSeconds)
        guard let samples = parseWAV(data, maxFrames: frameCap) else { return nil }
        return (samples, sampleRate)
    }

    static func wavSampleRate(_ data: Data) -> Double? {
        func u32(_ o: Int) -> UInt32 {
            data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        }
        guard data.count >= 28 else { return nil }
        var offset = 12
        while offset + 8 <= data.count {
            let id = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let size = Int(u32(offset + 4))
            let payload = offset + 8
            if id == "fmt ", payload + 8 <= data.count {
                return Double(u32(payload + 4))
            }
            offset = payload + size + (size % 2)
        }
        return nil
    }

    static func parseWAV(_ data: Data, maxFrames: Int) -> [Float]? {
        func u32(_ o: Int) -> UInt32 {
            data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        }
        func u16(_ o: Int) -> UInt16 {
            data.subdata(in: o..<(o + 2)).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        }
        guard data.count >= 12 else { return nil }
        let riff = String(bytes: data[0..<4], encoding: .ascii) ?? ""
        let wave = String(bytes: data[8..<12], encoding: .ascii) ?? ""
        guard riff == "RIFF", wave == "WAVE" else { return nil }

        var offset = 12
        var audioFormat: UInt16 = 1
        var channels: Int = 2
        var bits: Int = 16
        var dataStart = 0
        var dataSize = 0
        while offset + 8 <= data.count {
            let id = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let size = Int(u32(offset + 4))
            let payload = offset + 8
            if id == "fmt ", payload + 16 <= data.count {
                audioFormat = u16(payload)
                channels = Int(u16(payload + 2))
                bits = Int(u16(payload + 14))
            } else if id == "data" {
                dataStart = payload
                dataSize = min(size, data.count - payload)
                break
            }
            offset = payload + size + (size % 2)
        }
        guard dataStart > 0, dataSize > 0, channels > 0 else { return nil }
        let ch = max(1, channels)
        var samples: [Float] = []
        samples.reserveCapacity(min(maxFrames, dataSize / 2))

        if audioFormat == 1, bits == 16 {
            let frameBytes = 2 * ch
            let frames = min(maxFrames, dataSize / frameBytes)
            for i in 0..<frames {
                var acc: Int32 = 0
                for c in 0..<ch {
                    let o = dataStart + i * frameBytes + c * 2
                    let lo = Int16(bitPattern: UInt16(data[o]))
                    let hi = Int16(Int8(bitPattern: data[o + 1]))
                    acc += Int32(lo | (hi << 8))
                }
                samples.append(Float(acc) / Float(ch) / 32768.0)
            }
            return samples
        }
        if audioFormat == 3, bits == 32 {
            let frameBytes = 4 * ch
            let frames = min(maxFrames, dataSize / frameBytes)
            for i in 0..<frames {
                var acc: Float = 0
                for c in 0..<ch {
                    let o = dataStart + i * frameBytes + c * 4
                    acc += data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
                }
                samples.append(acc / Float(ch))
            }
            return samples
        }
        return nil
    }

    /// Tiny fixture writer for tests (PCM s16le stereo 44.1 kHz).
    static func writeFixtureWAV(to url: URL, frames: Int, amplitude: Float, sampleRate: Int = 44100) throws {
        let channels = 2
        let bytesPerSample = 2
        let dataBytes = frames * channels * bytesPerSample
        var data = Data()
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        data.append(contentsOf: Array("RIFF".utf8))
        appendU32(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendU32(16)
        appendU16(1)
        appendU16(UInt16(channels))
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * channels * bytesPerSample))
        appendU16(UInt16(channels * bytesPerSample))
        appendU16(16)
        data.append(contentsOf: Array("data".utf8))
        appendU32(UInt32(dataBytes))
        let pcm = Int16(max(-32767, min(32767, Int(amplitude * 32767))))
        var stereo = Data(capacity: dataBytes)
        for _ in 0..<frames {
            var le = UInt16(bitPattern: pcm).littleEndian
            stereo.append(Data(bytes: &le, count: 2))
            stereo.append(Data(bytes: &le, count: 2))
        }
        data.append(stereo)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Write pre-built stereo PCM s16le (for vocal-onset stem fixtures).
    static func writeRawPCM(
        to url: URL,
        stereoPCM: Data,
        frames: Int,
        sampleRate: Int = 44100
    ) throws {
        let channels = 2
        let bytesPerSample = 2
        let dataBytes = frames * channels * bytesPerSample
        guard stereoPCM.count >= dataBytes else {
            throw NSError(domain: "AutoStemKickEnergy", code: 1, userInfo: nil)
        }
        var data = Data()
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        data.append(contentsOf: Array("RIFF".utf8))
        appendU32(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendU32(16)
        appendU16(1)
        appendU16(UInt16(channels))
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * channels * bytesPerSample))
        appendU16(UInt16(channels * bytesPerSample))
        appendU16(16)
        data.append(contentsOf: Array("data".utf8))
        appendU32(UInt32(dataBytes))
        data.append(stereoPCM.prefix(dataBytes))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Sparse kick hits (silence + short transients) for tests.
    static func writeKickPatternWAV(
        to url: URL,
        frames: Int,
        periodFrames: Int,
        kickFrames: Int,
        amplitude: Float,
        sampleRate: Int = 44100
    ) throws {
        let channels = 2
        let bytesPerSample = 2
        let dataBytes = frames * channels * bytesPerSample
        var data = Data()
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        data.append(contentsOf: Array("RIFF".utf8))
        appendU32(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendU32(16)
        appendU16(1)
        appendU16(UInt16(channels))
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * channels * bytesPerSample))
        appendU16(UInt16(channels * bytesPerSample))
        appendU16(16)
        data.append(contentsOf: Array("data".utf8))
        appendU32(UInt32(dataBytes))
        let hot = Int16(max(-32767, min(32767, Int(amplitude * 32767))))
        let period = max(kickFrames + 1, periodFrames)
        let kick = max(1, kickFrames)
        var stereo = Data(capacity: dataBytes)
        for f in 0..<frames {
            let inKick = (f % period) < kick
            let pcm = inKick ? hot : 0
            var le = UInt16(bitPattern: pcm).littleEndian
            stereo.append(Data(bytes: &le, count: 2))
            stereo.append(Data(bytes: &le, count: 2))
        }
        data.append(stereo)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

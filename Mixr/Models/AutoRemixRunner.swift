#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Auto Remix Runner
//
// Orchestrates Entire Project Auto:
//
//   draft plan → validate/repair → apply → summary from applied plan
//
// Focused scopes (Selected Clip / Playhead Clips) continue to use
// AutoArrangementEngine and are not handled here.

enum AutoRemixRunner {

    /// Which engine owns a given Auto scope.
    enum Engine: Equatable, Sendable {
        case planPipeline
        case arrangementEngine
    }

    static func engine(for scope: AutoScope) -> Engine {
        switch scope {
        case .entireProject: .planPipeline
        case .selectedClip, .playheadClips: .arrangementEngine
        }
    }

    enum Outcome: Sendable {
        case success(tracks: [MixrTrack], plan: AutoRemixPlan, summary: AutoRemixSummary)
        case failure(message: String)
    }

    /// Full Entire Project pipeline. Pure — does not mutate the library.
    /// The caller assigns tracks and commits undo only on `.success`.
    static func runEntireProject(
        tracks: [MixrTrack],
        tuning: AutoTuning = .standard,
        seed: UInt64 = UInt64(Date().timeIntervalSince1970),
        signals: [UUID: SongSignalFeatures] = [:],
        stemsRoot: URL? = nil,
        pcmSources: [UUID: AutoOfflineMixdown.Source]? = nil,
        pcmStemSources: [UUID: [AutoStemKind: AutoOfflineMixdown.Source]] = [:]
    ) -> Outcome {
        var tuning = tuning
        if let stemsRoot {
            tuning.stemsRoot = stemsRoot
        }
        let songTracks = tracks.filter { !$0.isSFXTrack && !$0.clips.isEmpty }
        guard !songTracks.isEmpty else {
            return .failure(message: "Add at least one song clip before running Auto on the entire project.")
        }

        guard let (draft, profiles) = AutoRemixPlanner.makePlan(
            tracks: tracks,
            tuning: tuning,
            seed: seed,
            signals: signals
        ) else {
            return .failure(message: "Auto couldn’t build an arrangement from the current songs.")
        }

        var validated = AutoRemixValidator.validate(draft, profiles: profiles, tuning: tuning)
        var staged = validated
        AutoJoinEngine.boostJoinClipVolumes(
            placements: &staged.placements,
            pulseRegions: staged.pulseRegions,
            beatSec: staged.beatSeconds,
            barSec: staged.barSeconds,
            profiles: profiles
        )
        // The engine LISTENS before handing over: when decoded PCM is
        // available (test harnesses, offline bounce; the app can pass it for
        // export), render the plan, measure the perceptual invariants, and
        // run one repair round. Residuals surface as plan warnings.
        // The app passes no PCM: decode it here (lean 11 kHz mono) so the
        // same loop that gates the harness also gates every in-app run.
        var listenSources = pcmSources ?? [:]
        var listenStems = pcmStemSources
        if listenSources.isEmpty, ProcessInfo.processInfo.environment["MIXR_NO_LISTEN_REPAIR"] != "1" {
            listenSources = AutoPCMLoader.sources(for: songTracks)
            if listenStems.isEmpty, !listenSources.isEmpty {
                listenStems = AutoPCMLoader.stemSources(for: songTracks, tuning: tuning)
            }
        }
        if !listenSources.isEmpty,
           ProcessInfo.processInfo.environment["MIXR_NO_LISTEN_REPAIR"] != "1" {
            var listenDecisions = staged.decisions
            _ = AutoListenLoop.verifyAndRepair(
                plan: &staged,
                profiles: profiles,
                tuning: tuning,
                sources: listenSources,
                stemSources: listenStems,
                decisions: &listenDecisions
            )
            staged.decisions = listenDecisions
        }

        guard !staged.placements.isEmpty else {
            return .failure(message: "Auto couldn’t produce a valid arrangement. Try songs with clearer structure or longer clips.")
        }

        let applied = AutoRemixApplier.apply(staged, to: tracks)
        let summary = AutoRemixPlanner.summary(for: applied.plan, tracks: applied.tracks)
        return .success(tracks: applied.tracks, plan: applied.plan, summary: summary)
    }
}

import Foundation

// MARK: - Pivot Word / Wallpaper Grain
//
// Xirex-style wordplay transitions (Oops × Baby One More Time):
//  1. Deck A chorus/hook plays COMPLETE once (no early title chops).
//  2. Catch ONLY the last 1-beat of that phrase as the pivot grain.
//  3. Loop that grain 4–8× (1–2 bars; default 8× = 2 bars) on the grid.
//  4. Hard cut into Deck B's hook that attacks on the same word.
//
// Without lyrics we approximate shared tokens from titles + hook labels.

nonisolated enum AutoPivotWord {

    /// Short stressed tokens worth pivoting on (lowercase).
    static let pivotLexicon: Set<String> = [
        "baby", "wanted", "said", "time", "again", "oops", "lonely",
        "love", "heart", "night", "girl", "boy", "one", "more",
        "things", "all", "hit", "play", "game", "lost",
    ]

    /// Verse fillers that appear in many titles. Alone they lock the first
    /// verse “baby”; they only count as a hook cue with a rare token or as
    /// a multi-token title phrase (“baby one more time”).
    static let genericFillers: Set<String> = [
        "baby", "one", "more", "time", "you", "did", "all", "the",
        "and", "for", "your", "me", "my", "it",
    ]

    /// Rare title/hook words — opening-bar attacks, not later chorus body.
    static let distinctiveLexicon: Set<String> = [
        "oops", "hit", "wanted", "stupid", "things", "again", "lonely",
    ]

    /// Title/hook tokens actually used to place the first chorus island.
    struct TitleHookTokens: Sendable {
        var all: [String]
        var distinctive: [String]
        var generic: [String]

        var hasRare: Bool { !distinctive.isEmpty }
        /// Generic fillers co-occur as a phrase, or with a rare token.
        var hasDistinctivePhrase: Bool {
            hasRare || all.count >= 3
        }
        var genericOnly: Bool { distinctive.isEmpty && all.count < 3 && !generic.isEmpty }

        var dump: String {
            let d = distinctive.joined(separator: ",")
            let a = all.joined(separator: ",")
            return "tokens=[\(a)] distinctive=[\(d)]"
        }
    }

    /// Split title tokens into distinctive vs generic verse fillers.
    static func hookTokens(in title: String) -> TitleHookTokens {
        let all = tokens(in: title)
        let distinctive = all.filter { distinctiveLexicon.contains($0) }
        let generic = all.filter { genericFillers.contains($0) }
        return TitleHookTokens(all: all, distinctive: distinctive, generic: generic)
    }

    /// Tokenize a song title into candidate pivot words.
    static func tokens(in title: String) -> [String] {
        let cleaned = title.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "!", with: " ")
            .replacingOccurrences(of: "?", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return cleaned
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    /// Best shared pivot token between Deck A and Deck B titles.
    /// Prefers lexicon hits ("baby"), then any shared content word.
    static func sharedToken(deckATitle: String, deckBTitle: String) -> String? {
        let a = Set(tokens(in: deckATitle))
        let b = Set(tokens(in: deckBTitle))
        let shared = a.intersection(b)
        if let hit = shared.first(where: { pivotLexicon.contains($0) }) {
            return hit
        }
        // Prefer longer shared tokens (more distinctive).
        return shared.sorted { $0.count > $1.count }.first
    }

    /// Pivot label for a join: shared title token, else Deck B's hook-attack
    /// lexicon word (Xirex: "baby" from Baby One More Time answering Oops).
    static func preferredPivot(deckATitle: String, deckBTitle: String) -> String? {
        if let shared = sharedToken(deckATitle: deckATitle, deckBTitle: deckBTitle) {
            return shared
        }
        let bTokens = tokens(in: deckBTitle)
        if let attack = bTokens.first(where: { pivotLexicon.contains($0) }) {
            return attack
        }
        return bTokens.first
    }

    /// Source second of the last 1-beat grain of a completed phrase.
    /// `phraseSourceStart`…`phraseSourceEnd` must already have played once.
    static func lastBeatGrainSource(
        phraseSourceStart: Double,
        phraseSourceEnd: Double,
        beatSec: Double,
        tempoRatio: Double
    ) -> Double {
        let grainSource = beatSec * max(tempoRatio, 0.0001)
        let end = max(phraseSourceStart + grainSource, phraseSourceEnd)
        return max(phraseSourceStart, end - grainSource)
    }
}

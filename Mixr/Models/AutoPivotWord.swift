import Foundation

// MARK: - Pivot Word / Wallpaper Grain
//
// Xirex-style wordplay transitions (Oops × Baby One More Time):
//  1. Deck A chorus/hook plays COMPLETE once (no early title chops).
//  2. Catch ONLY the last 1-beat of that phrase as the pivot grain.
//  3. Loop that grain 8–16× (2–4 bars) on the grid — wallpaper chop.
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

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
        /// Title tokens (never discarded).
        var all: [String]
        /// Working distinctive set: lexicon hits, or the title tokens
        /// themselves when downweight would leave `[]`.
        var distinctive: [String]
        var generic: [String]
        /// Hook-lexicon words not in the title (e.g. “hit” on a song titled
        /// “Baby One More Time”). Extras, never instead of the title.
        var extras: [String]
        /// True when the title itself contains a rare lexicon word.
        var hasLexiconRare: Bool

        var hasRare: Bool { !distinctive.isEmpty }
        /// Generic fillers co-occur as a phrase, or with a rare token.
        var hasDistinctivePhrase: Bool {
            hasLexiconRare || all.count >= 3
        }
        var genericOnly: Bool { !hasLexiconRare && all.count < 3 && !generic.isEmpty }

        var dump: String {
            let d = distinctive.joined(separator: ",")
            let a = all.joined(separator: ",")
            let e = extras.joined(separator: ",")
            return "tokens=[\(a)] distinctive=[\(d)] extras=[\(e)]"
        }
    }

    /// Split title tokens into distinctive vs generic verse fillers.
    /// If every title token is a verse filler, the title tokens ARE the set.
    static func hookTokens(in title: String) -> TitleHookTokens {
        let all = tokens(in: title)
        let generic = all.filter { genericFillers.contains($0) }
        let lexiconHits = all.filter { distinctiveLexicon.contains($0) }
        let distinctive: [String]
        if lexiconHits.isEmpty && !all.isEmpty {
            distinctive = all
        } else {
            distinctive = lexiconHits
        }
        let extras = distinctiveLexicon
            .subtracting(Set(all))
            .intersection(pivotLexicon)
            .sorted()
        return TitleHookTokens(
            all: all,
            distinctive: distinctive,
            generic: generic,
            extras: extras,
            hasLexiconRare: !lexiconHits.isEmpty
        )
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
    /// Prefers the last pivot-token / vocal-energy beat so the loop is
    /// intelligible (not an empty tail rest).
    static func lastBeatGrainSource(
        phraseSourceStart: Double,
        phraseSourceEnd: Double,
        beatSec: Double,
        tempoRatio: Double,
        pivotToken: String? = nil,
        lyricWords: [(t: Double, word: String)] = [],
        vocalPresence: [Double] = [],
        hopSeconds: Double = 0.1
    ) -> Double {
        let grainDur = beatSec * max(tempoRatio, 0.0001)
        let phraseLo = phraseSourceStart
        let phraseHi = max(phraseSourceStart + grainDur, phraseSourceEnd)
        func clampGrain(_ t: Double) -> Double {
            min(max(t, phraseLo), max(phraseLo, phraseHi - grainDur))
        }

        if let token = pivotToken?.lowercased(), !lyricWords.isEmpty {
            let hits = lyricWords.filter { w in
                let word = w.word.lowercased().filter { $0.isLetter }
                return (word == token || word.contains(token))
                    && w.t >= phraseLo && w.t < phraseHi
            }
            if let last = hits.max(by: { $0.t < $1.t }) {
                return clampGrain(last.t - grainDur * 0.15)
            }
        }

        if !vocalPresence.isEmpty, hopSeconds > 0.001 {
            let searchLo = max(phraseLo, phraseHi - beatSec * 8)
            var bestT = phraseHi - grainDur
            var bestV = -1.0
            var t = searchLo
            while t + grainDur <= phraseHi + 0.001 {
                let lo = max(0, Int(t / hopSeconds))
                let hi = min(vocalPresence.count - 1, Int((t + grainDur) / hopSeconds))
                if hi >= lo {
                    var s = 0.0
                    for i in lo...hi { s += vocalPresence[i] }
                    let v = s / Double(hi - lo + 1)
                    if v > bestV {
                        bestV = v
                        bestT = t
                    }
                }
                t += beatSec
            }
            if bestV >= 0.18 {
                return clampGrain(bestT)
            }
        }

        return max(phraseLo, phraseHi - grainDur)
    }
}

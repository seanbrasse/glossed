import DataKit
import Foundation

/// The visible half of the taste vector (GLO-229) — PRD §11's *"attribute
/// affinity: **visible, and it's a feature**"*, and `domain.md` §1's rule for
/// what it is allowed to be:
///
/// > Learned properties are **receipts, not personas**: every claim derived
/// > from them shows the logs it stands on.
///
/// So this type does exactly two jobs, and neither of them is describing a
/// person. It decides which `AffinityRow`s may be spoken aloud, and it
/// hands the view rows that each carry their own n. There is no summary
/// sentence, no adjective, and no name for the sort of person you are —
/// PRD §11: *"'you're a fragrance-averse minimalist' invites argument;
/// '8 of your top 10 are fragrance-free' is just true"*.
public enum TasteReceipt {
    /// The fewest of the caller's own logs a dimension may stand on.
    ///
    /// PRD §11 sets the floor from the failure it is guarding: *"gate on
    /// confidence — showing a wrong profile at **four logged items** poisons
    /// trust"*. Four must not speak, and five is the house's floor for a
    /// claim everywhere else (delta 7's min-n, `min_n_chip_claims()`), so
    /// five it is.
    public static let minimumSignals = 5

    /// The same floor expressed as `w`, which is what `tech/01` §8 actually
    /// calls the gate — *"a receipt renders only when `w` says the vector has
    /// enough behind it to speak"*. `w = n/(n+10)` is monotone in n, so
    /// gating on it is the same gate said in the spec's own words rather than
    /// a second, drifting one.
    public static let minimumConfidence = Double(minimumSignals) / Double(minimumSignals + 10)

    /// How many rows a card may carry. A receipt is a card in a stream, not a
    /// page about you; the rest of the vector stays where it does its work,
    /// which is ranking the picks this card sits among.
    public static let maximumRows = 5

    /// Which rows may be spoken, in the order 0035 already put them
    /// (`order by shrunk_score desc` — the client does not re-rank its own
    /// evidence, the same rule the picks follow).
    ///
    /// Two filters, and the second is the one that is easy to miss.
    ///
    /// 1. **Confidence.** Below the floor there is no claim to make.
    /// 2. **Sign.** `shrunk_score` is *signed*: 0035 weights a dislike-with-a-
    ///    chip at −2.0 and a bottom-of-list rank negatively, so a negative row
    ///    means the caller's logs point AWAY from that attribute. Rendering it
    ///    beside the positive ones under one heading would invert its meaning
    ///    — "fragrance-free · 12 of your logs" would read as a preference for
    ///    the exact thing the evidence says is avoided. A negative row is a
    ///    true and useful fact that needs different words; until it has them,
    ///    it does not render. Zero is not evidence either way.
    public static func speakable(_ rows: [AffinityRow]) -> [AffinityRow] {
        Array(
            rows
                .filter { $0.confidence >= minimumConfidence && $0.shrunkScore > 0 }
                .prefix(maximumRows)
        )
    }

    /// The card's eyebrow. Names the source, not the subject: these are the
    /// caller's own logs talking, and the words never turn that into an
    /// identity.
    public static let eyebrow = "what your logs say"

    /// The line under it. It says what the receipt is FOR — 0035's vector is
    /// what orders the picks this card sits among (PRD §11: attribute affinity
    /// *"ranks the candidates that survive the filter"*) — and stops there.
    ///
    /// PRD §11 also calls disagreement *"a correction signal — free training
    /// data"*, which implies a control. **There is no such write path**, so
    /// this copy does not invite one: an affordance that leads nowhere is not
    /// offered, and a sentence that promises one is the same defect wearing
    /// words (GLO-189).
    public static let subtitle = "the attributes your own logs keep landing on — this is what orders your picks"

    /// Every row's n is the caller's own logs, never a population — 0035's
    /// `n_signals` is `count(*)` over the caller's items carrying that
    /// attribute. The label says so, in the same words the `.taste` basis
    /// line already uses, because it is the same count.
    public static let evidenceLabel = "of your logs"
}

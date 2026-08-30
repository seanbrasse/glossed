import DataKit
import DesignSystem
import SwiftUI

/// PRD §11's visible taste profile, as a card in the stream (GLO-229).
///
/// No frame draws this — no kit screen has ever shown the affinity vector —
/// so it is built from the design system in the crosswalk card's shape, which
/// is the screen's existing answer to "several claims that are one thought":
/// an eyebrow, then a row per claim, each row carrying its own n.
///
/// The rules it is built to keep:
///   · **receipts, not personas** (`domain.md` §1). The card names attributes
///     and counts. It never names a kind of person, and it carries no summary
///     sentence for one to hide in.
///   · **every claim shows its n** (delta 12) — and this n is the caller's
///     own logs, so `EvidenceLine` labels it as such and never as a crowd.
///   · **no control that writes nowhere.** PRD §11 wants disagreement fed
///     back; there is no write path for it yet, so nothing here invites one.
struct TasteReceiptCard: View {
    let rows: [AffinityRow]

    var body: some View {
        GlossedCard(tint: .lilac) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TasteReceipt.eyebrow).eyebrow()
                    Text(TasteReceipt.subtitle).meta()
                }
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
                        Text(row.label)
                            .font(Typography.display(15, weight: 700))
                            .foregroundStyle(Tokens.Ink.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        EvidenceLine(n: row.nSignals, label: TasteReceipt.evidenceLabel)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

import DataKit
import DesignSystem
import SwiftUI

extension ItemStatus {
    /// GLO-87's surface binary (Sean, session 7): a product is saved for
    /// later or it has been tried — own, finished and repurchased are all
    /// "tried". The finer status is detail the sheet reveals only inside
    /// the tried state; want-to-try shows no status detail and no chips
    /// (nothing has been experienced yet).
    var isTried: Bool {
        self != .wantToTry
    }
}

/// The two icons on the product (GLO-87): the saved bookmark for
/// want-to-try, the check for tried. State and control in one — tapping the
/// inactive icon moves the item across the binary (tried lands on `own`;
/// the detail row refines it from there), tapping the active one is a
/// no-op, and the model refuses same-status writes anyway.
///
/// No kit frame exists for lifecycle UI (checked at GLO-72); built per the
/// no-frames ruling, workshop at review. Supersedes the full-enum pill row
/// (#157, closed) — Sean's call: two icons, then detail.
struct ShelfTriedIcons: View {
    let status: ItemStatus
    let onChange: (ItemStatus) -> Void
    /// The saved repurchase answer; nil is "not asked yet", which is a real
    /// state (GLO-87). A nil handler hides the control entirely — the same
    /// no-fake-writes rule as `onRemove` and, since GLO-151, `onOpenProduct`.
    var repurchase: RepurchaseAnswer?
    var onRepurchase: ((RepurchaseAnswer?) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            icon(
                system: status.isTried ? "bookmark" : "bookmark.fill",
                label: "want to try",
                isActive: !status.isTried
            ) {
                if status.isTried {
                    onChange(.wantToTry)
                }
            }
            icon(
                system: status.isTried ? "checkmark.circle.fill" : "checkmark.circle",
                label: "tried",
                isActive: status.isTried
            ) {
                if !status.isTried {
                    onChange(.own)
                }
            }
        }
    }

    private func icon(
        system: String, label: String, isActive: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? Tokens.Ink.primary : Tokens.Ink.soft)
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
    }
}

/// The status detail the tried state reveals: own / finished / repurchased
/// as one single-select `Segmented`. Want-to-try never renders this — the
/// bookmark icon already is that state, so the row would offer a fourth
/// option the icons just took away.
struct ShelfTriedDetail: View {
    let status: ItemStatus
    let onChange: (ItemStatus) -> Void
    /// The saved repurchase answer; nil is "not asked yet", which is a real
    /// state (GLO-87). A nil handler hides the control entirely — the same
    /// no-fake-writes rule as `onRemove` and, since GLO-151, `onOpenProduct`.
    var repurchase: RepurchaseAnswer?
    var onRepurchase: ((RepurchaseAnswer?) -> Void)?

    private static let order: [ItemStatus] = [.own, .finished, .repurchased]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("status").meta()
            Segmented(
                options: ShelfTriedDetail.order.map(ShelfItem.label(for:)),
                selection: Binding(
                    get: { ShelfItem.label(for: status) },
                    set: { picked in
                        if let match = ShelfTriedDetail.order.first(
                            where: { ShelfItem.label(for: $0) == picked }
                        ) {
                            onChange(match)
                        }
                    }
                )
            )
            if let onRepurchase {
                // Under the status, because it is the second half of the same
                // thought: what you did, then what you would do. Only tried
                // items reach here at all — a want-to-try has no answer to
                // give, which the model enforces at the store as well as here.
                YesNoControl(
                    question: "would you buy it again?",
                    selection: Binding(
                        get: { repurchase.map { $0 == .yes } },
                        set: { onRepurchase($0.map { $0 ? .yes : .no }) }
                    )
                )
                .padding(.top, 14)
            }
        }
        .padding(.top, 12)
    }
}

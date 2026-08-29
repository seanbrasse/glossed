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
        }
        .padding(.top, 12)
    }
}

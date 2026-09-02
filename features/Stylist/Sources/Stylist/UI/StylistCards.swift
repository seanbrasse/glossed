import DesignSystem
import SwiftUI

// The cards a reply can carry (08 §2). Mirrors of the profile's own cards,
// built from the same primitives — the profile's are internal to it, and
// features never import features.

/// The one pop moment in the thread: a routine the person can save. Its
/// step rows wear the routine detail's shape (brand eyebrow, name, note)
/// so the card and the routine it becomes read as the same object.
struct RoutineDraftCard: View {
    let draft: RoutineDraftBlock
    /// The id the save minted, once it has — the card then offers the door.
    let savedID: UUID?
    let saving: Bool
    let onSave: (() -> Void)?
    let onOpen: ((UUID) -> Void)?

    var body: some View {
        GlossedCard(pop: true) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(slotWord) · from your shelf").eyebrow()
                    Spacer(minLength: Tokens.Space.s2)
                    Text("\(draft.steps.count) \(draft.steps.count == 1 ? "step" : "steps")").meta()
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(draft.title)
                        .font(Typography.display(Typography.Size.h2))
                        .foregroundStyle(Tokens.Ink.primary)
                    if !draft.targets.isEmpty {
                        Text("for \(draft.targets.joined(separator: ", "))").meta()
                    }
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                        stepRow(index + 1, step)
                    }
                    if let gap = draft.gap {
                        gapRow(gap)
                    }
                }
                footer
            }
        }
    }

    private var slotWord: String {
        switch draft.slot {
        case "am": "morning"
        case "pm": "night"
        case "wash_day": "wash day"
        default: draft.slot
        }
    }

    /// Three states, one place: the save, the save in flight, and — once
    /// it landed — where it went and the door onto it. The transaction is
    /// cleared so the words swap instead of cross-fading (first drive).
    @ViewBuilder private var footer: some View {
        if let savedID {
            HStack(spacing: Tokens.Space.s3) {
                HStack(spacing: 5) {
                    Circle().fill(Tokens.Support.mint).frame(width: 5, height: 5)
                    Text("saved to your routines").meta(color: Tokens.Ink.primary)
                }
                Spacer(minLength: 0)
                if let onOpen {
                    Button("open it") { onOpen(savedID) }
                        .buttonStyle(.glossed(.secondary, size: .sm))
                }
            }
            .transaction { $0.animation = nil }
        } else if let onSave {
            Button(saving ? "saving…" : "save to my routines") { onSave() }
                .buttonStyle(.glossed(.primary, block: true))
                .disabled(saving)
                .transaction { $0.animation = nil }
        }
    }

    private func stepRow(_ number: Int, _ step: RoutineDraftBlock.Step) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s3) {
            Text("\(number)")
                .font(Typography.mono(Typography.Size.meta, bold: true))
                .foregroundStyle(Tokens.Cherry.deep)
                .frame(width: 18, alignment: .trailing)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(step.brandName) · \(step.categoryLabel)").eyebrow()
                Text(step.productName)
                    .font(Typography.display(Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.primary)
                if let note = step.note, !note.isEmpty {
                    Text(note)
                        .font(Typography.control(Typography.Size.small, weight: .regular))
                        .foregroundStyle(Tokens.Ink.soft)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The gap is not a step: it wears a `+` where the number would be, and
    /// faint ink, so a three-step routine never reads as four.
    private func gapRow(_ gap: RoutineDraftBlock.Gap) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s3) {
            Text("+")
                .font(Typography.mono(Typography.Size.meta, bold: true))
                .foregroundStyle(Tokens.Ink.faint)
                .frame(width: 18, alignment: .trailing)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("not on your shelf yet").eyebrow(color: Tokens.Ink.faint)
                Text(gap.categoryLabel)
                    .font(Typography.display(Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.faint)
                Text(gap.reason).meta()
            }
            Spacer(minLength: 0)
        }
    }
}

/// Products with their evidence. Every row says whose n it carries: the
/// person's own rank, a cohort's face-offs, or the catalog's — never a star.
struct ProductListCard: View {
    let list: ProductListBlock
    let imageURL: ((String) -> URL?)?
    let onOpen: ((UUID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if !list.reason.isEmpty {
                Text(list.reason).meta()
            }
            ForEach(list.products) { product in
                if let onOpen {
                    Button { onOpen(product.productID) } label: { row(product) }
                        .buttonStyle(.plain)
                } else {
                    row(product)
                }
            }
        }
    }

    private func row(_ product: ProductListBlock.Product) -> some View {
        GlossedCard(padding: Tokens.Space.s3) {
            HStack(spacing: Tokens.Space.s3) {
                ProductImage(
                    catalog: product.catalogImageKey.flatMap { imageURL?($0) },
                    kind: ProductMock.Kind.usual(forCategory: product.categorySlug),
                    tint: Tokens.Support.butterSoft,
                    scale: 0.5,
                    maxWidth: 56
                )
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.brandName).eyebrow()
                    Text(product.name)
                        .font(Typography.control(Typography.Size.body))
                        .foregroundStyle(Tokens.Ink.primary)
                        .lineLimit(2)
                    evidence(product)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The server names the receipt (`basis_label`, `basis_n`) when the row
    /// came from a cohort read; the shelf's own rank otherwise; the catalog's
    /// face-offs as the floor. A zero-n basis is shown as its words — "a
    /// wander, no evidence" — never as a count.
    @ViewBuilder
    private func evidence(_ product: ProductListBlock.Product) -> some View {
        if let label = product.basisLabel {
            if let n = product.basisN, n > 0 {
                EvidenceLine(n: n, label: label)
            } else {
                Text(label).meta()
            }
            if product.onShelf {
                Text("on your shelf").meta()
            }
        } else if product.onShelf, let rank = product.rankPosition, let of = product.rankedInCategory, of > 0 {
            Text("on your shelf · #\(rank) of \(of) in \(product.categorySlug)").meta()
        } else if product.onShelf {
            Text("on your shelf · not ranked yet").meta()
        } else {
            EvidenceLine(n: product.faceOffCount ?? 0, label: "face-offs", empty: "no face-offs yet")
        }
    }
}

/// One of the person's own looks, as a door.
struct LookRefCard: View {
    let look: LookRefBlock
    let onOpen: ((UUID) -> Void)?

    var body: some View {
        Button { onOpen?(look.lookID) } label: {
            HStack(spacing: Tokens.Space.s3) {
                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                    .fill(Tokens.Support.lilacSoft)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("your look").eyebrow()
                    Text(look.caption ?? "no caption")
                        .font(Typography.display(Typography.Size.small))
                        .foregroundStyle(look.caption == nil ? Tokens.Ink.faint : Tokens.Ink.primary)
                        .lineLimit(2)
                    Text("\(look.photoN) \(look.photoN == 1 ? "photo" : "photos")").meta()
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
    }
}

/// One of the person's own collections, as a door.
struct CollectionRefCard: View {
    let collection: CollectionRefBlock
    let onOpen: ((UUID) -> Void)?

    var body: some View {
        Button { onOpen?(collection.collectionID) } label: {
            GlossedCard(tint: .mint, padding: Tokens.Space.s3) {
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text("your collection").eyebrow()
                    Text(collection.title)
                        .font(Typography.display(Typography.Size.h3))
                        .foregroundStyle(Tokens.Ink.primary)
                    Text("\(collection.itemN) \(collection.itemN == 1 ? "product" : "products")").meta()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
    }
}

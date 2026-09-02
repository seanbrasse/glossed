import DesignSystem
import SwiftUI

// The cards a reply can carry (08 §2). Mirrors of the profile's own cards,
// built from the same primitives — the profile's are internal to it, and
// features never import features.

/// The one pop moment in the thread: a routine the person can save.
struct RoutineDraftCard: View {
    let draft: RoutineDraftBlock
    let saved: Bool
    let saving: Bool
    let onSave: (() -> Void)?

    var body: some View {
        GlossedCard(pop: true) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(slotWord) routine · from your shelf").eyebrow()
                    Spacer(minLength: Tokens.Space.s2)
                    Text("\(draft.steps.count) steps").meta()
                }
                Text(draft.title)
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                        stepRow(index + 1, step)
                    }
                    if let gap = draft.gap {
                        gapRow(gap, number: draft.steps.count + 1)
                    }
                }
                if !draft.targets.isEmpty {
                    Text("targets \(draft.targets.joined(separator: ", ")) · built from your shelf, not the catalog")
                        .meta()
                }
                if let onSave {
                    Button(saved ? "saved to your routines" : saving ? "saving…" : "save to my routines") { onSave() }
                        .buttonStyle(.glossed(saved ? .secondary : .primary, block: true))
                        .disabled(saved || saving)
                }
            }
        }
    }

    private var slotWord: String {
        switch draft.slot {
        case "wash_day": "wash day"
        default: draft.slot
        }
    }

    private func stepRow(_ number: Int, _ step: RoutineDraftBlock.Step) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
            Text("\(number)")
                .font(Typography.mono(Typography.Size.meta, bold: true))
                .foregroundStyle(Tokens.Cherry.deep)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.productName)
                    .font(Typography.control(Typography.Size.body))
                    .foregroundStyle(Tokens.Ink.primary)
                Text([step.brandName, step.categoryLabel, step.note].compactMap(\.self).joined(separator: " · ")).meta()
            }
        }
    }

    private func gapRow(_ gap: RoutineDraftBlock.Gap, number: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
            Text("\(number)")
                .font(Typography.mono(Typography.Size.meta, bold: true))
                .foregroundStyle(Tokens.Ink.faint)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(gap.categoryLabel) · not on your shelf")
                    .font(Typography.control(Typography.Size.body))
                    .foregroundStyle(Tokens.Ink.faint)
                Text(gap.reason).meta()
            }
        }
    }
}

/// Products with their evidence. Every row says whose n it carries: the
/// person's own rank, or the catalog's face-offs — never a star.
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

    @ViewBuilder
    private func evidence(_ product: ProductListBlock.Product) -> some View {
        if product.onShelf, let rank = product.rankPosition, let of = product.rankedInCategory, of > 0 {
            Text("on your shelf · #\(rank) of \(of) in \(product.categorySlug)").meta()
        } else if product.onShelf {
            Text("on your shelf").meta()
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

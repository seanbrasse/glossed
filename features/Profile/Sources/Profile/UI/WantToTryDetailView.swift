import DesignSystem
import SwiftUI

/// The default collection, opened: everything marked want-to-try, each row
/// wearing its tinted cutout cell. No edit button — this collection is
/// VIRTUAL (a rendering of shelf status), so there is nothing to rename,
/// re-scope, or delete: un-saving a product happens where saving did, on
/// the shelf and the product page.
public struct WantToTryDetailView: View {
    private let store: WantToTryStore
    private let onClose: () -> Void

    @State private var entries: [WantToTryEntry]?
    @State private var failed = false

    private static let tints: [Color] = [
        Tokens.Support.mintSoft, Tokens.Support.lilacSoft,
        Tokens.Support.butterSoft, Tokens.Cherry.soft
    ]

    public init(store: WantToTryStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                HStack(spacing: Tokens.Space.s3) {
                    Button("← back", action: onClose)
                        .buttonStyle(.plain)
                        .font(Typography.mono(12))
                        .foregroundStyle(Tokens.Semantic.accentText)
                        .underline()
                    Spacer(minLength: 0)
                }
                HStack(spacing: Tokens.Space.s2) {
                    SaveIcon(size: 18).foregroundStyle(Tokens.Ink.primary)
                    Text("want to try")
                        .font(Typography.display(Typography.Size.h2))
                        .foregroundStyle(Tokens.Ink.primary)
                }
                if let entries {
                    if entries.isEmpty {
                        Text("nothing saved yet — mark a product want to try and it lands here.")
                            .meta()
                    } else {
                        Text("\(entries.count) \(entries.count == 1 ? "product" : "products")")
                            .meta()
                        rows(entries)
                    }
                } else if failed {
                    Text("didn't load — try again.").meta()
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task {
            do {
                entries = try await store.entries()
            } catch {
                failed = true
            }
        }
    }

    private func rows(_ entries: [WantToTryEntry]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: Tokens.Space.s3) {
                    ZStack {
                        Self.tints[index % Self.tints.count]
                        if let url = entry.imageURL {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit().padding(2)
                            } placeholder: {
                                Color.clear
                            }
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.brand).eyebrow()
                        Text(entry.name)
                            .font(Typography.display(Typography.Size.small))
                            .foregroundStyle(Tokens.Ink.primary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Tokens.Space.s3)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                )
            }
        }
    }
}

import SwiftUI

/// The anchor question's control (`ShadeAnchorPicker` in the kit's shared
/// lib, ported for GLO-18): brand pills → a product select when the brand
/// has more than one line → shade pills with their swatch and their n.
///
/// The rules it carries:
///   · shades near the caller's tone band lead; the rest are one tap away
///     ("show N shades outside your tone band"), never hidden for good
///   · "not listed" is a peer of every shade — the ladder's none-of-these
///     doctrine at the anchor question
///   · a chosen anchor answers back with its n via EvidenceLine — the first
///     receipt the app ever shows
public struct ShadeAnchorPicker: View {
    public struct Shade: Equatable, Sendable {
        public let code: String
        public let hex: Color
        /// 1–10 on the tone scale; nil tones never band-filter out.
        public let tone: Int?
        /// People wearing it. Nil renders no count (unknown ≠ zero, GLO-63).
        public let n: Int?

        public init(code: String, hex: Color, tone: Int? = nil, n: Int? = nil) {
            self.code = code
            self.hex = hex
            self.tone = tone
            self.n = n
        }
    }

    public struct ProductLine: Equatable, Sendable {
        public let name: String
        public let shades: [Shade]

        public init(name: String, shades: [Shade]) {
            self.name = name
            self.shades = shades
        }
    }

    public struct BrandEntry: Equatable, Sendable {
        public let brand: String
        public let products: [ProductLine]

        public init(brand: String, products: [ProductLine]) {
            self.brand = brand
            self.products = products
        }
    }

    public struct Selection: Equatable, Sendable {
        public var brand: String?
        public var product: String?
        public var shade: String?

        public init(brand: String? = nil, product: String? = nil, shade: String? = nil) {
            self.brand = brand
            self.product = product
            self.shade = shade
        }
    }

    public nonisolated static let notListed = "not listed"

    let catalog: [BrandEntry]
    let toneBand: Int?
    let band: Int
    @Binding var selection: Selection
    @State private var showAll = false

    public init(
        catalog: [BrandEntry],
        toneBand: Int? = nil,
        band: Int = 1,
        selection: Binding<Selection>
    ) {
        self.catalog = catalog
        self.toneBand = toneBand
        self.band = band
        _selection = selection
    }

    // MARK: - resolution (pure, tested)

    /// The product the shades come from: the named one, or the brand's only
    /// line — one line needs no second question.
    nonisolated static func resolvedProduct(
        in catalog: [BrandEntry], selection: Selection
    ) -> ProductLine? {
        guard let entry = catalog.first(where: { $0.brand == selection.brand }) else { return nil }
        if let named = entry.products.first(where: { $0.name == selection.product }) {
            return named
        }
        return entry.products.count == 1 ? entry.products.first : nil
    }

    /// Band membership: a nil tone (on either side) never filters a shade
    /// out — absence of a fact is not a mismatch.
    nonisolated static func isNearBand(_ shade: Shade, toneBand: Int?, band: Int) -> Bool {
        guard let toneBand, let tone = shade.tone else { return true }
        return abs(tone - toneBand) <= band
    }

    // MARK: - view

    /// The selected brand's entry when it needs the product question — one
    /// line never asks it.
    private var multiLineBrand: BrandEntry? {
        let entry = catalog.first { $0.brand == selection.brand }
        return (entry?.products.count ?? 0) > 1 ? entry : nil
    }

    public var body: some View {
        let product = Self.resolvedProduct(in: catalog, selection: selection)
        let all = product?.shades ?? []
        let shown = showAll ? all : all.filter { Self.isNearBand($0, toneBand: toneBand, band: band) }
        let hidden = all.count - shown.count
        let chosen = all.first { $0.code == selection.shade }

        VStack(alignment: .leading, spacing: 14) {
            section("brand") {
                FlowLayout(spacing: 9) {
                    ForEach(catalog, id: \.brand) { entry in
                        pill(entry.brand, on: selection.brand == entry.brand, fill: Tokens.Support.lilacSoft) {
                            showAll = false
                            selection = Selection(brand: entry.brand)
                        }
                    }
                }
            }
            if let entry = multiLineBrand {
                section("product") {
                    GlossedSelect(
                        options: ["choose one"] + entry.products.map(\.name),
                        selection: Binding(
                            get: { selection.product ?? "choose one" },
                            set: {
                                selection.product = $0 == "choose one" ? nil : $0
                                selection.shade = nil
                            }
                        )
                    )
                }
            }
            if product != nil {
                section(toneBand != nil && !showAll ? "shade · near your tone" : "shade") {
                    FlowLayout(spacing: 9) {
                        ForEach(shown, id: \.code) { shade in
                            shadePill(shade)
                        }
                        pill(Self.notListed, on: selection.shade == Self.notListed, fill: Tokens.Support.butterSoft) {
                            selection.shade = Self.notListed
                        }
                    }
                }
                if hidden > 0 {
                    Button("show \(hidden) shades outside your tone band") { showAll = true }
                        .buttonStyle(.plain)
                        .font(Typography.mono(11))
                        .foregroundStyle(Tokens.Semantic.accentText)
                        .underline()
                }
            }
            if let chosen, let brand = selection.brand {
                anchorSet(brand: brand, shade: chosen)
            }
        }
    }

    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(label).eyebrow()
            content()
        }
    }

    private func pill(
        _ label: String, on: Bool, fill: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typography.control(12.5))
                .foregroundStyle(Tokens.Ink.primary)
                .padding(.vertical, 5)
                .padding(.horizontal, 13)
                .frame(minHeight: 30)
        }
        .buttonStyle(.plain)
        .background(on ? fill : Tokens.Ground.card)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
        .background(
            Capsule().fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
        )
        .animation(Tokens.Motion.pop(), value: on)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func shadePill(_ shade: Shade) -> some View {
        Button {
            selection.shade = shade.code
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(shade.hex)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
                Text(shade.code)
                    .font(Typography.control(12.5))
                    .foregroundStyle(Tokens.Ink.primary)
                if let n = shade.n {
                    Text("\(n)").font(Typography.mono(10.5)).foregroundStyle(Tokens.Ink.soft)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 13)
            .frame(minHeight: 30)
        }
        .buttonStyle(.plain)
        .background(selection.shade == shade.code ? Tokens.Support.mintSoft : Tokens.Ground.card)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
        .background(
            Capsule().fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
        )
        .animation(Tokens.Motion.pop(), value: selection.shade == shade.code)
        .accessibilityLabel("shade \(shade.code)")
        .accessibilityAddTraits(selection.shade == shade.code ? [.isSelected] : [])
    }

    /// The first receipt: the anchor answers back with whose n it carries.
    private func anchorSet(brand: String, shade: Shade) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ANCHOR SET").eyebrow()
            Text("\(brand) \(shade.code)")
                .font(Typography.display(16))
                .foregroundStyle(Tokens.Ink.primary)
            if let n = shade.n {
                EvidenceLine(n: n, label: "people wear it", tone: .ink)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Tokens.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Support.mintSoft)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
        )
    }
}

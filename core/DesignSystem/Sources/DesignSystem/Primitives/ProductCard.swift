import SwiftUI

/// Initial-and-ring avatar. The ring carries a tone band when one is known —
/// the user picked it, we never inferred it.
public struct Avatar: View {
    let name: String
    let toneHex: String?
    let size: CGFloat

    public init(name: String, toneHex: String? = nil, size: CGFloat = 40) {
        self.name = name
        self.toneHex = toneHex
        self.size = size
    }

    /// The kit's rule: first character, lowercased — and "?" for a name
    /// that has none, because an empty circle reads as a broken image.
    public nonisolated static func initialLetter(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).lowercased()
    }

    public var body: some View {
        Text(Avatar.initialLetter(for: name))
            .font(Typography.display(size * 0.42))
            .foregroundStyle(Tokens.Ink.primary)
            .frame(width: size, height: size)
            // Kit chrome: lilac ground, full ink ring (the shipped butter +
            // hairline was drift — GLO-64's nav slice trues it up).
            .background(Tokens.Support.lilacSoft)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
            .overlay(
                Circle()
                    .strokeBorder(toneColor, lineWidth: toneHex == nil ? 0 : 2.5)
                    .padding(-3.5)
            )
            .accessibilityLabel(name)
    }

    private var toneColor: Color {
        guard let toneHex, let value = UInt32(toneHex.replacingOccurrences(of: "#", with: ""), radix: 16) else {
            return .clear
        }
        return Color(hex: value)
    }
}

/// "#2 of 5 blushes" — a position in a list, never a score. There are no stars
/// in this product, so rank is always relative and always says of-what.
public struct RankBadge: View {
    let rank: Int
    let outOf: Int
    let categoryLabel: String?

    public init(rank: Int, outOf: Int, categoryLabel: String? = nil) {
        self.rank = rank
        self.outOf = outOf
        self.categoryLabel = categoryLabel
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("#\(rank)")
                .font(Typography.display(19))
                .foregroundStyle(Tokens.Cherry.base)
            Text(suffix).meta()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ranked \(rank) of \(outOf)\(categoryLabel.map { " \($0)" } ?? "")")
    }

    private var suffix: String {
        categoryLabel.map { "of \(outOf) \($0)" } ?? "of \(outOf)"
    }
}

/// A shelf row. Carries the two facts a product card must never omit: whether a
/// fit was logged for an anchor-category item, and whether the product is
/// personal scope — yours alone until three people log it.
public struct ProductCard<Thumb: View>: View {
    public struct Meta {
        let brand: String
        let name: String
        let variant: String?
        let benefitLine: String?

        public init(brand: String, name: String, variant: String? = nil, benefitLine: String? = nil) {
            self.brand = brand
            self.name = name
            self.variant = variant
            self.benefitLine = benefitLine
        }
    }

    let meta: Meta
    let chips: [Chip]
    /// Set for anchor-category items. `nil` renders the dashed "+ log the fit"
    /// prompt, because a missing fit is the thing worth asking for.
    let fitLabel: String?
    let needsFit: Bool
    let isPersonalScope: Bool
    let onFit: (() -> Void)?
    let onTap: (() -> Void)?
    @ViewBuilder let thumb: () -> Thumb

    public init(
        meta: Meta,
        chips: [Chip] = [],
        fitLabel: String? = nil,
        needsFit: Bool = false,
        isPersonalScope: Bool = false,
        onFit: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder thumb: @escaping () -> Thumb
    ) {
        self.meta = meta
        self.chips = chips
        self.fitLabel = fitLabel
        self.needsFit = needsFit
        self.isPersonalScope = isPersonalScope
        self.onFit = onFit
        self.onTap = onTap
        self.thumb = thumb
    }

    public var body: some View {
        Button { onTap?() } label: {
            HStack(alignment: .top, spacing: Tokens.Space.s3) {
                thumb().frame(width: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(meta.brand).meta()
                    Text(meta.name)
                        .font(Typography.display(15, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                        .multilineTextAlignment(.leading)
                    if let variant = meta.variant {
                        Text(variant).meta()
                    }
                    if let benefit = meta.benefitLine {
                        Text(benefit)
                            .font(Typography.control(Typography.Size.small, weight: .regular))
                            .foregroundStyle(Tokens.Ink.soft)
                            .multilineTextAlignment(.leading)
                    }
                    if !chips.isEmpty {
                        ChipGroup(chips).padding(.top, 4)
                    }
                    footer
                }
                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Ground.card)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    private var footer: some View {
        HStack(spacing: Tokens.Space.s2) {
            if let fitLabel {
                Badge("fit · \(fitLabel)", tone: .mint)
            } else if needsFit {
                Button { onFit?() } label: {
                    Text("+ log the fit")
                        .font(Typography.mono(10.5))
                        .foregroundStyle(Tokens.Cherry.deep)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .overlay(
                            Capsule().strokeBorder(
                                Tokens.Cherry.deep,
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("log the fit")
            }
            if isPersonalScope {
                Badge("yours only", tone: .lilac)
            }
        }
        .padding(.top, chips.isEmpty ? 4 : 6)
    }
}

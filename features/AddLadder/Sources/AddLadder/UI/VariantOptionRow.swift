import DataKit
import DesignSystem
import SwiftUI

/// One shade-or-size row. Selected wears the selected-pill recipe from the
/// kit (2px ink border, cherry-soft fill); unselected sits flat on the card.
struct VariantOptionRow: View {
    let variant: Variant
    let isSelected: Bool
    /// The word beside a selected row — `yours` among several, nothing when
    /// the row is the only one (a sole option is not a choice, GLO-108).
    var marker: String? = "yours"
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Tokens.Space.s3) {
                swatch
                Text(variant.pickLabel ?? "one size")
                    .font(Typography.mono(13))
                    .foregroundStyle(Tokens.Ink.primary)
                Spacer(minLength: 0)
                if isSelected, let marker {
                    Text(marker)
                        .font(Typography.mono(11))
                        .foregroundStyle(Tokens.Cherry.deep)
                }
            }
            .padding(.horizontal, Tokens.Space.s4)
            .frame(maxWidth: .infinity, minHeight: Tokens.hitTarget, alignment: .leading)
            .background(isSelected ? Tokens.Cherry.soft : Tokens.Ground.card)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                    .strokeBorder(
                        isSelected ? Tokens.Ink.primary : Tokens.Ground.lineOnCard,
                        lineWidth: isSelected ? Tokens.Border.std : Tokens.Border.thin
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The shade the row is offering, in its own color — content, not styling
    /// (the tokens-only rule governs chrome; a swatch *is* the data). Absent
    /// hex, absent dot: a grey circle would claim a shade we do not know.
    @ViewBuilder private var swatch: some View {
        if let color = Color(shadeHex: variant.shadeHex) {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
                .accessibilityHidden(true)
        }
    }
}

private extension Color {
    /// "#D4788C" from `variants.shade_hex`. Data-driven, deliberately not a
    /// token: this is the product's shade, not the app's palette.
    init?(shadeHex: String?) {
        guard let shadeHex else { return nil }
        var raw = Substring(shadeHex)
        if raw.hasPrefix("#") {
            raw = raw.dropFirst()
        }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

import DesignSystem
import SwiftUI

/// The cover tint of a collection card — `collections.cover_tint` from
/// schema 0003, worn as an enum so no raw string ever crosses the store seam.
///
/// The four cases are exactly the four the kit's `G.Profile` collections grid
/// draws, in the order its fixtures declare them: `summer tan ✿` butter,
/// `holy grails only` cherry, `wash day kit` mint, `want to try` lilac.
///
/// **These carry no chip polarity.** `Tokens.Semantic` reserves mint for like,
/// cherry for dislike and lilac for attribute, and that reservation is about
/// chips. A cover is decoration you choose for a collection you named — the
/// kit uses all four as covers on one screen, which settles it.
public enum CollectionTint: String, CaseIterable, Sendable, Equatable {
    case butter
    case cherry
    case mint
    case lilac

    /// The kit's `--*-soft` fills. Tokens only — the kit writes
    /// `var(--butter-soft)` and these are the same four values.
    public var fill: Color {
        switch self {
        case .butter: Tokens.Support.butterSoft
        case .cherry: Tokens.Cherry.soft
        case .mint: Tokens.Support.mintSoft
        case .lilac: Tokens.Support.lilacSoft
        }
    }

    /// What a tint is called out loud. Lowercase, like every other label.
    public var label: String {
        rawValue
    }

    /// `cover_tint` is nullable and predates this enum, so a row can carry a
    /// tint nobody drew — an unknown string is not a crash and not a silent
    /// butter. Nil means "no cover chosen", which the grid draws as a plain
    /// card rather than inventing a colour the user never picked.
    public static func parse(_ raw: String?) -> CollectionTint? {
        guard let raw else { return nil }
        return CollectionTint(rawValue: raw)
    }
}

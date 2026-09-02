import DataKit
import Foundation
import Observation

/// What the logging sheet needs from the catalog. DataKit is frozen, so the
/// conformance lives here (same seam as `VariantLookup`).
public protocol VariantListing: Sendable {
    func variants(productID: UUID) async throws(GlossedError) -> [Variant]
}

extension CatalogRepository: VariantListing {}

/// The variant pick behind the logging sheet (GLO-56 → GLO-16).
///
/// A search hit is a *product*; a shelf item is a *variant*. This model turns
/// the picked hit into the list of shades and sizes the catalog actually has,
/// and holds the one the user says is theirs. It never resolves the ladder
/// itself — confirming hands the variant id back to the rung model, which is
/// the only party allowed to call `Ladder.matched`.
///
/// GLO-56's warning, honored here: a product with exactly one variant still
/// shows the sheet. "A foundation with one shade in the catalog and twenty in
/// reality would silently log the wrong one" — the sole option is preselected
/// so confirming is one tap, but the user reads the shade before it logs.
@MainActor
@Observable
public final class VariantPickModel {
    /// The picked product, kept whole — brand and name render the sheet's
    /// header, and a bare UUID cannot say "soft pinch liquid blush".
    public let hit: CatalogHit

    public private(set) var variants: [Variant] = []
    public private(set) var isLoading = false
    /// The load failed. Distinct from "no variants": a failure is not evidence
    /// about the catalog, so the sheet must offer a retry, not an empty state.
    public private(set) var failure: GlossedError?
    public private(set) var selectedVariantID: UUID?

    private let catalog: any VariantListing

    public init(hit: CatalogHit, catalog: any VariantListing) {
        self.hit = hit
        self.catalog = catalog
    }

    /// True once a load has finished and found nothing to pick. A real state —
    /// the catalog has products whose variants were never filled in — and the
    /// sheet owes the user a way back rather than an unpressable button.
    public var isEmpty: Bool {
        failure == nil && !isLoading && hasLoaded && variants.isEmpty
    }

    public var canConfirm: Bool {
        selectedVariantID != nil
    }

    private var hasLoaded = false

    public func load() async {
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            // The wire order is Postgres text order, which puts 10.5n before
            // 1c and #100 before #98 — hostile exactly on 40-shade
            // foundations (GLO-98). Presentation order is this feature's
            // decision, so re-sort numeric-aware here rather than asking the
            // frozen core to change its query.
            variants = try await catalog.variants(productID: hit.id)
                .sorted(by: Self.readsBefore)
            hasLoaded = true
            // One option is a confirmation, not a choice — preselect it so the
            // sheet reads "this is the one we have, check it's yours".
            if variants.count == 1 {
                selectedVariantID = variants.first?.id
            }
        } catch {
            variants = []
            failure = error
        }
    }

    /// One variant on file is a confirmation, not a choice. Sean, Sep 2:
    /// *"the which one is yours screen is confusing when one size is the
    /// only option, and why does it say yours??"* The sheet asks no question
    /// and marks nothing "yours" when there is nothing to choose between.
    public var isSole: Bool {
        hasLoaded && variants.count == 1
    }

    public func select(_ variantID: UUID) {
        guard variants.contains(where: { $0.id == variantID }) else { return }
        selectedVariantID = variantID
    }

    /// The confirmed variant, or nil while nothing is picked. The sheet's
    /// confirm button is disabled exactly when this is nil.
    public var confirmed: Variant? {
        variants.first { $0.id == selectedVariantID }
    }

    /// Finder-style ordering on the row's own label: digit runs compare as
    /// numbers (1c < 2c < 10c, #98 < #100), everything else as text. Label-less
    /// rows sort last — "one size" under any named shade is never a real list.
    /// `nonisolated`: pure arithmetic, testable without a @MainActor test.
    nonisolated static func readsBefore(_ lhs: Variant, _ rhs: Variant) -> Bool {
        switch (lhs.pickLabel, rhs.pickLabel) {
        case (nil, _): false
        case (_, nil): true
        case let (left?, right?): left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}

extension Variant {
    /// The shade-strength-size line — "joy · 7.5ml", "10% · 30ml", "150ml".
    /// The client-side twin of the database's `variant_label()` (migration
    /// 0007): same field order, same separator, same trailing-zero trim, so
    /// a sheet row and a shelf row agree. The strength gap this used to
    /// state is closed — `Variant.strengthPct` decodes since the session-7
    /// opening (#147, GLO-56).
    public var pickLabel: String? {
        let strength = strengthPct.map { Variant.trimmed($0) + "%" }
        let size = sizeML.map { Variant.trimmed($0) + "ml" }
        let parts = [shadeCode, strength, size].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "32.0" reads as a decimal nobody printed on the box; `trim_scale` in
    /// SQL drops it and this is its Swift half.
    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(value)
    }
}

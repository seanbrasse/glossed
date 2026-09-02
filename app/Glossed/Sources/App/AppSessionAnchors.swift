import DataKit
import Foundation

// The anchor lookup, split from `AppSession.swift` for the 300-line ceiling
// when the phone's account path landed (Sept 2) — a mechanical move.

extension AppSession {
    /// The `is_anchor` categories, by id. Failure is empty, not fatal: a
    /// surface then treats every product as non-anchor and asks no shade
    /// question, which under-claims rather than invents.
    static func loadAnchorCategoryIDs(_ catalog: CatalogRepository) async -> Set<UUID> {
        guard let categories = try? await catalog.categories() else { return [] }
        return Set(categories.filter(\.isAnchor).map(\.id))
    }

    /// Every foundation variant the local catalog carries, keyed the way the
    /// picker names one. Failure is empty, not fatal: an unresolvable anchor
    /// makes the payoff say it has nothing to show, which is true, rather than
    /// taking the whole flow down.
    static func loadAnchorVariants(_ catalog: CatalogRepository) async -> [String: UUID] {
        guard let hits = try? await catalog.search("foundation", limit: 60) else { return [:] }
        var map: [String: UUID] = [:]
        for hit in hits where hit.categorySlug == "foundation" {
            guard let variants = try? await catalog.variants(productID: hit.id) else { continue }
            for variant in variants {
                guard let shade = variant.shadeCode else { continue }
                map[anchorKey(brand: hit.brandName, product: hit.name, shade: shade)] = variant.id
            }
        }
        return map
    }

    /// Lowercased and trimmed on both sides, because the picker's strings come
    /// from the kit and the catalog's come from an importer.
    static func anchorKey(brand: String, product: String, shade: String) -> String {
        [brand, product, shade]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "·")
    }

    /// Handed to `OnboardingFlowModel`, which calls it when a shade is picked.
    func resolveAnchorVariant(brand: String, product: String, shade: String) -> UUID? {
        anchorVariants[Self.anchorKey(brand: brand, product: product, shade: shade)]
    }
}

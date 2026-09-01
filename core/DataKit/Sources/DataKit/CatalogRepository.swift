import Foundation
import Supabase

/// Reads the shared catalog and creates personal-scope products.
///
/// Personal scope is enforced in the database (RLS), not here — this type just
/// makes the correct call easy to make. A personal product is invisible to
/// every other user and never aggregates until it is promoted.
public struct CatalogRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    /// The shortest query the catalog will answer. Public because the search
    /// rung enforces the same floor before it records a failed search, and a
    /// floor that drifts up here alone writes false demand into the fill queue
    /// (GLO-55).
    public static let minimumQueryLength = 2

    /// Type-ahead across the catalog. Returns canonical products plus the
    /// caller's own personal ones — RLS decides which, so no scope filter here.
    public func search(_ query: String, limit: Int = 20) async throws(GlossedError) -> [CatalogHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= CatalogRepository.minimumQueryLength else { return [] }
        return try await run {
            try await client.supabase
                .rpc("search_catalog", params: ["q": trimmed])
                .limit(limit)
                .execute()
                .value
        }
    }

    /// Exact GTIN lookup — the barcode rung, where dedupe is exact rather than
    /// probabilistic.
    ///
    /// Matches on `gtin14`, the padded generated column, so a 12-digit UPC-A
    /// scan finds the 13-digit EAN-13 row for the same product (GLO-58). The
    /// padding happens on both sides — client here, generated column there —
    /// because normalizing one side of an exact match makes every scan miss.
    public func variant(gtin: String) async throws(GlossedError) -> Variant? {
        guard let padded = CatalogRepository.gtin14(gtin) else { return nil }
        let hits: [Variant] = try await run {
            try await client.supabase
                .from("variants")
                .select()
                .eq("gtin14", value: padded)
                .limit(1)
                .execute()
                .value
        }
        return hits.first
    }

    /// GS1's canonical form: digits only, 8–14 of them, left-padded to 14.
    /// Anything else is not a GTIN and returns nil rather than a padded typo.
    static func gtin14(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count == raw.count, (8 ... 14).contains(digits.count) else { return nil }
        return String(repeating: "0", count: 14 - digits.count) + digits
    }

    /// Brands for the create rung's typeahead. The draft requires a `brandID`
    /// and a search hit carries only a brand *name*, so without this the rung
    /// cannot be built: free-text brands are how a catalog acquires "Rare
    /// Beauty", "rare beauty" and "RareBeauty" as three rows to merge by hand
    /// forever (GLO-60).
    public func brands(matching query: String, limit: Int = 10) async throws(GlossedError) -> [Brand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= CatalogRepository.minimumQueryLength else { return [] }
        return try await run {
            try await client.supabase
                .from("brands")
                .select("id,name")
                .ilike("normalized_name", pattern: "%\(trimmed.lowercased())%")
                .order("normalized_name")
                .limit(limit)
                .execute()
                .value
        }
    }

    /// The dedupe middle band's own question (0018): candidates near the
    /// query — or near a missed scan's GS1 prefix — each carrying the reason
    /// it qualified. Distinct from `search_catalog`: that asks "what matches",
    /// this asks "what might she be confusing this with".
    public func nearMatches(
        _ query: String,
        domain: Domain? = nil,
        gtin: String? = nil
    ) async throws(GlossedError) -> [NearMatch] {
        try await run {
            try await client.supabase
                .rpc("near_matches", params: NearMatchParams(query: query, pDomain: domain?.rawValue, pGtin: gtin))
                .execute()
                .value
        }
    }

    public func variants(productID: UUID) async throws(GlossedError) -> [Variant] {
        try await run {
            try await client.supabase
                .from("variants")
                .select()
                .eq("product_id", value: productID.uuidString)
                .order("shade_code")
                .execute()
                .value
        }
    }

    /// TOP-LEVEL categories only — the rankable set every picker, ladder and
    /// leaderboard means by "category". The 0057 tree put ~200 LEAF product
    /// types under these as children; without this predicate all five
    /// category consumers would flood with them the moment the tree landed.
    public func categories(domain: Domain? = nil) async throws(GlossedError) -> [Category] {
        try await run {
            let table = client.supabase.from("categories").select()
                .is("parent_id", value: nil)
            let filtered = domain.map { table.eq("domain", value: $0.rawValue) } ?? table
            return try await filtered.order("slug").execute().value
        }
    }

    /// A top-level category's leaf product types (0057) — the fine-grained
    /// vocabulary ("aha", "lip oil", "bond builder") for classification and
    /// pickers that want the second level. Empty for a leafless category.
    public func subtypes(of categoryID: UUID) async throws(GlossedError) -> [Category] {
        try await run {
            try await client.supabase.from("categories").select()
                .eq("parent_id", value: categoryID.uuidString)
                .order("label")
                .execute()
                .value
        }
    }

    /// The experience-chip vocabulary a user picks from. Reference data, so it
    /// sits here beside `categories(domain:)` rather than on the shelf: the
    /// list is the same for everyone, and only the *applying* is personal.
    ///
    /// A chip with a null `category_id` applies to its whole domain; a non-null
    /// one narrows to a single category. Passing `categoryID` returns both —
    /// the domain-wide chips AND that category's own — because a foundation
    /// should offer "broke me out" as well as "oxidized", and filtering to an
    /// exact category match would silently drop the general half.
    public func chipVocabulary(
        domain: Domain? = nil,
        categoryID: UUID? = nil
    ) async throws(GlossedError) -> [ExperienceChip] {
        try await run {
            let table = client.supabase.from("experience_chips").select()
            let byDomain = domain.map { table.eq("domain", value: $0.rawValue) } ?? table
            let scoped = categoryID.map {
                byDomain.or("category_id.is.null,category_id.eq.\($0.uuidString)")
            } ?? byDomain
            return try await scoped.order("label").execute().value
        }
    }

    /// Every empty search names exactly which product is missing, weighted by
    /// demand — the highest-value catalog signal we will ever have (tech/01 §4).
    public func recordFailedSearch(_ query: String, domain: Domain?) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= CatalogRepository.minimumQueryLength else { return }
        _ = try? await client.supabase
            .rpc("record_failed_search", params: FailedSearchParams(query: trimmed, domain: domain?.rawValue))
            .execute()
    }

    /// Last rung of the submission ladder. Always personal scope: nothing a
    /// user creates can reach the shared catalog without promotion.
    ///
    /// One RPC rather than two inserts, because `user_items.variant_id` is not
    /// null and nothing else creates the variant — the old two-call shape
    /// produced a product that could not be logged, and failed a step *after*
    /// the success badge on a row that now existed and was invisible.
    public func createPersonalProduct(
        _ draft: PersonalProductDraft
    ) async throws(GlossedError) -> CreatedProduct {
        _ = try await client.requireUserID()
        let created: [CreatedProduct] = try await run {
            try await client.supabase
                .rpc("create_personal_product", params: draft.params())
                .execute()
                .value
        }
        guard let first = created.first else {
            throw GlossedError(
                .notFound,
                userMessage: "we couldn't add that. try again.",
                debugDetail: "create_personal_product returned no row"
            )
        }
        return first
    }

    private struct NearMatchParams: Encodable {
        let query: String
        let pDomain: String?
        let pGtin: String?

        enum CodingKeys: String, CodingKey {
            case query = "q"
            case pDomain = "p_domain"
            case pGtin = "p_gtin"
        }
    }

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}

/// Four fields, a category, and the code that was scanned before the miss.
public struct PersonalProductDraft: Sendable {
    public let brandID: UUID
    public let categoryID: UUID
    public let domain: Domain
    public let name: String
    /// The variant as the user wrote it — "joy · 2.5ml mini". Free text on
    /// purpose: for a personal-scope product the variant is whatever its owner
    /// calls it. The server lands it in `shade_code`, which is what
    /// `variant_label()` reads, so it renders everywhere with no view changes.
    public let variant: String?
    /// The barcode the scan rung failed to find. Kept because it is the
    /// strongest identifier a user will ever hand us — it is what later lets
    /// this product be matched against the feed and promoted (domain.md §3.1).
    public let scannedGTIN: String?

    public init(
        brandID: UUID,
        categoryID: UUID,
        domain: Domain,
        name: String,
        variant: String? = nil,
        scannedGTIN: String? = nil
    ) {
        self.brandID = brandID
        self.categoryID = categoryID
        self.domain = domain
        self.name = name
        self.variant = variant
        self.scannedGTIN = scannedGTIN
    }

    // Normalization used to live here as `normalize(_:)`. It disagreed with the
    // seed — it wrote "Pro Filt'r" as `pro filt r` where the catalog writes
    // `pro filtr` — and two implementations of one dedupe rule is how a catalog
    // acquires two rows for one product. The rule is now `normalize_name()` in
    // the database and this side does not compute it.

    func params() -> CreateProductParams {
        CreateProductParams(
            brandID: brandID.uuidString,
            categoryID: categoryID.uuidString,
            domain: domain.rawValue,
            name: name,
            gtin: scannedGTIN,
            variant: variant
        )
    }
}

struct CreateProductParams: Encodable, Sendable {
    let brandID: String
    let categoryID: String
    let domain: String
    let name: String
    let gtin: String?
    let variant: String?

    enum CodingKeys: String, CodingKey {
        case brandID = "p_brand_id"
        case categoryID = "p_category_id"
        case domain = "p_domain"
        case name = "p_name"
        case gtin = "p_gtin"
        case variant = "p_variant"
    }
}

struct FailedSearchParams: Encodable, Sendable {
    let query: String
    let domain: String?

    enum CodingKeys: String, CodingKey {
        case query = "p_query"
        case domain = "p_domain"
    }
}

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
    public func variant(gtin: String) async throws(GlossedError) -> Variant? {
        let hits: [Variant] = try await run {
            try await client.supabase
                .from("variants")
                .select()
                .eq("gtin", value: gtin)
                .limit(1)
                .execute()
                .value
        }
        return hits.first
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

    public func categories(domain: Domain? = nil) async throws(GlossedError) -> [Category] {
        try await run {
            let table = client.supabase.from("categories").select()
            let filtered = domain.map { table.eq("domain", value: $0.rawValue) } ?? table
            return try await filtered.order("slug").execute().value
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
    /// The barcode the scan rung failed to find. Kept because it is the
    /// strongest identifier a user will ever hand us — it is what later lets
    /// this product be matched against the feed and promoted (domain.md §3.1).
    public let scannedGTIN: String?

    public init(
        brandID: UUID,
        categoryID: UUID,
        domain: Domain,
        name: String,
        scannedGTIN: String? = nil
    ) {
        self.brandID = brandID
        self.categoryID = categoryID
        self.domain = domain
        self.name = name
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
            gtin: scannedGTIN
        )
    }
}

struct CreateProductParams: Encodable, Sendable {
    let brandID: String
    let categoryID: String
    let domain: String
    let name: String
    let gtin: String?

    enum CodingKeys: String, CodingKey {
        case brandID = "p_brand_id"
        case categoryID = "p_category_id"
        case domain = "p_domain"
        case name = "p_name"
        case gtin = "p_gtin"
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

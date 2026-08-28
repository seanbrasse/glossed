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

    /// Type-ahead across the catalog. Returns canonical products plus the
    /// caller's own personal ones — RLS decides which, so no scope filter here.
    public func search(_ query: String, limit: Int = 20) async throws(GlossedError) -> [CatalogHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
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
        guard trimmed.count >= 2 else { return }
        _ = try? await client.supabase
            .rpc("record_failed_search", params: FailedSearchParams(query: trimmed, domain: domain?.rawValue))
            .execute()
    }

    /// Last rung of the submission ladder. Always personal scope: nothing a
    /// user creates can reach the shared catalog without promotion.
    public func createPersonalProduct(_ draft: PersonalProductDraft) async throws(GlossedError) -> Product {
        let userID = try await client.requireUserID()
        return try await run {
            try await client.supabase
                .from("products")
                .insert(draft.row(createdBy: userID))
                .select()
                .single()
                .execute()
                .value
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

/// Four fields and a category — the whole create rung.
public struct PersonalProductDraft: Sendable {
    public let brandID: UUID
    public let categoryID: UUID
    public let domain: Domain
    public let name: String

    public init(brandID: UUID, categoryID: UUID, domain: Domain, name: String) {
        self.brandID = brandID
        self.categoryID = categoryID
        self.domain = domain
        self.name = name
    }

    /// Normalization mirrors the catalog's own rule so dedupe can compare like
    /// with like: lowercased, punctuation stripped, whitespace collapsed.
    public static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let stripped = lowered.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(stripped).split(separator: " ").joined(separator: " ")
    }

    func row(createdBy: UUID) -> PersonalProductRow {
        PersonalProductRow(
            brandID: brandID.uuidString,
            categoryID: categoryID.uuidString,
            domain: domain.rawValue,
            name: name,
            normalizedName: PersonalProductDraft.normalize(name),
            scope: CatalogScope.personal.rawValue,
            createdBy: createdBy.uuidString
        )
    }
}

struct PersonalProductRow: Encodable, Sendable {
    let brandID: String
    let categoryID: String
    let domain: String
    let name: String
    let normalizedName: String
    let scope: String
    let createdBy: String

    enum CodingKeys: String, CodingKey {
        case domain, name, scope
        case brandID = "brand_id"
        case categoryID = "category_id"
        case normalizedName = "normalized_name"
        case createdBy = "created_by"
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

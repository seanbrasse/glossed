import DataKit
import Foundation

/// GLO-93's client half: a scanned code the catalog cannot name gets one
/// chance at the `barcode_fill` Edge Function before the ladder falls
/// through to near matches.
///
/// The seam lives here rather than in DataKit for the usual reason — the
/// frozen core carries opaque bytes across the boundary
/// (`invokeEdgeFunctionForData`) and the feature that knows the function's
/// shape owns the decoding.
public protocol BarcodeFilling: Sendable {
    /// The function's suggestion for a code, or nil when it has nothing.
    /// **Never throws**: a fill is an optional courtesy on a path that
    /// already failed, so an unreachable function, an exhausted budget or a
    /// missing key must leave the ladder exactly as it found it.
    func suggestion(gtin: String) async -> BarcodeFillSuggestion?
}

/// What the create rung can be pre-filled with. Mirrors the function's
/// response (`supabase/functions/barcode_fill/lookup.ts`) — and deliberately
/// carries no category: the upstream's category is domain-coarse
/// ("skincare", never "serum"), so the human still answers that question.
public struct BarcodeFillSuggestion: Codable, Sendable, Equatable {
    public let found: Bool
    public let brand: String?
    public let name: String?
    /// Our `domain_enum` as a string, or nil when the upstream's category
    /// maps to nothing — an unpicked domain beats a wrong one.
    public let domain: String?
    public let inci: String?

    public init(found: Bool, brand: String?, name: String?, domain: String?, inci: String?) {
        self.found = found
        self.brand = brand
        self.name = name
        self.domain = domain
        self.inci = inci
    }
}

/// The live conformance: JSON out through the frozen core, JSON back.
public struct BarcodeFillService: BarcodeFilling {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    public func suggestion(gtin: String) async -> BarcodeFillSuggestion? {
        guard let body = try? JSONEncoder().encode(["gtin": gtin]) else { return nil }
        guard let data = try? await client.invokeEdgeFunctionForData(
            "barcode_fill", jsonBody: body
        ) else {
            // Swallowed on purpose (see `BarcodeFilling`): the scan already
            // missed, and a failed courtesy must not become a second failure
            // the user has to read.
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(BarcodeFillSuggestion.self, from: data),
              decoded.found,
              decoded.brand?.isEmpty == false,
              decoded.name?.isEmpty == false
        else { return nil }
        return decoded
    }
}

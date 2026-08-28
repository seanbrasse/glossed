import DataKit
import Foundation

/// What the barcode rung needs from the catalog. DataKit is frozen, so the
/// conformance lives here.
public protocol VariantLookup: Sendable {
    func variant(gtin: String) async throws(GlossedError) -> Variant?
}

extension CatalogRepository: VariantLookup {}

/// Rung 2: a scanned code, resolved against the catalog.
///
/// The path the spec pushes as the common one (tech/01 §6), and the only rung
/// that identifies a *variant* rather than a product — a GTIN is one shade in
/// one size, which is why dedupe here is exact rather than probabilistic.
public struct BarcodeRung: Sendable {
    /// What a scan turned out to be. Three outcomes, not two: a code we cannot
    /// read is not the same as a product we do not stock.
    public enum Outcome: Equatable, Sendable {
        /// Found it. A variant id, so the ladder can resolve here — unlike the
        /// search rung, which only ever lands on a product.
        case matched(Variant)
        /// A well-formed code the catalog has never seen. Real demand.
        case unknownCode(String)
        /// The digits do not check out: a misread, a damaged label, or a code
        /// that is not a product code at all. The answer is to scan again.
        /// Recording it as demand would fill the queue with noise nobody can
        /// act on, and that queue drives what we go and add.
        case misread
    }

    private let catalog: any VariantLookup

    public init(catalog: any VariantLookup) {
        self.catalog = catalog
    }

    public func resolve(scanned raw: String) async throws(GlossedError) -> Outcome {
        guard let gtin = GTIN.normalize(raw) else { return .misread }
        if let variant = try await catalog.variant(gtin: gtin) {
            return .matched(variant)
        }
        return .unknownCode(gtin)
    }
}

/// What counts as a product code, and what a scanner actually hands us.
public enum GTIN {
    /// The four GS1 lengths. A payload of any other length is not a GTIN — most
    /// often a QR code on the packaging pointing at a marketing site.
    public static let validLengths: Set<Int> = [8, 12, 13, 14]

    /// The scanned code as a string worth looking up, or nil if it is not a
    /// product code at all.
    ///
    /// Deliberately *not* zero-padded to GTIN-14. Padding is the correct
    /// canonical form, but `variants.gtin` stores whatever the feed supplied —
    /// 13 digits today — and the lookup is an exact match, so padding one side
    /// only would turn every scan into a miss. Normalizing both sides is a
    /// schema change; GLO-58 has it.
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy(\.isNumber),
              validLengths.contains(trimmed.count),
              isCheckDigitValid(trimmed)
        else { return nil }
        return trimmed
    }

    /// The GS1 mod-10 check digit.
    ///
    /// A single misread digit fails this, which is exactly the difference
    /// between "we do not stock it" and "hold the phone steadier". Every
    /// physical barcode carries a valid one, so a failure is about the read,
    /// never about the product.
    public static func isCheckDigitValid(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, values.count >= 2, let check = values.last else {
            return false
        }
        // Weights alternate 3,1,3,1… leftward from the digit before the check.
        let sum = values.dropLast().reversed().enumerated().reduce(0) { total, pair in
            total + pair.element * (pair.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }
}

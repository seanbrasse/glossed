import DataKit
import Foundation

/// What the create rung needs from the catalog, and nothing more — the same
/// shape as `CatalogSearching`, for the same reason: DataKit is frozen, so the
/// conformance lives here, and a test double stands in for exactly three calls.
public protocol ProductCreating: Sendable {
    func brands(matching query: String, limit: Int) async throws(GlossedError) -> [Brand]
    func categories(domain: Domain?) async throws(GlossedError) -> [DataKit.Category]
    func createPersonalProduct(_ draft: PersonalProductDraft) async throws(GlossedError) -> CreatedProduct
}

extension CatalogRepository: ProductCreating {}

/// The one shelf call the rung's button promises: "create + add to shelf".
public protocol ItemLogging: Sendable {
    func log(_ draft: LogDraft) async throws(GlossedError) -> UserItem
}

extension ShelfRepository: ItemLogging {}

/// Rung 4: create the product in personal scope, then put it on the shelf.
///
/// Two writes, because they are two systems — `create_personal_product` is one
/// transaction for product + variant, and the shelf log is the user's own row.
/// The seam between them is exactly where GLO-15 warned the quiet failure
/// lives: a create that succeeds and a log that fails leaves a product that
/// exists and is invisible. So the outcome names that state instead of
/// swallowing it, and a resumed call skips the create rather than making a
/// duplicate.
public struct CreateRung: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Both writes landed; the ladder can resolve. The shelf row rides
        /// along because the fit prompt (GLO-16) is keyed by it — a log that
        /// discards its row forces whoever asks "did it fit?" to re-query for
        /// a fact this call just held.
        case shelved(CreatedProduct, UserItem)
        /// The product exists, the shelf row does not. The caller keeps the
        /// product and retries the log alone — never the create.
        case createdButNotShelved(CreatedProduct, GlossedError)
    }

    private let catalog: any ProductCreating
    private let shelf: any ItemLogging

    public init(catalog: any ProductCreating, shelf: any ItemLogging) {
        self.catalog = catalog
        self.shelf = shelf
    }

    /// Creates (unless `resuming` carries an earlier create) and logs.
    ///
    /// - Parameter clientID: the shelf log's idempotency key. The caller holds
    ///   one per form submission so a retry upserts the same row rather than
    ///   logging the product twice.
    /// - Throws: only when the *create* fails — nothing exists yet and the
    ///   whole thing is safe to retry. A log failure is an `Outcome`, because
    ///   at that point something exists that must not be re-created.
    public func createAndLog(
        _ draft: PersonalProductDraft,
        resuming earlier: CreatedProduct? = nil,
        clientID: UUID
    ) async throws(GlossedError) -> Outcome {
        let created: CreatedProduct = if let earlier {
            earlier
        } else {
            try await catalog.createPersonalProduct(draft)
        }
        do {
            let item = try await shelf.log(LogDraft(variantID: created.variantID, clientID: clientID))
            return .shelved(created, item)
        } catch {
            return .createdButNotShelved(created, error)
        }
    }
}

import Foundation

/// One saved product — a shelf row whose status is `want_to_try`, shaped
/// for the default collection's card and its detail (Sean, Aug 31 batch 2:
/// "there should be a default want to try collection").
public struct WantToTryEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let brand: String
    public let name: String
    /// The CATALOG image — public storage, composed by the app from
    /// `imageBase` (GLO-74: features never guess at it). Nil renders the
    /// tinted cell with no cutout, which is less, never wrong.
    public let imageURL: URL?

    public init(id: UUID, brand: String, name: String, imageURL: URL?) {
        self.id = id
        self.brand = brand
        self.name = name
        self.imageURL = imageURL
    }
}

/// The want-to-try read, as a closure the app fills. VIRTUAL by design:
/// the "default collection" is a rendering of `shelf(status: want_to_try)`,
/// not a `collections` row — nothing to keep in sync, nothing a user can
/// delete out from under themselves, and marking a product want-to-try IS
/// putting it here.
public struct WantToTryStore: Sendable {
    public var entries: @Sendable () async throws -> [WantToTryEntry]

    public init(entries: @escaping @Sendable () async throws -> [WantToTryEntry]) {
        self.entries = entries
    }
}

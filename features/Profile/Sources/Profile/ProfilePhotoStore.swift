import Foundation

/// The pfp's two moves, as closures the app fills (GLO-272 — "an edit icon
/// on the corner of the pfp"). The feature knows WHERE the avatar renders
/// and when to refresh it; the app knows how to prepare, presign, PUT and
/// store a key — and neither learns the other's half.
///
/// `currentURL` answers nil for "no photo yet" AND for "could not sign" —
/// both render the seeded initial, which is never wrong, only less. A pfp
/// is chrome; chrome must not take the header down.
public struct ProfilePhotoStore: Sendable {
    public var currentURL: @Sendable () async -> URL?
    /// The whole pipeline behind one verb: prepare (strip, re-encode),
    /// presign, PUT, store the key. Throws with a user-facing message —
    /// the control shows it in place.
    public var upload: @Sendable (Data) async throws -> Void

    public init(
        currentURL: @escaping @Sendable () async -> URL?,
        upload: @escaping @Sendable (Data) async throws -> Void
    ) {
        self.currentURL = currentURL
        self.upload = upload
    }
}

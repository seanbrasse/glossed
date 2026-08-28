import Foundation

/// The one error type crossing the DataKit boundary. Every error carries a
/// machine `code` for logs and a `userMessage` safe to render — internal
/// details never reach the user (tech/00 §7.1).
public struct GlossedError: Error, Equatable, Sendable {
    public enum Code: String, Sendable {
        case configMissing = "config_missing"
        case configMalformed = "config_malformed"
        case notAuthenticated = "not_authenticated"
        case underAgeMinimum = "under_age_minimum"
        case invalidInput = "invalid_input"
        case notFound = "not_found"
        case permissionDenied = "permission_denied"
        case conflict
        case rateLimited = "rate_limited"
        case offline
        case server
        case unknown
    }

    public let code: Code
    public let userMessage: String
    /// Short reference the UI shows so a report maps 1:1 to a logged event.
    public let supportReference: String
    /// Developer-facing detail. Logged, never rendered.
    public let debugDetail: String?

    public init(_ code: Code, userMessage: String, debugDetail: String? = nil, supportReference: String? = nil) {
        self.code = code
        self.userMessage = userMessage
        self.debugDetail = debugDetail
        self.supportReference = supportReference ?? GlossedError.makeReference()
    }

    public static func == (lhs: GlossedError, rhs: GlossedError) -> Bool {
        lhs.code == rhs.code && lhs.userMessage == rhs.userMessage
    }

    /// Six uppercase base-32-ish characters — short enough to read aloud.
    static func makeReference() -> String {
        String((0 ..< 6).map { _ in "ABCDEFGHJKMNPQRSTUVWXYZ23456789".randomElement() ?? "X" })
    }
}

public extension GlossedError {
    /// Maps a transport/database failure to the typed error. This is the single
    /// boundary — services throw `GlossedError`, never raw client errors.
    static func from(_ error: Error) -> GlossedError {
        if let already = error as? GlossedError {
            return already
        }

        let text = String(describing: error).lowercased()
        let detail = String(describing: error)

        // Postgres/PostgREST signals we care about, in specificity order.
        if text.contains("row-level security") || text.contains("42501") {
            return GlossedError(.permissionDenied, userMessage: "that isn't yours to change.", debugDetail: detail)
        }
        if text.contains("duplicate key") || text.contains("23505") {
            return GlossedError(.conflict, userMessage: "that's already on your shelf.", debugDetail: detail)
        }
        if text.contains("jwt") || text.contains("401") || text.contains("not authenticated") {
            return GlossedError(.notAuthenticated, userMessage: "sign in to keep going.", debugDetail: detail)
        }
        if text.contains("429") || text.contains("rate limit") {
            return GlossedError(.rateLimited, userMessage: "too many tries — give it a minute.", debugDetail: detail)
        }
        if isOffline(error) {
            return GlossedError(.offline, userMessage: "no connection — try again in a sec.", debugDetail: detail)
        }
        if text.contains("500") || text.contains("502") || text.contains("503") {
            return GlossedError(.server, userMessage: "something broke on our side.", debugDetail: detail)
        }
        return GlossedError(.unknown, userMessage: "something went wrong.", debugDetail: detail)
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(urlError.code)
    }
}

import Foundation
import Supabase

/// Env-validated configuration. The app refuses to boot on a missing or
/// malformed value — no silent `nil` (handbook §5.1).
public struct GlossedConfig: Sendable {
    public let supabaseURL: URL
    public let publishableKey: String

    public init(supabaseURL: URL, publishableKey: String) {
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
    }

    /// Builds config from an environment dictionary, validating as it goes.
    public static func validated(from environment: [String: String]) throws(GlossedError) -> GlossedConfig {
        guard let rawURL = environment["SUPABASE_URL"], !rawURL.isEmpty else {
            throw GlossedError(.configMissing, userMessage: setupMessage, debugDetail: "SUPABASE_URL absent")
        }
        guard let key = environment["SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty else {
            throw GlossedError(
                .configMissing,
                userMessage: setupMessage,
                debugDetail: "SUPABASE_PUBLISHABLE_KEY absent"
            )
        }
        guard let url = URL(string: rawURL), let scheme = url.scheme, scheme.hasPrefix("http"), url.host != nil else {
            throw GlossedError(
                .configMalformed,
                userMessage: setupMessage,
                debugDetail: "SUPABASE_URL not a http(s) URL"
            )
        }
        // A secret key in the app bundle would be a credential leak, not a typo.
        guard !key.hasPrefix("sb_secret_"), !key.contains("service_role") else {
            throw GlossedError(
                .configMalformed,
                userMessage: setupMessage,
                debugDetail: "secret key supplied where the publishable key belongs"
            )
        }
        return GlossedConfig(supabaseURL: url, publishableKey: key)
    }

    private static let setupMessage = "the app isn't set up correctly."
}

/// The frozen core's single entry point. Wraps the platform client and never
/// exports it: every query in the app goes through DataKit's repositories, so
/// there is exactly one place session handling can be got wrong.
public actor GlossedClient {
    /// Nonisolated because `SupabaseClient` is itself Sendable — the protection
    /// here is access level, not isolation: nothing outside DataKit can see it.
    private nonisolated let client: SupabaseClient

    public init(config: GlossedConfig) {
        client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.publishableKey)
    }

    /// Internal-only access for repositories inside this module.
    nonisolated var supabase: SupabaseClient {
        client
    }

    /// The signed-in user's id, or a typed error — repositories call this
    /// instead of reaching for the session themselves.
    public func requireUserID() async throws(GlossedError) -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            throw GlossedError(
                .notAuthenticated,
                userMessage: "sign in to keep going.",
                debugDetail: String(describing: error)
            )
        }
    }

    public func currentUserID() async -> UUID? {
        try? await client.auth.session.user.id
    }

    /// Email/password sign-in. The path GLO-23's auth flows will use, and the
    /// one the DEBUG picker uses today against the local seed — which is why
    /// it lands ahead of the flows: nothing can drive a live read without a
    /// session, and every screen was fixture-fed until something could sign in.
    public func signIn(email: String, password: String) async throws(GlossedError) {
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            throw GlossedError.from(error)
        }
    }

    public func signOut() async throws(GlossedError) {
        do {
            try await client.auth.signOut()
        } catch {
            throw GlossedError.from(error)
        }
    }

    /// Hands a JSON body to a named Edge Function with the caller's auth
    /// attached — the platform client stays unexported (session-7 opening,
    /// GLO-80's transport). No `requireUserID()` on purpose: `track_ingest`
    /// accepts the anon key too, which is how pre-signup onboarding events
    /// exist at all (tech/06 §2, `anon_id`). DataKit never sees event
    /// shapes; the body is opaque bytes to it.
    public func invokeEdgeFunction(_ name: String, jsonBody: Data) async throws(GlossedError) {
        do {
            try await client.functions.invoke(
                name,
                options: FunctionInvokeOptions(
                    headers: ["Content-Type": "application/json"],
                    body: jsonBody
                )
            )
        } catch {
            throw GlossedError.from(error)
        }
    }

    /// Same transport as `invokeEdgeFunction`, but hands back the response body
    /// as raw bytes — for functions whose ANSWER is the point rather than the
    /// side effect (GLO-93's catalog enrichment: you call it to get a product
    /// back, not to record that you asked).
    ///
    /// `Data` and not a decoded type on purpose. DataKit stays ignorant of
    /// payload shapes — the body goes out opaque and comes back opaque, and the
    /// feature that knows what the function returns owns the decoding. The SDK
    /// offers a `Decodable` overload; taking it would drag every upstream
    /// response shape through the frozen core and make each new function a core
    /// opening.
    ///
    /// A distinct NAME rather than an overload on the return type: with both
    /// spelled `invokeEdgeFunction`, a call whose result is discarded resolves
    /// by inference, and the compiler would quietly pick for you at every call
    /// site. Non-2xx and relay failures throw, mapped like every other call.
    public func invokeEdgeFunctionForData(_ name: String, jsonBody: Data) async throws(GlossedError) -> Data {
        do {
            return try await client.functions.invoke(
                name,
                options: FunctionInvokeOptions(
                    headers: ["Content-Type": "application/json"],
                    body: jsonBody
                )
            ) { data, _ in data }
        } catch {
            throw GlossedError.from(error)
        }
    }

    /// Auth state for the app shell to observe: emits on sign-in, sign-out,
    /// and token refresh.
    public nonisolated func authStates() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    continuation.yield(AuthState(event: event, userID: session?.user.id))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// What the shell needs to know: who is signed in, if anyone.
public struct AuthState: Sendable, Equatable {
    public let isSignedIn: Bool
    public let userID: UUID?

    init(event: AuthChangeEvent, userID: UUID?) {
        self.userID = userID
        switch event {
        case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
            isSignedIn = userID != nil
        case .signedOut, .userDeleted:
            isSignedIn = false
        default:
            isSignedIn = userID != nil
        }
    }
}

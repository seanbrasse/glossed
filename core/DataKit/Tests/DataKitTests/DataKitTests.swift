import Foundation
import Testing
@testable import DataKit

// MARK: - Config validation (the app must refuse to boot on bad env)

@Test func validConfigParses() throws {
    let config = try GlossedConfig.validated(from: [
        "SUPABASE_URL": "https://nsnniahnfmagoejwrgvc.supabase.co",
        "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_abc123"
    ])
    #expect(config.supabaseURL.host == "nsnniahnfmagoejwrgvc.supabase.co")
}

@Test func missingValuesAreRejected() {
    #expect(throws: GlossedError.self) {
        try GlossedConfig.validated(from: ["SUPABASE_PUBLISHABLE_KEY": "sb_publishable_abc"])
    }
    #expect(throws: GlossedError.self) {
        try GlossedConfig.validated(from: ["SUPABASE_URL": "https://x.supabase.co"])
    }
    #expect(throws: GlossedError.self) {
        try GlossedConfig.validated(from: ["SUPABASE_URL": "", "SUPABASE_PUBLISHABLE_KEY": ""])
    }
}

@Test func malformedURLIsRejected() {
    #expect(throws: GlossedError.self) {
        try GlossedConfig.validated(from: [
            "SUPABASE_URL": "not-a-url",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_abc"
        ])
    }
}

@Test func secretKeyInTheAppBundleIsRejected() {
    // A secret key shipped to clients is a credential leak, so it fails loudly
    // at boot rather than working fine and quietly over-permissioning the app.
    for leaked in ["sb_secret_abc123", "eyJ...service_role...xyz"] {
        #expect(throws: GlossedError.self) {
            try GlossedConfig.validated(from: [
                "SUPABASE_URL": "https://x.supabase.co",
                "SUPABASE_PUBLISHABLE_KEY": leaked
            ])
        }
    }
}

// MARK: - Error mapping (one boundary, user-safe messages)

@Test func rlsDenialMapsToPermissionDenied() {
    let raw = NSError(
        domain: "PostgREST", code: 42501,
        userInfo: [NSLocalizedDescriptionKey: "new row violates row-level security policy for table \"user_items\""]
    )
    #expect(GlossedError.from(raw).code == .permissionDenied)
}

@Test func duplicateKeyMapsToConflict() {
    let raw = NSError(
        domain: "PostgREST", code: 23505,
        userInfo: [NSLocalizedDescriptionKey: "duplicate key value violates unique constraint"]
    )
    #expect(GlossedError.from(raw).code == .conflict)
}

@Test func offlineMapsToOffline() {
    #expect(GlossedError.from(URLError(.notConnectedToInternet)).code == .offline)
}

@Test func unknownErrorsStayUserSafe() {
    let raw = NSError(
        domain: "Internal", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "connection string postgres://user:hunter2@db"]
    )
    let mapped = GlossedError.from(raw)
    #expect(mapped.code == .unknown)
    // internal detail is kept for logs but must never surface in the message
    #expect(!mapped.userMessage.contains("hunter2"))
    #expect(mapped.debugDetail?.contains("hunter2") == true)
}

@Test func mappingIsIdempotent() {
    let original = GlossedError(.notFound, userMessage: "we don't have that one yet.")
    #expect(GlossedError.from(original).supportReference == original.supportReference)
}

@Test func supportReferenceIsShortAndUnambiguous() {
    let reference = GlossedError(.unknown, userMessage: "x").supportReference
    #expect(reference.count == 6)
    // no characters that get misread aloud (0/O, 1/I/L)
    #expect(reference.allSatisfy { "ABCDEFGHJKMNPQRSTUVWXYZ23456789".contains($0) })
}

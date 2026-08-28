import DataKit
import Foundation
import Testing
@testable import AddLadder

/// DataKit is frozen and `CatalogHit`'s memberwise init is internal to it, so
/// hits are built the way the app really gets them — decoded off the wire.
/// A drift in the RPC's column names fails here rather than in production.
/// Shared with the model tests: one shape of fake hit, one place to fix it.
func hit(name: String, scope: String = "canonical") throws -> CatalogHit {
    let json = """
    {"id":"\(UUID().uuidString)","name":"\(name)","brand_name":"Glow Recipe",
     "category_slug":"serum","domain":"skincare","scope":"\(scope)"}
    """
    return try JSONDecoder().decode(CatalogHit.self, from: Data(json.utf8))
}

actor FakeCatalog: CatalogSearching {
    private let hits: [CatalogHit]
    private let failure: GlossedError?
    private(set) var searched: [String] = []
    private(set) var recordedMisses: [String] = []

    init(hits: [CatalogHit] = [], failure: GlossedError? = nil) {
        self.hits = hits
        self.failure = failure
    }

    func search(_ query: String, limit _: Int) async throws(GlossedError) -> [CatalogHit] {
        searched.append(query)
        if let failure {
            throw failure
        }
        return hits
    }

    func recordFailedSearch(_ query: String, domain _: Domain?) async {
        recordedMisses.append(query)
    }
}

@Test func aSearchThatFindsSomethingReturnsItAndRecordsNothing() async throws {
    let catalog = try FakeCatalog(hits: [hit(name: "Watermelon Glow")])
    let result = try await SearchRung(catalog: catalog).typeahead("watermelon")
    #expect(result.hits.count == 1)
    #expect(result.hits[0].name == "Watermelon Glow")
    #expect(result.isMiss == false)
    #expect(await catalog.recordedMisses.isEmpty)
}

@Test func anEmptySearchIsRecordedAsDemand() async throws {
    // tech/01 §4: the miss is the signal. Losing it is the expensive bug here,
    // not returning zero rows. `isMiss` claims only what this layer can see —
    // a real query came back empty and we asked for it to be recorded — since
    // recordFailedSearch swallows its own transport errors by design.
    let catalog = FakeCatalog()
    let result = try await SearchRung(catalog: catalog).typeahead("  laneige  lip  ", domain: .skincare)
    #expect(result.isEmpty)
    #expect(result.isMiss)
    #expect(await catalog.recordedMisses == ["laneige lip"])
}

@Test func stillTypingIsNotAMiss() async throws {
    let catalog = FakeCatalog()
    for tooShort in ["", " ", "l", " l "] {
        let result = try await SearchRung(catalog: catalog).typeahead(tooShort)
        #expect(result.isEmpty)
        #expect(result.isMiss == false)
    }
    #expect(await catalog.searched.isEmpty)
    #expect(await catalog.recordedMisses.isEmpty)
}

@Test func anUnauthenticatedSearchFailsAsItselfAndRecordsNoDemand() async throws {
    // A signed-out search is not evidence that the catalog is missing anything.
    let catalog = FakeCatalog(failure: GlossedError(.notAuthenticated, userMessage: "sign in to keep going."))
    await #expect(throws: GlossedError(.notAuthenticated, userMessage: "sign in to keep going.")) {
        try await SearchRung(catalog: catalog).typeahead("laneige")
    }
    #expect(await catalog.recordedMisses.isEmpty)
}

@Test func aDeniedSearchSurfacesAsDeniedRatherThanAsNoResults() async throws {
    let catalog = FakeCatalog(failure: GlossedError(.permissionDenied, userMessage: "that isn't yours to change."))
    await #expect(throws: GlossedError.self) {
        try await SearchRung(catalog: catalog).typeahead("laneige")
    }
    #expect(await catalog.recordedMisses.isEmpty)
}

@Test func personalHitsPassThroughExactlyAsRLSReturnedThem() async throws {
    // The rung applies no scope filter of its own: another user's personal
    // product never reaches us, and our own must not be dropped on the way out.
    let catalog = try FakeCatalog(hits: [
        hit(name: "Watermelon Glow"),
        hit(name: "the pink one from the market", scope: "personal")
    ])
    let result = try await SearchRung(catalog: catalog).typeahead("glow")
    #expect(result.hits.map(\.scope) == [.canonical, .personal])
}

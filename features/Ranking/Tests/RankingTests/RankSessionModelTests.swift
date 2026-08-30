import DataKit
import Foundation
import Testing
@testable import Ranking

// The model against a recording stub. Fixtures sit on BOTH sides of every
// precondition (the session-12 rule): a status that can rank and one that
// cannot, a wear-in that has elapsed and one that has not, a count above the
// unlock and one below it, an unlock of 3 and one that is not 3.

func row(
    id: UUID = UUID(),
    category: String = "blush",
    status: String = "own",
    rank: Int? = nil,
    startedOn: String? = nil,
    loggedAt: String = "2026-08-01T12:00:00Z",
    name: String = "pocket blush",
    variantLabel: String? = "freckle"
) throws -> ShelfRow {
    let raw = """
    {"user_item_id":"\(id.uuidString)",
     "variant_id":"\(UUID().uuidString)","product_id":"\(UUID().uuidString)",
     "product_name":"\(name)","brand_name":"rhode",
     "category_slug":"\(category)","category_label":"\(category)es",
     "domain":"makeup","scope":"canonical",
     "benefit_line":null,"variant_label":\(variantLabel.map { "\"\($0)\"" } ?? "null"),
     "height_mm":70,"status":"\(status)",
     "started_on":\(startedOn.map { "\"\($0)\"" } ?? "null"),
     "note":null,"cutout_r2_key":null,"logged_at":"\(loggedAt)",
     "rank_position":\(rank.map(String.init) ?? "null"),"ranked_in_category":0,
     "is_anchor":false,"catalog_image_key":null,
     "catalog_image_width":null,"catalog_image_height":null}
    """
    return try JSONDecoder.postgrest.decode(ShelfRow.self, from: Data(raw.utf8))
}

func category(
    _ slug: String = "blush",
    wearInDays: Int = 0,
    unlockMin: Int = 3
) throws -> DataKit.Category {
    let raw = """
    {"id":"\(UUID().uuidString)","domain":"makeup","slug":"\(slug)","label":"\(slug)es",
     "wear_in_days":\(wearInDays),"is_anchor":false,"rank_unlock_min":\(unlockMin)}
    """
    return try JSONDecoder().decode(DataKit.Category.self, from: Data(raw.utf8))
}

actor Applied {
    private(set) var faceOffs: [FaceOffRecord] = []
    private(set) var positions: [RankPosition] = []
    private(set) var calls = 0
    func record(_ offs: [FaceOffRecord], _ pos: [RankPosition]) {
        faceOffs = offs
        positions = pos
        calls += 1
    }
}

func store(
    shelf: [ShelfRow],
    categories: [DataKit.Category],
    applied: Applied? = nil,
    failingApply: Bool = false,
    failingShelf: Bool = false
) -> RankingStore {
    RankingStore(
        shelf: {
            if failingShelf {
                throw GlossedError(.offline, userMessage: "the connection dropped")
            }
            return shelf
        },
        categories: { _ in categories },
        apply: { offs, pos in
            if failingApply {
                throw GlossedError(.offline, userMessage: "the connection dropped")
            }
            await applied?.record(offs, pos)
        }
    )
}

@MainActor
func loaded(_ model: RankSessionModel) async -> RankSessionModel {
    model.load()
    await model.loadTask?.value
    return model
}

// MARK: - the unlock gate

@MainActor
@Test func belowTheUnlockTheScreenSaysSoRatherThanHiding() async throws {
    // PRD §03: "Under 3 items in a category: like/dislike + chips only. At 3+,
    // ranking unlocks as a reward, never a required step." A reward you cannot
    // see coming is not a reward — so the state carries both numbers.
    let candidate = UUID()
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [row(id: candidate), row()],
            categories: [category()]
        )
    ))

    #expect(model.state == .locked(have: 2, need: 3))
}

@MainActor
@Test func theUnlockIsTheCategorysOwnNumberNotThree() async throws {
    // `rank_unlock_min` is a column. A category that unlocks at two must not
    // be held to the default, and hard-coding 3 here is how that would happen.
    let candidate = UUID()
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [row(id: candidate), row()],
            categories: [category(unlockMin: 2)]
        )
    ))

    guard case .ready = model.state else {
        Issue.record("a category that unlocks at two should be unlocked by two items")
        return
    }
}

// MARK: - eligibility

@MainActor
@Test func aWishlistItemCannotAnswerWhichDoYouReachFor() async throws {
    // You have not reached for it. Counting it would let a wishlist outrank
    // the things you actually use.
    let candidate = UUID()
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [
                row(id: candidate),
                row(status: "finished"),
                row(status: "want_to_try")
            ],
            categories: [category()]
        )
    ))

    #expect(model.state == .locked(have: 2, need: 3))
    #expect(model.rows.count == 2)
}

@MainActor
@Test func anItemInsideItsWearInWindowIsNotEligibleYet() async throws {
    // Judging a retinoid at day three is judging nothing (PRD §03).
    let candidate = UUID()
    let now = try #require(Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 8, day: 30)
    ))
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [
                row(id: candidate, startedOn: "2026-01-01T00:00:00Z"),
                row(startedOn: "2026-01-01T00:00:00Z"),
                row(startedOn: "2026-08-29T00:00:00Z")
            ],
            categories: [category(wearInDays: 56)]
        ),
        now: now
    ))

    #expect(model.state == .locked(have: 2, need: 3))
}

@MainActor
@Test func itemsFromOtherCategoriesNeverEnterTheList() async throws {
    // "A lipgloss never faces a foundation" (PRD §03, ranking rules).
    let candidate = UUID()
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [
                row(id: candidate),
                row(),
                row(),
                row(category: "foundation"),
                row(category: "foundation")
            ],
            categories: [category()]
        )
    ))

    #expect(model.rows.count == 3)
    #expect(model.rows.allSatisfy { $0.categorySlug == "blush" })
}

// MARK: - the list to insert into

@MainActor
@Test func rankedItemsKeepTheirOrderAndUnrankedOnesJoinAtTheEnd() async throws {
    // An unpositioned item is not unrankable — it has not had its turn. A
    // session that refused to compare against one would ask nothing at all on
    // a shelf where nothing has been ranked before.
    let candidate = UUID()
    let second = UUID()
    let first = UUID()
    let late = UUID()
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [
                row(id: late, loggedAt: "2026-08-20T12:00:00Z"),
                row(id: second, rank: 2),
                row(id: candidate),
                row(id: first, rank: 1)
            ],
            categories: [category()]
        )
    ))

    #expect(model.rows.map(\.userItemID) == [first, second, candidate, late])
    guard case let .ready(session) = model.state else {
        Issue.record("four eligible items unlock a category that needs three")
        return
    }
    // The candidate is being placed, so it is never its own opponent.
    #expect(session.currentComparison?.candidate == candidate)
    #expect(session.currentComparison?.opponent != candidate)
}

extension JSONDecoder {
    /// The platform decoder DataKit's reads actually run through — a
    /// hand-configured stand-in is how `startedOn`'s decoding bug once stayed
    /// green (PR #84), and this model reads `started_on` to gate wear-in.
    static let postgrest: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a timestamp: \(string)")
        }
        return decoder
    }()
}

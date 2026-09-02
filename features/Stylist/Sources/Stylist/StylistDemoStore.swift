import Foundation

public extension StylistStore {
    /// A stylist that answers without a server: canned turns that exercise
    /// every block the thread can carry. For previews and for driving the tab
    /// on a stack with no `ANTHROPIC_API_KEY` — never the live path, and every
    /// line says "demo ·" first so a screenshot cannot pass for one.
    static func demo(shelfItemID: UUID = UUID(), lookID: UUID = UUID(), collectionID: UUID = UUID()) -> StylistStore {
        let fixtures = DemoFixtures(shelfItemID: shelfItemID, lookID: lookID, collectionID: collectionID)
        var store = StylistStore(send: { transcript in
            try await Task.sleep(for: .milliseconds(400))
            return fixtures.reply(to: transcript.last?.text ?? "")
        })
        store.saveRoutine = { _ in
            try await Task.sleep(for: .milliseconds(300))
            return UUID()
        }
        return store
    }
}

struct DemoFixtures: Sendable {
    let shelfItemID: UUID
    let lookID: UUID
    let collectionID: UUID

    func reply(to asked: String) -> StylistReply {
        let asked = asked.lowercased()
        if asked.contains("routine") {
            return StylistReply(
                text: "demo · tight after cleansing reads as a barrier that wants moisture back fast. "
                    + "here's the morning, with the one gap named.",
                blocks: [.routine(routine)], chips: ["save it", "what's missing for dryness", "build my pm routine"],
                groundedIn: ["profile", "shelf"], toolsUsed: ["propose_routine", "suggest_chips"]
            )
        }
        if asked.contains("serum") || asked.contains("compare") || asked.contains("try next") {
            return StylistReply(
                text: "demo · you ranked the ordinary first of your two serums. "
                    + "people with dry skin who face-off cloud serum keep it too.",
                blocks: [.products(products)], chips: ["add cloud serum to want to try", "not now"],
                groundedIn: ["shelf", "search_catalog"], toolsUsed: ["search_catalog", "show_products", "suggest_chips"]
            )
        }
        if asked.contains("look") {
            return StylistReply(
                text: "demo · your golden hour look leans on the bronzer and the balm. "
                    + "tonight, swap the balm for the lip oil you ranked first.",
                blocks: [.look(look), .collection(collection)], chips: ["open the look", "build a look for tonight"],
                groundedIn: ["looks", "collections"], toolsUsed: [
                    "reference_look",
                    "reference_collection",
                    "suggest_chips"
                ]
            )
        }
        if asked.contains("capital") || asked.contains("weather") {
            return StylistReply(
                text: "demo · that one's outside what I do — I stay on skin, hair, makeup and what's on your shelf. "
                    + "want me to look at your pm routine instead?",
                blocks: [], chips: ["build my pm routine"], groundedIn: [], toolsUsed: ["suggest_chips"]
            )
        }
        return StylistReply(
            text: "demo · ask me about a routine, your serums, or your golden hour look "
                + "and I'll show you what a reply can carry.",
            blocks: [], chips: ["build my am routine", "compare my two serums", "recreate my golden hour look"],
            groundedIn: ["shelf"], toolsUsed: ["suggest_chips"]
        )
    }

    var routine: RoutineDraftBlock {
        RoutineDraftBlock(
            title: "glass skin, morning",
            slot: "am",
            targets: ["dryness"],
            steps: [
                .init(
                    userItemID: shelfItemID,
                    productName: "pineapple refresh",
                    brandName: "rhode",
                    categoryLabel: "cleanser",
                    note: nil
                ),
                .init(
                    userItemID: shelfItemID, productName: "niacinamide 10% + zinc", brandName: "the ordinary",
                    categoryLabel: "serums + actives", note: "wait two minutes before the next step"
                ),
                .init(
                    userItemID: shelfItemID,
                    productName: "you",
                    brandName: "glossier",
                    categoryLabel: "moisturizer",
                    note: nil
                )
            ],
            gap: .init(categoryLabel: "sunscreen", reason: "the one step you own nothing for")
        )
    }

    var products: ProductListBlock {
        ProductListBlock(reason: "the two serums you own, ranked by you", products: [
            .init(
                productID: UUID(), name: "niacinamide 10% + zinc", brandName: "the ordinary", categorySlug: "serum",
                onShelf: true, rankPosition: 1, rankedInCategory: 2, faceOffCount: nil, catalogImageKey: nil
            ),
            .init(
                productID: UUID(), name: "cloud serum", brandName: "somebrand", categorySlug: "serum",
                onShelf: false, rankPosition: nil, rankedInCategory: nil, faceOffCount: 12, catalogImageKey: nil
            )
        ])
    }

    var look: LookRefBlock {
        LookRefBlock(lookID: lookID, caption: "golden hour, favorites on", photoN: 2)
    }

    var collection: CollectionRefBlock {
        CollectionRefBlock(collectionID: collectionID, title: "holy grails only", itemN: 1)
    }
}

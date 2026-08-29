import DataKit
import Foundation
import Observation
import Tracking

/// Rung 4's form: four fields, no review queue.
///
/// Brand is a typeahead FK — free-text brands are how a catalog acquires
/// "Rare Beauty", "rare beauty" and "RareBeauty" as three rows (GLO-60) — so
/// the model holds a *picked* brand, and typing after a pick un-picks it: the
/// text field showing one brand while the draft carries another would submit
/// something the screen never said.
@MainActor
@Observable
public final class CreateRungModel {
    public private(set) var ladder: Ladder

    /// What the brand field shows. Editing it clears the pick until a brand is
    /// chosen again.
    public var brandQuery: String {
        didSet {
            if let picked = pickedBrand, picked.name != brandQuery {
                pickedBrand = nil
            }
        }
    }

    public private(set) var brandOptions: [Brand] = []
    public private(set) var pickedBrand: Brand?

    public var productName: String
    public var variantText: String = ""

    public private(set) var categories: [DataKit.Category] = []
    public private(set) var pickedCategory: DataKit.Category?

    public private(set) var isWorking = false
    public private(set) var failure: GlossedError?

    /// The shelf row the create door wrote, kept for the host: the fit prompt
    /// needs its id, and by resolution time the write that returned it is over.
    public private(set) var loggedItem: UserItem?

    /// A create that landed while its shelf log did not (the GLO-15 quiet
    /// failure). Held so a retry resumes at the log instead of creating twice.
    private var createdButNotShelved: CreatedProduct?
    /// One idempotency key per form submission: a retried log upserts the same
    /// shelf row.
    private let logClientID = UUID()

    private let rung: CreateRung
    private let catalog: any ProductCreating
    private let tracker: Tracker?

    /// Seeded from the ladder: the words someone typed two rungs ago arrive
    /// pre-filled, and a scanned code that missed rides the draft.
    public init(
        catalog: any ProductCreating,
        shelf: any ItemLogging,
        ladder: Ladder,
        tracker: Tracker? = nil
    ) {
        rung = CreateRung(catalog: catalog, shelf: shelf)
        self.catalog = catalog
        self.ladder = ladder
        self.tracker = tracker
        brandQuery = ""
        productName = ladder.query
    }

    /// The whole category tree, once. The select needs every domain because
    /// the ladder can be entered without one.
    public func loadCategories() async {
        do {
            categories = try await catalog.categories(domain: nil)
        } catch {
            failure = error
        }
    }

    public func searchBrands() async {
        guard pickedBrand == nil else { return }
        do {
            brandOptions = try await catalog.brands(matching: brandQuery, limit: 8)
        } catch {
            brandOptions = []
            failure = error
        }
    }

    public func pick(brand: Brand) {
        pickedBrand = brand
        brandQuery = brand.name
        brandOptions = []
    }

    public func pick(category: DataKit.Category) {
        pickedCategory = category
    }

    /// The four fields, minus the optional one. Variant is genuinely optional —
    /// plenty of products have no shade and one size.
    public var canCreate: Bool {
        pickedBrand != nil
            && pickedCategory != nil
            && !Ladder.tidy(productName).isEmpty
            && !isWorking
    }

    /// What the confirmation card shows.
    public struct ConfirmedMeta: Equatable, Sendable {
        public let brand: String
        public let name: String
        public let variant: String?
    }

    /// Read from the form rather than re-fetched: the card's promise is
    /// "what you typed is what exists".
    public var confirmedMeta: ConfirmedMeta? {
        guard case .created = ladder.resolution, let pickedBrand else { return nil }
        return ConfirmedMeta(brand: pickedBrand.name, name: Ladder.tidy(productName), variant: tidiedVariant)
    }

    public func create() async {
        guard canCreate, let brand = pickedBrand, let category = pickedCategory else { return }
        isWorking = true
        defer { isWorking = false }

        let draft = PersonalProductDraft(
            brandID: brand.id,
            categoryID: category.id,
            domain: category.domain,
            name: Ladder.tidy(productName),
            variant: tidiedVariant,
            scannedGTIN: ladder.scannedGTIN
        )
        do {
            switch try await rung.createAndLog(draft, resuming: createdButNotShelved, clientID: logClientID) {
            case let .shelved(created, item):
                failure = nil
                createdButNotShelved = nil
                loggedItem = item
                ladder.created(productID: created.productID)
                // Fired on the write landing, not the tap — an event is a
                // fact. Created products are personal scope by construction.
                await tracker?.track(.itemLogged(
                    variantID: created.variantID,
                    categoryID: category.id,
                    source: .ladderCreate,
                    scope: CatalogScope.personal.rawValue
                ))
            case let .createdButNotShelved(created, error):
                createdButNotShelved = created
                failure = error
            }
        } catch {
            failure = error
        }
    }

    private var tidiedVariant: String? {
        let tidied = Ladder.tidy(variantText)
        return tidied.isEmpty ? nil : tidied
    }
}

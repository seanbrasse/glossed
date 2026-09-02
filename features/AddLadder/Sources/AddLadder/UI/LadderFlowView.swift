import DataKit
import DesignSystem
import SwiftUI
import Tracking

/// Everything the ladder asks of the catalog, in one requirement — the four
/// per-need protocols, which `CatalogRepository` already satisfies severally.
public typealias LadderCatalog = CatalogSearching & NearMatching & ProductCreating & VariantListing & VariantLookup

/// The ladder as one trip: search → barcode → near matches → create → confirm.
///
/// Until now every rung was its own picker state and the transitions only
/// existed in `Ladder`. This host makes them real: each rung's model mutates
/// its own ladder, the host watches the ladder move and constructs the next
/// rung's model with the carried state — the query someone typed at search
/// arrives pre-filled two rungs later, and a scanned code that missed rides
/// all the way into the create draft.
///
/// The variant seam, resolved both ways:
/// - A *matched* product from search/near-matches opens the shade/size pick
///   (GLO-56 → GLO-16's logging sheet). The sheet hands a variant id back to
///   the rung model, and the same matched-log machinery as the barcode path
///   writes the row — one write path, two doors.
/// - A *matched barcode* is an exact variant (GLO-56: "barcode skips the
///   pick"), so it logs directly and hands back to the host.
/// A shelf row the flow just wrote, with the category that classifies it.
/// `categoryID` is nil when the door could not know one — the matched-barcode
/// path, whose bare variant lookup carries no category (the same stated gap
/// that leaves that door eventless, GLO-80). The host uses this to decide
/// whether the log deserves a follow-up ask (the anchor fit prompt, GLO-16).
public struct LoggedShelfItem: Sendable, Equatable {
    public let userItemID: UUID
    public let categoryID: UUID?
}

public struct LadderFlowView: View {
    enum Step {
        case search(SearchRungModel)
        case barcode(BarcodeRungModel)
        case nearMatches(NearMatchRungModel)
        case create(CreateRungModel)
    }

    @State private var step: Step
    /// The search rung's words, kept because the barcode rung's ladder starts
    /// fresh (it never has a query) — without this the near-match rung would
    /// ask someone to retype what they already said.
    @State private var carriedQuery = ""
    /// Idempotency for the matched-barcode log: one key per flow, so a retry
    /// after a failed write upserts the same shelf row.
    @State private var matchClientID = UUID()
    @State private var isLoggingMatch = false
    @State private var matchLogFailure: GlossedError?
    @State private var hasNotifiedShelf = false
    @State private var hasReportedLog = false
    /// What `item_logged` needs beyond the variant id, captured at pick time —
    /// by the time the ladder resolves, the hit that supplied them is gone.
    /// Nil on the matched-barcode path: a bare variant lookup carries no
    /// category, so that door logs without an event (the stated gap, GLO-80).
    @State private var matchEventContext: (categoryID: UUID, scope: String)?

    private let catalog: any LadderCatalog
    private let shelf: any ItemLogging
    private let tracker: Tracker?
    /// Nil leaves the barcode rung exactly as it was (GLO-93): fixture
    /// states and environments without the function keep the old behaviour.
    private let fill: (any BarcodeFilling)?
    private let onClose: () -> Void
    /// Something landed on the shelf — the host should reload it.
    private let onShelfChanged: () -> Void
    /// The row that landed, once per flow — richer than `onShelfChanged`
    /// because the host's next question (fit) is about *this* row.
    private let onLogged: (LoggedShelfItem) -> Void

    public init(
        catalog: any LadderCatalog,
        shelf: any ItemLogging,
        tracker: Tracker? = nil,
        fill: (any BarcodeFilling)? = nil,
        suggestions: (any LadderSuggesting)? = nil,
        query: String = "",
        onClose: @escaping () -> Void = {},
        onShelfChanged: @escaping () -> Void = {},
        onLogged: @escaping (LoggedShelfItem) -> Void = { _ in }
    ) {
        self.catalog = catalog
        self.shelf = shelf
        self.tracker = tracker
        self.fill = fill
        self.onClose = onClose
        self.onShelfChanged = onShelfChanged
        self.onLogged = onLogged
        _step = State(initialValue: .search(SearchRungModel(catalog: catalog, query: query, suggestions: suggestions)))
        _carriedQuery = State(initialValue: query)
    }

    public var body: some View {
        rung
            .onChange(of: currentLadder) { _, ladder in
                react(to: ladder)
            }
            // The shade sheet is an overlay, not a `.sheet`, so the search
            // field underneath keeps focus and the keyboard stays up over the
            // sheet (Sean, Sep 2: "the keyboard doesn't go away when adding
            // a product, it's stuck"). A pick ends the typing; say so.
            .onChange(of: pickedHit) { _, hit in
                if hit != nil {
                    endEditing()
                }
            }
            .overlay {
                if let hit = pickedHit {
                    // Identity pinned to the pick: a different product is a
                    // fresh sheet with a fresh load, never recycled state.
                    VariantPickSheet(
                        model: VariantPickModel(hit: hit, catalog: catalog),
                        onConfirm: { variantID in pickedVariant(variantID) },
                        onCancel: { cancelVariantPick() }
                    )
                    .id(hit.id)
                }
                if isLoggingMatch || matchLogFailure != nil {
                    matchLogOverlay
                }
            }
    }

    @ViewBuilder private var rung: some View {
        switch step {
        case let .search(model):
            SearchRungView(model: model, onBack: onClose)
        case let .barcode(model):
            BarcodeRungView(model: model, onBack: onClose)
        case let .nearMatches(model):
            NearMatchRungView(model: model, onBack: onClose)
        case let .create(model):
            CreateRungView(model: model, onBack: onClose, onDone: onClose)
        }
    }

    private var currentLadder: Ladder {
        switch step {
        case let .search(model): model.ladder
        case let .barcode(model): model.ladder
        case let .nearMatches(model): model.ladder
        case let .create(model): model.ladder
        }
    }

    private var pickedHit: CatalogHit? {
        switch step {
        case let .search(model): model.pickedHit
        case let .nearMatches(model): model.pickedHit
        case .barcode, .create: nil
        }
    }

    /// The sheet's answer, delivered to whichever rung asked — the rung model
    /// is the only party allowed to resolve the ladder.
    private func pickedVariant(_ variantID: UUID) {
        if let hit = pickedHit {
            matchEventContext = (categoryID: hit.categoryID, scope: hit.scope.rawValue)
        }
        switch step {
        case let .search(model): model.pickedVariant(variantID)
        case let .nearMatches(model): model.pickedVariant(variantID)
        case .barcode, .create: break
        }
    }

    // MARK: - Moving down the ladder

    private func react(to ladder: Ladder) {
        if let resolution = ladder.resolution {
            resolved(resolution)
            return
        }
        switch (step, ladder.rung) {
        case let (.search(model), .barcode):
            carriedQuery = model.ladder.query
            step = .barcode(BarcodeRungModel(catalog: catalog, fill: fill))
        case (.barcode, .nearMatches):
            // The barcode ladder carries the scanned code but never a query;
            // re-injecting the carried words keeps both.
            var carried = ladder
            carried.refine(query: carriedQuery)
            step = .nearMatches(NearMatchRungModel(catalog: catalog, ladder: carried))
        case (.nearMatches, .create):
            step = .create(CreateRungModel(catalog: catalog, shelf: shelf, ladder: ladder, tracker: tracker))
        default:
            break
        }
    }

    private func resolved(_ resolution: Ladder.Resolution) {
        switch resolution {
        case let .matched(variantID):
            logMatch(variantID)
        case .created:
            // The create rung logged the shelf row itself and shows its own
            // confirmation; the host only passes the news along, once.
            if case let .create(model) = step, let item = model.loggedItem {
                reportLogged(LoggedShelfItem(userItemID: item.id, categoryID: model.pickedCategory?.id))
            }
            notifyShelfChanged()
        }
    }

    private func logMatch(_ variantID: UUID) {
        guard !isLoggingMatch else { return }
        isLoggingMatch = true
        matchLogFailure = nil
        Task {
            defer { isLoggingMatch = false }
            do {
                let item = try await shelf.log(LogDraft(variantID: variantID, clientID: matchClientID))
                // Fired on the write landing, not the tap — an event is a
                // fact. Context exists only when a pick supplied it (see
                // `matchEventContext`); the barcode door logs eventless.
                if let context = matchEventContext, let tracker {
                    await tracker.track(.itemLogged(
                        variantID: variantID,
                        categoryID: context.categoryID,
                        source: .search,
                        scope: context.scope
                    ))
                }
                reportLogged(LoggedShelfItem(userItemID: item.id, categoryID: matchEventContext?.categoryID))
                notifyShelfChanged()
                onClose()
            } catch {
                matchLogFailure = GlossedError.from(error)
            }
        }
    }

    private func notifyShelfChanged() {
        guard !hasNotifiedShelf else { return }
        hasNotifiedShelf = true
        onShelfChanged()
    }

    /// Once per flow, like `notifyShelfChanged` — a re-fired resolution change
    /// must not turn one log into two fit prompts.
    private func reportLogged(_ logged: LoggedShelfItem) {
        guard !hasReportedLog else { return }
        hasReportedLog = true
        onLogged(logged)
    }

    private func cancelVariantPick() {
        switch step {
        case let .search(model): model.cancelVariantPick()
        case let .nearMatches(model): model.cancelVariantPick()
        case .barcode, .create: break
        }
    }

    /// The matched-barcode write, made visible: a spinner while it runs, and a
    /// failure that keeps the retry (same idempotency key) instead of leaving
    /// a scan that silently never reached the shelf.
    private var matchLogOverlay: some View {
        VStack(spacing: Tokens.Space.s3) {
            if isLoggingMatch {
                ProgressView()
                Text("adding to your shelf…").meta()
            } else if let failure = matchLogFailure {
                Text(failure.userMessage).meta().multilineTextAlignment(.center)
                Button("try again") {
                    if case let .matched(variantID) = currentLadder.resolution {
                        logMatch(variantID)
                    }
                }
                .buttonStyle(.glossed())
            }
        }
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        )
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Ink.primary.opacity(0.4))
        .ignoresSafeArea()
    }
}

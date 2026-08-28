import DataKit
import DesignSystem
import SwiftUI

/// Everything the ladder asks of the catalog, in one requirement — the three
/// per-rung protocols, which `CatalogRepository` already satisfies severally.
public typealias LadderCatalog = CatalogSearching & ProductCreating & VariantLookup

/// The ladder as one trip: search → barcode → near matches → create → confirm.
///
/// Until now every rung was its own picker state and the transitions only
/// existed in `Ladder`. This host makes them real: each rung's model mutates
/// its own ladder, the host watches the ladder move and constructs the next
/// rung's model with the carried state — the query someone typed at search
/// arrives pre-filled two rungs later, and a scanned code that missed rides
/// all the way into the create draft.
///
/// Two seams are stated rather than papered over:
/// - A *matched* product from search/near-matches needs the shade/size pick,
///   which the GLO-56 decision assigned to the logging sheet (GLO-16, not
///   built). Picking a product shows an honest interim card and a way back —
///   it does not guess a variant.
/// - A *matched barcode* is an exact variant (GLO-56: "barcode skips the
///   pick"), so it logs directly and hands back to the host.
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

    private let catalog: any LadderCatalog
    private let shelf: any ItemLogging
    private let onClose: () -> Void
    /// Something landed on the shelf — the host should reload it.
    private let onShelfChanged: () -> Void

    public init(
        catalog: any LadderCatalog,
        shelf: any ItemLogging,
        query: String = "",
        onClose: @escaping () -> Void = {},
        onShelfChanged: @escaping () -> Void = {}
    ) {
        self.catalog = catalog
        self.shelf = shelf
        self.onClose = onClose
        self.onShelfChanged = onShelfChanged
        _step = State(initialValue: .search(SearchRungModel(catalog: catalog, query: query)))
        _carriedQuery = State(initialValue: query)
    }

    public var body: some View {
        rung
            .onChange(of: currentLadder) { _, ladder in
                react(to: ladder)
            }
            .overlay {
                if let productID = pickedProductID {
                    variantPickInterim(productID)
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

    private var pickedProductID: UUID? {
        switch step {
        case let .search(model): model.pickedProductID
        case let .nearMatches(model): model.pickedProductID
        case .barcode, .create: nil
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
            step = .barcode(BarcodeRungModel(catalog: catalog))
        case (.barcode, .nearMatches):
            // The barcode ladder carries the scanned code but never a query;
            // re-injecting the carried words keeps both.
            var carried = ladder
            carried.refine(query: carriedQuery)
            step = .nearMatches(NearMatchRungModel(catalog: catalog, ladder: carried))
        case (.nearMatches, .create):
            step = .create(CreateRungModel(catalog: catalog, shelf: shelf, ladder: ladder))
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
                _ = try await shelf.log(LogDraft(variantID: variantID, clientID: matchClientID))
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

    // MARK: - The stated seams

    /// A picked product is not yet a shelf item — the shade/size pick belongs
    /// to the logging sheet (GLO-56 → GLO-16), which does not exist. Saying so
    /// beats guessing a variant, and the way back keeps the rung usable.
    private func variantPickInterim(_: UUID) -> some View {
        VStack(spacing: Tokens.Space.s3) {
            Text("almost —")
                .font(Typography.display(24))
                .foregroundStyle(Tokens.Ink.primary)
            Text(
                "picking the shade & size is the logging sheet's job, and it isn't built yet "
                    + "(GLO-16). scan the barcode instead — a scan knows its exact variant."
            )
            .meta()
            .multilineTextAlignment(.center)
            Button("back") {
                cancelVariantPick()
            }
            .buttonStyle(.glossed(.secondary))
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

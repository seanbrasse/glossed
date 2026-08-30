import DesignSystem
import SwiftUI

/// Rung 2: near matches, framed as a question about the photo.
///
/// Built to `G.AddLadder` rung 2, which is the sparest screen in the flow: an
/// eyebrow, the candidates, and the way out. No heading and no search field —
/// the query came down the ladder, and the rung's job is to make you look at
/// the pictures rather than re-read the names.
public struct NearMatchRungView: View {
    @State private var model: NearMatchRungModel
    @State private var searchTask: Task<Void, Never>?
    private let onBack: () -> Void

    public init(model: NearMatchRungModel, onBack: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onBack = onBack
    }

    public var body: some View {
        LadderScaffold(ladder: model.ladder, onBack: onBack) {
            Text(eyebrow).eyebrow()
            // The one thing the frame has no state for. A prototype always
            // arrives with a query; a scan that missed arrives with a GTIN and
            // no name at all, and the rung cannot show candidates until it has
            // one. Present only in that case — otherwise the field would invite
            // re-typing what the ladder already carried down.
            if model.arrivedWithoutAName {
                GlossedInput(
                    "what's it called?",
                    text: $model.query,
                    label: "the scan came up empty",
                    hint: hint
                )
                .plainTyping()
            } else if let hint {
                // The field is where a hint normally lives, so without this a
                // failed lookup on a rung that has no field says nothing at
                // all: an eyebrow, no candidates, and a way out. That reads as
                // "we checked, there is nothing" — the exact conclusion this
                // rung exists to stop someone reaching by accident.
                Text(hint).meta()
            }
            if model.failure != nil {
                retryButton
            }
            options
        }
        .scrollDismissesKeyboard(.immediately)
        .task { await model.search() }
        .onChange(of: model.query) { _, _ in scheduleSearch() }
    }

    /// The instruction that gives this rung its reason to exist — but only when
    /// the list can carry it. Two shades of one product read almost identically
    /// as text, so the name is the thing least worth trusting here; a list that
    /// failed to load has no photos to check, and telling someone to check them
    /// anyway is the screen vouching for something it does not know.
    private var eyebrow: String {
        canVouchForPhotos
            ? "NEAR MATCHES · CHECK THE PHOTO, NOT THE NAME"
            : "NEAR MATCHES"
    }

    /// There are two ways to have no photos to check, and the sentence above
    /// only ever tested one of them.
    ///
    /// `isCandidateListTrustworthy` answers *"are these all of them?"* — it
    /// catches a list that failed or has not arrived. It says nothing about a
    /// list that loaded perfectly and is **entirely drawings** (GLO-177), which
    /// is the ordinary case rather than the tail: 430 of 497 brands carry no
    /// catalog image, and this rung assembles its candidates by brand.
    ///
    /// Both halves of the URL are required, because both halves are required to
    /// render a photo — `catalogImageURL(base:)` needs the key *and* the base,
    /// and `LadderOptionRow` draws a `ProductMock` whenever either is missing.
    private var canVouchForPhotos: Bool {
        imageBase != nil && model.isCandidateListTrustworthy && model.everyCandidateHasAPhoto
    }

    /// Read here for the same reason `LadderOptionRow` reads it: the eyebrow is
    /// a claim about what those rows are showing, so it has to be answered from
    /// the same value they render from.
    @Environment(\.catalogImageBase) private var imageBase

    private var hint: String? {
        // Failure first, and it survives a retry until an answer replaces it —
        // an unanswered list must never read as an empty one here.
        if let failure = model.failure {
            return failure.userMessage
        }
        if model.isSearching {
            return "looking…"
        }
        return nil
    }

    /// `gap: 10` in the frame — the rows read as one list, and the way out is
    /// the last element of it rather than a footer under it.
    private var options: some View {
        VStack(spacing: 10) {
            ForEach(model.options) { option in
                LadderOptionRow(option) { model.choose(option) }
            }
        }
    }

    /// The same gap as the search rung's, and it is worse here: this rung's
    /// hint is often the only thing on screen besides the way out, so "try
    /// again in a sec." with nothing to press reads as the end of the road
    /// (GLO-179). Covers both branches — the failure can arrive whether or not
    /// the rung is asking for a name.
    private var retryButton: some View {
        Button("try again") {
            searchTask?.cancel()
            searchTask = Task { await model.search() }
        }
        .buttonStyle(.glossed(.secondary, size: .sm))
        // This rung clears `failure` only when an answer arrives, on purpose —
        // a window with no error and no candidates would read as "nothing
        // matched, safe to create". The cost is that the hint keeps showing the
        // old failure through the retry, so without this the press has no
        // visible effect at all. The search rung needs no equivalent: it clears
        // `failure` on the way in, so its button unmounts as the retry starts.
        .disabled(model.isSearching)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.search()
        }
    }
}

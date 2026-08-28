import DesignSystem
import SwiftUI

/// Rung 1: type, see what the catalog has, or say none of these.
///
/// Built to `G.AddLadder` rung 0 in the kit. The screen holds no ordering or
/// matching logic — it renders `SearchRungModel.options` in order and reports
/// taps back.
public struct SearchRungView: View {
    @State private var model: SearchRungModel
    @State private var searchTask: Task<Void, Never>?
    private let onBack: () -> Void

    public init(model: SearchRungModel, onBack: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onBack = onBack
    }

    public var body: some View {
        LadderScaffold(ladder: model.ladder, onBack: onBack) {
            GlossedInput("brand, product, shade…", text: $model.query, hint: hint)
                .plainTyping()
            if matchCount > 0 {
                Text("\(matchCount) MATCHES IN THE CATALOG").eyebrow()
            }
            options
        }
        // Arriving with a query already in hand is ordinary — the ladder seeds
        // it, and rung 0 can be re-entered. Without this the screen sits empty
        // until the user types a character it already has.
        .task { await model.search() }
        .onChange(of: model.query) { _, _ in scheduleSearch() }
    }

    /// The eyebrow counts matches, so it counts everything in the list except
    /// the way out — which is in the same list by design, and is not a match.
    private var matchCount: Int {
        model.options.count { option in
            if case .match = option {
                return true
            }
            return false
        }
    }

    /// The way out is the last element of the same list, not a footer, so it
    /// cannot drift out of the layout the matches live in.
    private var options: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(model.options) { option in
                    LadderOptionRow(option) { model.choose(option) }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// Says what the state actually is. A failed search is never dressed up as
    /// an empty catalog — the user would go create a product that exists.
    private var hint: String? {
        if model.failure != nil {
            return model.failure?.userMessage
        }
        if model.isSearching {
            return "looking…"
        }
        if model.isMiss {
            return "nothing yet — we noted that you looked"
        }
        return nil
    }

    /// One in-flight search at a time: a new keystroke cancels the last, so
    /// results cannot land out of order and show the answer to an older query.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.search()
        }
    }
}

extension View {
    /// Product names are not sentences and not dictionary words. Left alone,
    /// iOS capitalises the first letter and autocorrects brand names into
    /// English ones — "laneige" becomes "lineage" and the search misses.
    ///
    /// Every catalog query field in this package must use it. GLO-57 moves the
    /// choice into `GlossedInput`, where forgetting it stops being possible.
    @ViewBuilder
    func plainTyping() -> some View {
        #if canImport(UIKit)
            textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }
}

/// The rungs walked so far. Renders from the ladder's trail, so entering at the
/// barcode rung never shows a search step nobody was offered.
struct RungRail: View {
    let trail: [Rung]
    let current: Rung

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            ForEach(trail, id: \.self) { rung in
                Text(RungRail.label(for: rung))
                    .font(Typography.mono(Typography.Size.tag, bold: rung == current))
                    .foregroundStyle(rung == current ? Tokens.Ink.primary : Tokens.Ink.faint)
                if rung != trail.last {
                    Text("›").foregroundStyle(Tokens.Ink.faint)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func label(for rung: Rung) -> String {
        switch rung {
        case .search: "search"
        case .barcode: "scan"
        case .nearMatches: "near matches"
        case .create: "add it"
        case .confirm: "done"
        }
    }
}

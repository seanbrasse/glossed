import DataKit
import DesignSystem
import Discover
import Onboarding
import SwiftUI

// The tune card's wiring (GLO-18's acceptance line: a returning user with
// no anchor gets the tune card on discover, never a re-quiz), in its own
// file because `AppShell` sits one line under the 300-line ceiling and this
// host needs stored state — so the state lives HERE, on a self-contained
// view, not on the shell at all.

/// The injected card plus its own sheet: discover's slot renders this, and
/// tapping it opens `G.Tune` wired to the live profile.
struct TuneCardHost: View {
    let client: GlossedClient

    @State private var tuneOpen = false
    /// Resolved here, not on the shell (which sits at the line ceiling):
    /// nil while loading renders the anchored copy — the conservative line.
    @State private var hasAnchor: Bool?

    var body: some View {
        TuneCard(hasAnchor: hasAnchor ?? true) { tuneOpen = true }
            .sheet(isPresented: $tuneOpen) {
                TuneSheet(client: client)
            }
            .task {
                hasAnchor = await ((try? ProfileRepository(client: client).anchor()) != nil)
            }
    }
}

extension AppShell {
    /// The card's gate, decided from facts and set on the model — the
    /// stream re-composes deterministically around it (GLO-200). Offered to
    /// a user with a profile who has no anchor (GLO-18's acceptance line:
    /// never a re-quiz) or has never tuned.
    func armTuneCard(_ model: DiscoverModel) async {
        guard let client = session.client else { return }
        let profiles = ProfileRepository(client: client)
        let profile = try? await profiles.own()
        let anchor = try? await profiles.anchor()
        let offer = TuneGate.shouldOffer(
            profileExists: profile != nil,
            hasAnchor: anchor != nil,
            hasTuned: profile?.skinType != nil
        )
        model.injectedCards = offer ? [.init(id: "tune", position: 0)] : []
    }
}

/// `G.Tune` against the live stores: the current answers come off the
/// profile, brand options come off the user's own shelf (you rate the
/// brands you use — the honest option list, and it needs no new read),
/// and the save merges into the profile so untouched fields keep their
/// values. Brands ride `brandAffinities`, which encodes only when asked
/// (#326's never-erase design).
private struct TuneSheet: View {
    let client: GlossedClient

    @Environment(\.dismiss) private var dismiss
    @State private var brandOptions: [String] = []

    var body: some View {
        TuneView(
            model: TuneModel(
                load: { [profiles = ProfileRepository(client: client)] in
                    guard let profile = try await profiles.own() else {
                        return TuneModel.Selection()
                    }
                    return TuneModel.Selection(
                        skinType: profile.skinType,
                        concerns: profile.concerns,
                        brands: profile.brandAffinities
                    )
                },
                save: { [profiles = ProfileRepository(client: client)] selection in
                    // Merge, never overwrite blind: the draft carries the
                    // profile's own values for everything tune does not ask.
                    guard let profile = try await profiles.own() else {
                        throw GlossedError(
                            .notFound,
                            userMessage: "finish signing up first — then tuning has somewhere to save."
                        )
                    }
                    try await profiles.saveProfile(ProfileDraft(
                        birthYearMonth: profile.birthYearMonth,
                        domains: profile.domains,
                        skinType: selection.skinType,
                        toneBand: profile.toneBand,
                        hairPattern: profile.hairPattern,
                        concerns: selection.concerns,
                        climate: profile.climate,
                        displayName: profile.displayName,
                        brandAffinities: selection.brands
                    ))
                }
            ),
            brandOptions: brandOptions,
            onBack: { dismiss() },
            onSaved: { dismiss() }
        )
        .task {
            // The shelf's brands, most-shelved first, deduped — plus any
            // already-saved affinities so a saved brand never disappears
            // from its own list.
            let shelf = await (try? ShelfRepository(client: client).shelf()) ?? []
            var counts: [String: Int] = [:]
            for row in shelf {
                counts[row.brandName, default: 0] += 1
            }
            let fromShelf = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
            let saved = await (try? ProfileRepository(client: client).own()?.brandAffinities) ?? []
            var seen = Set<String>()
            brandOptions = (fromShelf + saved).filter { seen.insert($0).inserted }
        }
    }
}

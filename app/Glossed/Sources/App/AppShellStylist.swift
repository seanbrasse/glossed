import DataKit
import Stylist
import SwiftUI
import Tracking

// The stylist tab (docs/tech/08-stylist.md) and the crossings out of it.
// Its own file for the reason every tab has one: `AppShell.swift` sits at
// the line ceiling. A feature is not reachable until a file in `app/` says
// so — this is that file.

/// 08 §3: behind a flag. On for every DEBUG build so drives see it; off in
/// release until Sean flips it, with a defaults override for a build that
/// needs it on a device without rebuilding.
enum StylistFlag {
    static var isEnabled: Bool {
        #if DEBUG
            return true
        #else
            return UserDefaults.standard.bool(forKey: "stylist.enabled")
        #endif
    }
}

extension AppShell {
    @ViewBuilder var stylistTab: some View {
        if let client = session.client {
            StylistView(
                model: StylistModel(store: stylistStore(client: client)),
                imageURL: { key in session.imageBase?.appending(path: key) },
                // The doors are the shell's: a look opens as the post, a
                // collection as its editor — the same covers the profile uses.
                onOpenLook: { openLook = OpenLook(id: $0) },
                onOpenCollection: { openOwnItem = .collection($0) }
            )
        } else {
            unreadableTab(
                "stylist",
                line: "a chat that knows your shelf",
                because: "built — you're signed out"
            )
        }
    }

    /// The live seam: the edge function for the turn, `RoutinesRepository`
    /// for the save, the tracker for `stylist_query` (tool names and a bool,
    /// never the words).
    private func stylistStore(client: GlossedClient) -> StylistStore {
        // STYLIST_DEMO=1 in the launch environment: the canned stylist, for a
        // drive on a stack with no ANTHROPIC_API_KEY. Every canned line says
        // "demo ·" first, so a screenshot cannot pass for the live one.
        if ProcessInfo.processInfo.environment["STYLIST_DEMO"] == "1" {
            return StylistStore.demo()
        }
        var store = StylistStore.live(client: client, routines: RoutinesRepository(client: client))
        let tracker = session.tracker
        store.track = { toolsUsed, answered in
            guard let tracker else { return }
            Task { await tracker.track(.stylistQuery(toolsUsed: toolsUsed, answered: answered)) }
        }
        return store
    }
}

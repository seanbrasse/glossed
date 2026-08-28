#if DEBUG

    import DataKit
    import DesignSystem
    import Shelf
    import SwiftUI

    /// The first live read. Every other picker state is a fixture on purpose;
    /// this one signs into the local stack as the seed user and renders whatever
    /// `user_shelf_items` actually returns, through the same mapping the real
    /// app will use. If this screen and `shelf · bays` disagree about how a row
    /// draws, the mapping is lying somewhere — which is exactly what it is in
    /// the catalog to catch.
    ///
    /// Local only: the URL is the simulator's loopback into `supabase start`,
    /// the key is the shared local demo publishable key every local stack
    /// ships, and maya is seed.sql's user. None of it can reach production —
    /// the hosted URL is not here to reach.
    @MainActor
    enum LiveShelfEntry {
        static let live = ScreenEntry(
            id: "shelf-live",
            title: "shelf · LIVE — the seeded database",
            note: "signs in as maya against supabase start and renders user_shelf_items "
                + "through ShelfItem(row:) — no fixtures anywhere in this path"
        ) {
            LiveShelfScreen()
        }
    }

    private struct LiveShelfScreen: View {
        enum Phase {
            case connecting
            // The model rather than the sections: it is built where the
            // repository is in hand, so the sheet's fit section reads and
            // writes item_fits instead of firing into a no-op.
            case loaded(ShelfModel)
            case failed(String)
        }

        @State private var phase = Phase.connecting

        var body: some View {
            content
                .task { await load() }
        }

        @ViewBuilder
        private var content: some View {
            switch phase {
            case .connecting:
                VStack(spacing: Tokens.Space.s3) {
                    ProgressView()
                    Text("signing in as maya@local.test").meta()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.Ground.milk)
            case let .loaded(model):
                ShelfView(model: model)
            case let .failed(message):
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Text("the local stack is not answering").font(Typography.display(24))
                    Text(message).meta()
                    Text(
                        "run `make setup`, then put SUPABASE_PUBLISHABLE_KEY (from `supabase status`) "
                            + "in the Run scheme's environment and reopen this state"
                    ).meta()
                }
                .padding(Tokens.Space.s5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Tokens.Ground.milk)
            }
        }

        private func load() async {
            do {
                // The same env contract the release app will use, via the
                // validated path — a malformed value fails loudly here too.
                var environment = ProcessInfo.processInfo.environment
                if environment["SUPABASE_URL"] == nil {
                    environment["SUPABASE_URL"] = "http://127.0.0.1:54321"
                }
                let config = try GlossedConfig.validated(from: environment)
                let client = GlossedClient(config: config)
                try await client.signIn(email: "maya@local.test", password: "password")
                let repository = ShelfRepository(client: client)
                let rows = try await repository.shelf()
                phase = .loaded(ShelfModel(
                    sections: ShelfSection.grouped(
                        from: rows,
                        imageBase: config.supabaseURL.appending(path: "storage/v1/object/public/catalog")
                    ),
                    fitStore: .repository(repository)
                ))
            } catch let error as GlossedError {
                phase = .failed("\(error.code.rawValue): \(error.debugDetail ?? error.userMessage)")
            } catch {
                phase = .failed(String(describing: error))
            }
        }
    }

#endif

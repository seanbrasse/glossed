import DesignSystem
import SwiftUI

// The boot-failure screen, extracted for the 300-line ceiling — AppShell went
// to 301 when GLO-266's look-post cover landed, which is the #400/#394 shape
// (a per-file limit broken by an addition no single change broke), and the
// house remedy is extraction (AppShellLadder's precedent).

extension AppShell {
    func failedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("the local stack is not answering").font(Typography.display(24))
            Text(message).meta()
            Text(
                "run `make setup`, then launch with SUPABASE_PUBLISHABLE_KEY from "
                    + "`supabase status` in the environment. if sign-in fails, `supabase db reset` first."
            ).meta()
        }
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.Ground.milk)
    }
}

import DataKit
import DesignSystem
import SwiftUI

/// The typed under-13 rejection (PRD §17, COPPA): a hard block in words with
/// its support reference, never a validation hint. Its own type so the
/// account screen's body stays inside the linter's ceiling.
struct AgeRefusal: View {
    let error: GlossedError

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Text(error.userMessage)
                .font(Typography.display(15, weight: 700))
                .foregroundStyle(Tokens.Ink.primary)
            Text("ref \(error.supportReference)").meta()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Tokens.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Cherry.soft)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        )
    }
}

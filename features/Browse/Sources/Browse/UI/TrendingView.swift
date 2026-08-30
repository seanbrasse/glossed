import DataKit
import DesignSystem
import SwiftUI

/// What people are logging. GLO-129, `docs/tech/02` §4.
public struct TrendingView: View {
    @State private var model: TrendingModel

    public init(store: TrendingStore, skinType: String? = nil) {
        _model = State(wrappedValue: TrendingModel(store: store, skinType: skinType))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                header
                if model.isLoading {
                    ProgressView().padding(.top, Tokens.Space.s8)
                } else if model.isEmpty {
                    empty
                } else {
                    ForEach(model.rows) { row in
                        TrendingRowView(row: row)
                    }
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("TRENDING").eyebrow()
            Text("what people are logging")
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(Tokens.Ink.primary)
            Text([model.cohortLine, model.windowLine].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: Typography.Size.small))
                .foregroundStyle(Tokens.Ink.soft)
        }
    }

    private var empty: some View {
        Text("nothing logged yet in this window.")
            .font(.system(size: Typography.Size.small))
            .foregroundStyle(Tokens.Ink.soft)
    }
}

/// One row. A below-threshold row renders with its count rather than vanishing.
struct TrendingRowView: View {
    let row: TrendingVariant

    var body: some View {
        GlossedCard {
            HStack(alignment: .top, spacing: Tokens.Space.s3) {
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(row.brandName)
                        .font(.system(size: Typography.Size.meta))
                        .foregroundStyle(Tokens.Ink.soft)
                    Text(row.productName)
                        .font(.system(size: Typography.Size.h3, weight: .semibold))
                        .foregroundStyle(Tokens.Ink.primary)
                    if let shade = row.shadeCode {
                        Text(shade)
                            .font(Typography.mono(Typography.Size.meta))
                            .foregroundStyle(Tokens.Ink.soft)
                    }
                }
                Spacer()
                evidence
            }
        }
    }

    @ViewBuilder private var evidence: some View {
        if let line = row.notEnoughYetLine {
            Text(line)
                .font(Typography.mono(Typography.Size.meta))
                .foregroundStyle(Tokens.Ink.faint)
                .multilineTextAlignment(.trailing)
        } else {
            EvidenceLine(n: row.nLogs, label: "logged it")
        }
    }
}

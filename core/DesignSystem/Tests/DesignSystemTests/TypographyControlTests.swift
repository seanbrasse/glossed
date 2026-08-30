import SwiftUI
import Testing
@testable import DesignSystem

#if canImport(UIKit)
    import UIKit

    // These run under `make test` (iOS simulator), not CI's `swift test` —
    // that runs on macOS, where the scaling path being asserted does not
    // compile. The cap is the whole point of the helper, so it is worth
    // pinning even on a runner that only sometimes sees it.

    private func point(
        _ size: CGFloat, weight: Font.Weight = .bold, maxScale: CGFloat = Typography.controlMaxScale,
        at category: UIContentSizeCategory
    ) -> CGFloat {
        Typography.scaledControl(
            size: size, weight: weight, maxScale: maxScale,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        ).pointSize
    }

    @Test func defaultTextSizeRendersTheSizeItWasAskedFor() {
        // The fix must be invisible at the size most people use. A control
        // that shifted at .large would be a redesign wearing a bug fix's name.
        #expect(point(13, at: .large) == 13)
        #expect(point(17, at: .large) == 17)
    }

    @Test func accessibilitySizesActuallyGrowTheControl() {
        // The defect was that this number never moved (GLO-186).
        #expect(point(13, at: .accessibilityExtraExtraExtraLarge) > 13)
    }

    @Test func growthStopsAtTheCap() {
        let capped = point(13, at: .accessibilityExtraExtraExtraLarge)
        #expect(capped <= 13 * Typography.controlMaxScale)
    }

    @Test func aTighterCapBindsSooner() {
        // FloatingNav and GlossedButton are load-bearing for every screen's
        // layout, so they get to ask for less than the shared ceiling.
        let shared = point(17, at: .accessibilityExtraExtraExtraLarge)
        let tight = point(17, maxScale: 1.15, at: .accessibilityExtraExtraExtraLarge)
        #expect(tight < shared)
        #expect(tight <= 17 * 1.15)
    }

    @Test func weightSurvivesTheScaling() {
        let font = Typography.scaledControl(
            size: 13, weight: .heavy, maxScale: Typography.controlMaxScale,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        #expect((traits?[.weight] as? CGFloat ?? 0) > 0)
    }
#endif

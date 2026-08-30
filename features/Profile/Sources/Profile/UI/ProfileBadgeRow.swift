import DesignSystem
import SwiftUI

/// The three published body-fact badges, in the frame's order and the frame's
/// tones.
///
/// `G.Profile` draws them as `combo` (lilac) · `fenty 240` (butter) · `3b`
/// (mint). The tone tracks the FACT, not the position it happens to land in,
/// so the same badge is the same colour on every screen that draws it. Three
/// screens draw them — your own profile, someone else's, and the stranger
/// preview — and before this they were `.lilac` literals in two of the three
/// and absent from the third, so a reader had no way to tell the tone was
/// meant to mean something.
///
/// **Nil is absent, never "unknown".** A badge is published only by its
/// owner's explicit act (`tech/02` §3.4), and `public_profile` emits nothing
/// for a flag that is off or an owner who is a minor. So a missing badge here
/// says "not published" — which is a different claim from "has none", and the
/// RPC deliberately does not let the caller tell them apart. Rendering a
/// placeholder for one would be inventing the other.
///
/// This is also the only path by which `skin_type`, the anchor variant and
/// `hair_pattern` reach another human (`domain.md` §5, GLO-205). It renders
/// values the server already decided to emit; it never gates them itself, and
/// it never renders a fact the RPC withheld.
struct ProfileBadgeRow: View {
    let skinType: String?
    let anchor: String?
    let hairPattern: String?

    /// Kept pure and static so the ordering and the fact-to-tone mapping are
    /// one expression a test can hold, rather than a shape you can only check
    /// by rendering.
    nonisolated static func badges(
        skinType: String?, anchor: String?, hairPattern: String?
    ) -> [(value: String, tone: Badge.Tone)] {
        [(skinType, Badge.Tone.lilac), (anchor, .butter), (hairPattern, .mint)]
            .compactMap { pair in pair.0.map { (value: $0, tone: pair.1) } }
    }

    private var rendered: [(value: String, tone: Badge.Tone)] {
        Self.badges(skinType: skinType, anchor: anchor, hairPattern: hairPattern)
    }

    var body: some View {
        // An empty row draws nothing at all — not a spacer, not a rule. The
        // "you have published nothing" sentence belongs on the stranger
        // preview, which is the screen that exists to answer that question.
        if !rendered.isEmpty {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(rendered, id: \.value) { badge in
                    Badge(badge.value, tone: badge.tone)
                }
            }
        }
    }
}

import DesignSystem
import SwiftUI

/// What the profile looks like before it has loaded: the loaded layout's
/// shapes, in line colour, in the loaded layout's places.
///
/// Sean, Sep 2: *"There's a weird flash of a screen when navigating to the
/// profile tab, it looks bad."* Recorded on the simulator at 20 fps and
/// counted (GLO-241's rule): the FIRST entry into `you` was four discrete
/// jumps over ~0.85 s — discover cross-fading to a bare milk page with one
/// spinner at the top-left, then the header and tab strip popping in, then
/// the look tile's caption, then its photo. A second entry cross-faded in
/// two frames, so this is the first-load path and not the tab switch (which
/// #478 and the `TabView` pager already fixed).
///
/// Two moves. This view stands in for the header, counts and strip while
/// the two loads run, so the page has its shape from the first frame; and
/// the swap from it to the real thing is a fade rather than a cut (in
/// `OwnProfileView`). Neither is a spinner: a spinner says "nothing yet"
/// and then replaces itself with everything at once, which is the flash.
struct ProfileSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            HStack(spacing: Tokens.Space.s3) {
                Circle().fill(Tokens.Ground.line).frame(width: 52, height: 52)
                bar(width: 140, height: 26)
                Spacer(minLength: 0)
            }
            bar(width: 260, height: 14)
            bar(width: 200, height: 12)
                .padding(.top, Tokens.Space.s4)
            Capsule()
                .fill(Tokens.Ground.line)
                .frame(height: 44)
                .padding(.top, Tokens.Space.s4)
            HStack(spacing: Tokens.Space.s3) {
                tile
                tile
            }
            .padding(.top, Tokens.Space.s2)
        }
        .accessibilityLabel("loading your profile")
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.sm)
            .fill(Tokens.Ground.line)
            .frame(width: width, height: height)
    }

    /// One look tile's silhouette: the square photo and two lines under it.
    private var tile: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .fill(Tokens.Ground.line)
                .aspectRatio(1, contentMode: .fit)
            bar(width: 110, height: 12)
            bar(width: 70, height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import CoreGraphics
import Testing
@testable import Looks

// Fitting a photo into the post's frame: the arithmetic, without a screen.

@Test func aPhotoIsNeverSmallerThanTheFrame() {
    // 4000×3000 landscape into a 110×196 portrait frame: height is the tight
    // axis, so fill is 196/3000, and zoom cannot go under it.
    let fit = LookPhotoFit(imageSize: CGSize(width: 4000, height: 3000), frameSize: CGSize(width: 110, height: 196))
    #expect(abs(fit.fillScale - 196.0 / 3000.0) < 1e-9)
    #expect(fit.clampedZoom(0.2) == 1)
    #expect(fit.clampedZoom(9) == LookPhotoFit.maxZoom)
}

@Test func theOffsetIsClampedToTheSlackTheZoomCreated() {
    let fit = LookPhotoFit(imageSize: CGSize(width: 4000, height: 3000), frameSize: CGSize(width: 110, height: 196))
    // At fill, the height matches exactly: no vertical slack at all.
    let atFill = fit.clampedOffset(CGSize(width: 9999, height: 9999), at: 1)
    #expect(atFill.height == 0)
    #expect(atFill.width == fit.slack(at: 1).width)
    // Zooming in makes room on both axes.
    #expect(fit.slack(at: 2).height > 0)
    #expect(fit.clampedOffset(CGSize(width: -9999, height: 5), at: 2) == CGSize(
        width: -fit.slack(at: 2).width,
        height: 5
    ))
}

@Test func theCropIsTheFrameInTheImagesOwnPixels() {
    // A square photo in a square frame at fill and no pan crops to itself.
    let square = LookPhotoFit(imageSize: CGSize(width: 1000, height: 1000), frameSize: CGSize(width: 100, height: 100))
    #expect(square.cropRect(zoom: 1, offset: .zero) == CGRect(x: 0, y: 0, width: 1000, height: 1000))
    // Zoomed 2× and unpanned it is the middle half.
    #expect(square.cropRect(zoom: 2, offset: .zero) == CGRect(x: 250, y: 250, width: 500, height: 500))
    // Panned all the way left at 2× (image centre 50pt right of frame centre)
    // the crop starts at the photo's left edge.
    let left = square.cropRect(zoom: 2, offset: CGSize(width: 50, height: 0))
    #expect(left.minX == 0)
    #expect(left.width == 500)
}

@Test func theCropNeverLeavesThePhoto() {
    let fit = LookPhotoFit(imageSize: CGSize(width: 3000, height: 4000), frameSize: CGSize(width: 110, height: 196))
    let rect = fit.cropRect(zoom: 1, offset: CGSize(width: 9999, height: -9999))
    #expect(rect.minX >= 0)
    #expect(rect.minY >= 0)
    #expect(rect.maxX <= 3000)
    #expect(rect.maxY <= 4000)
}

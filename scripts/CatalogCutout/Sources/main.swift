// CatalogCutout <input> <output.png> [maxDimension=512]
//
// Removes the background from one product photo with Vision's foreground
// instance mask, scales the result so its longest side is `maxDimension`, and
// writes a transparent PNG. Prints `<width>x<height> cut|uncut` on success.
//
// A photo with a hand or a face in frame is REJECTED, not processed: a cutout
// keeps the person along with the product, and a floating hand on a shelf is
// worse than the drawn mock (Sean's session-5 review of the OBF images —
// crowd photos are a bad image source; the source ladder is GLO-79). The
// drawn mock is the correct floor for these until a studio image exists.
//
// Exit codes: 0 = cut out · 3 = no foreground found, wrote a plain resize
// (still usable — an uncut catalog photo beats a drawing) · 4 = person in
// frame, nothing written · 1 = unreadable input or unwritable output.

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: CatalogCutout <input> <output.png> [maxDimension]\n".utf8))
    exit(1)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let maxDimension = arguments.count > 3 ? CGFloat(Double(arguments[3]) ?? 512) : 512

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write(Data("unreadable input: \(inputURL.path)\n".utf8))
    exit(1)
}

// Person gate first: a hand holding the bottle survives the foreground mask
// and ships as part of the "product", and a floating hand on a shelf is
// impossible to unsee. Person *segmentation* is the detector that works here —
// hand-pose wants articulated joints and misses a gripping hand entirely
// (measured: pose found nothing in a photo that is 60% arm). Calibrated on
// the OBF set: hand photos measure 0.75%–60% person pixels, clean product
// photos measure exactly zero, so the threshold sits at 0.5%.
let handler = VNImageRequestHandler(cgImage: original)
let personRequest = VNGeneratePersonSegmentationRequest()
personRequest.qualityLevel = .balanced
try? handler.perform([personRequest])
if let mask = personRequest.results?.first?.pixelBuffer {
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
    let maskWidth = CVPixelBufferGetWidth(mask)
    let maskHeight = CVPixelBufferGetHeight(mask)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
    if let base = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: UInt8.self) {
        var personPixels = 0
        for y in 0 ..< maskHeight {
            for x in 0 ..< maskWidth where base[y * bytesPerRow + x] > 128 {
                personPixels += 1
            }
        }
        let fraction = Double(personPixels) / Double(maskWidth * maskHeight)
        if fraction > 0.005 {
            FileHandle.standardError.write(
                Data("person in frame (\(Int(fraction * 100))% of pixels)\n".utf8)
            )
            exit(4)
        }
    }
}

/// The mask request. A failure to find a foreground is an ordinary outcome for
/// flat-lay or heavily styled photos, not an error — the plain resize ships.
let request = VNGenerateForegroundInstanceMaskRequest()
try? handler.perform([request])

var working = original
var didCut = false
if let observation = request.results?.first,
   !observation.allInstances.isEmpty,
   let masked = try? observation.generateMaskedImage(
       ofInstances: observation.allInstances,
       from: handler,
       croppedToInstancesExtent: true
   )
{
    let ciImage = CIImage(cvPixelBuffer: masked)
    if let cut = CIContext().createCGImage(ciImage, from: ciImage.extent) {
        working = cut
        didCut = true
    }
}

// Scale down (never up) so the longest side is maxDimension, preserving alpha.
let longest = CGFloat(max(working.width, working.height))
let scale = min(1, maxDimension / longest)
let width = max(1, Int((CGFloat(working.width) * scale).rounded()))
let height = max(1, Int((CGFloat(working.height) * scale).rounded()))

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("could not create drawing context\n".utf8))
    exit(1)
}

context.interpolationQuality = .high
context.draw(working, in: CGRect(x: 0, y: 0, width: width, height: height))

guard let final = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else {
    FileHandle.standardError.write(Data("could not write \(outputURL.path)\n".utf8))
    exit(1)
}

CGImageDestinationAddImage(destination, final, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("could not finalize \(outputURL.path)\n".utf8))
    exit(1)
}

print("\(width)x\(height) \(didCut ? "cut" : "uncut")")
exit(didCut ? 0 : 3)

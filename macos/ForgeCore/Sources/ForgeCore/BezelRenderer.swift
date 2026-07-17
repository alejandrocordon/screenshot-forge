#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Places a screenshot inside a simple rounded device bezel, at **exactly** the
/// target size (so the framed image is still an upload-ready store size).
///
/// Scaffold: this draws a frameless rounded bezel — good enough to look like a
/// modern phone — without needing per-device mockup PNGs. To use real frames
/// later, load a frame image with a transparent screen cutout and composite the
/// cropped screenshot behind it using the frame's known screen rect.
public enum BezelRenderer {

    public static func renderFramed(
        source: URL,
        to target: PixelSize,
        style: FrameStyle = .phone,
        output: URL
    ) throws {
        guard
            let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw ForgeError.imageDecodeFailed(source)
        }

        let width = target.width
        let height = target.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ForgeError.renderFailed(output)
        }
        context.interpolationQuality = .high

        let shorterSide = Double(min(width, height))
        let bezel = CGFloat(shorterSide * style.bezelFraction)
        let outerRadius = CGFloat(shorterSide * style.outerCornerFraction)
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)

        // Bezel: a filled, rounded rectangle covering the whole canvas.
        context.setFillColor(CGColor(gray: CGFloat(style.bezelGray), alpha: 1))
        context.addPath(CGPath(roundedRect: canvas, cornerWidth: outerRadius,
                               cornerHeight: outerRadius, transform: nil))
        context.fillPath()

        // Inner "screen" rect, inset by the bezel thickness.
        let inner = canvas.insetBy(dx: bezel, dy: bezel)
        let innerRadius = max(0, outerRadius - bezel)
        let innerSize = PixelSize(width: Int(inner.width.rounded()),
                                  height: Int(inner.height.rounded()))

        // Crop the screenshot to exactly the inner screen size, then draw it
        // clipped to the rounded inner rect.
        let plan = CropGeometry.plan(
            source: PixelSize(width: image.width, height: image.height),
            target: innerSize
        )
        let scale = inner.width / CGFloat(innerSize.width)

        context.saveGState()
        context.addPath(CGPath(roundedRect: inner, cornerWidth: innerRadius,
                               cornerHeight: innerRadius, transform: nil))
        context.clip()

        let drawX = inner.minX - CGFloat(plan.cropX) * scale
        let drawY = inner.minY - CGFloat(plan.scaled.height - plan.cropY - innerSize.height) * scale
        context.draw(
            image,
            in: CGRect(
                x: drawX,
                y: drawY,
                width: CGFloat(plan.scaled.width) * scale,
                height: CGFloat(plan.scaled.height) * scale
            )
        )
        context.restoreGState()

        guard let outputImage = context.makeImage() else {
            throw ForgeError.renderFailed(output)
        }

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw ForgeError.renderFailed(output)
        }
        CGImageDestinationAddImage(destination, outputImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ForgeError.renderFailed(output)
        }
    }
}
#endif

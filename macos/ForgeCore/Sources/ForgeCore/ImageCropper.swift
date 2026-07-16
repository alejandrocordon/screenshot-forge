#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Crops still images to an exact size using CoreGraphics (no external deps).
public enum ImageCropper {

    /// Crop `source` to exactly `target` (scale-to-cover + center-crop) and
    /// write a PNG to `output`.
    public static func crop(source: URL, to target: PixelSize, output: URL) throws {
        guard
            let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw ForgeError.imageDecodeFailed(source)
        }

        let plan = CropGeometry.plan(
            source: PixelSize(width: image.width, height: image.height),
            target: target
        )

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: target.width,
            height: target.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ForgeError.renderFailed(output)
        }

        context.interpolationQuality = .high

        // CoreGraphics draws from a bottom-left origin, so convert the
        // top-left crop origin into a draw offset for the full scaled image.
        let drawX = -CGFloat(plan.cropX)
        let drawY = -CGFloat(plan.scaled.height - plan.cropY - target.height)
        context.draw(
            image,
            in: CGRect(
                x: drawX,
                y: drawY,
                width: CGFloat(plan.scaled.width),
                height: CGFloat(plan.scaled.height)
            )
        )

        guard let outputImage = context.makeImage() else {
            throw ForgeError.renderFailed(output)
        }

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

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

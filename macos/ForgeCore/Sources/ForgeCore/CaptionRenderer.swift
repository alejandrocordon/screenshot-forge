#if canImport(CoreGraphics) && canImport(CoreText) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Draws a marketing screenshot: a solid background, a centered title in a top
/// band, and the (cover-cropped) screenshot filling the area below — all at
/// exactly the target size. Single-line title (Core Text, no wrapping).
public enum CaptionRenderer {

    public static func render(
        source: URL,
        to target: PixelSize,
        caption: String,
        style: CaptionStyle = .standard,
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
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ForgeError.renderFailed(output)
        }
        context.interpolationQuality = .high

        // Background.
        context.setFillColor(CGColor(gray: CGFloat(style.backgroundGray), alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Screenshot area (below the title band). CG origin is bottom-left, so
        // the screenshot sits at the bottom and the title band is up top.
        let titleBandHeight = Int((Double(height) * style.titleAreaFraction).rounded())
        let screenHeight = max(1, height - titleBandHeight)
        let screenSize = PixelSize(width: width, height: screenHeight)
        let plan = CropGeometry.plan(
            source: PixelSize(width: image.width, height: image.height),
            target: screenSize
        )

        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: width, height: screenHeight))
        let drawX = -CGFloat(plan.cropX)
        let drawY = -CGFloat(plan.scaled.height - plan.cropY - screenSize.height)
        context.draw(
            image,
            in: CGRect(x: drawX, y: drawY,
                       width: CGFloat(plan.scaled.width), height: CGFloat(plan.scaled.height))
        )
        context.restoreGState()

        // Title (Core Text draws upright in CG's coordinate space — no flipping).
        let fontSize = CGFloat(Double(min(width, height)) * style.fontSizeFraction)
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .init(rawValue: kCTFontAttributeName as String): font,
            .init(rawValue: kCTForegroundColorAttributeName as String):
                CGColor(gray: CGFloat(style.textGray), alpha: 1),
        ]
        let attributed = NSAttributedString(string: caption, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let textBounds = CTLineGetImageBounds(line, context)

        let bandCenterY = CGFloat(screenHeight) + CGFloat(titleBandHeight) / 2
        context.textPosition = CGPoint(
            x: (CGFloat(width) - textBounds.width) / 2 - textBounds.minX,
            y: bandCenterY - textBounds.height / 2 - textBounds.minY
        )
        CTLineDraw(line, context)

        // Write PNG.
        guard let outputImage = context.makeImage() else { throw ForgeError.renderFailed(output) }
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw ForgeError.renderFailed(output) }
        CGImageDestinationAddImage(dest, outputImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw ForgeError.renderFailed(output) }
    }
}
#endif

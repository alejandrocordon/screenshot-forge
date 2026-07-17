import Foundation

/// A resolved plan to turn a source of `source` size into an exact `target`
/// using *scale-to-cover + center-crop* — identical to the Python engine's
/// `resize_and_crop` and to `crop_apple_video.sh`.
public struct CropPlan: Equatable, Sendable {
    /// Size the source is scaled to (fully covering the target) before cropping.
    public let scaled: PixelSize
    /// Top-left origin of the crop window inside the scaled image.
    public let cropX: Int
    public let cropY: Int
    /// Exact output size (== target).
    public let output: PixelSize
}

/// A rectangle in normalized `[0, 1]` coordinates with a top-left origin.
public struct NormalizedRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum CropGeometry {

    /// The region of the **source** that survives the crop (everything outside
    /// it is cut away), in normalized `[0, 1]` coordinates with a top-left
    /// origin. Use it to draw a live "what will be kept" overlay on the source.
    public static func keptRegion(source: PixelSize, target: PixelSize) -> NormalizedRect {
        let sourceAspect = Double(source.width) / Double(source.height)
        let targetAspect = Double(target.width) / Double(target.height)

        if targetAspect > sourceAspect {
            // Target is wider than the source → keep full width, crop top/bottom.
            let keptHeight = sourceAspect / targetAspect
            return NormalizedRect(x: 0, y: (1 - keptHeight) / 2, width: 1, height: keptHeight)
        } else {
            // Target is taller/narrower → keep full height, crop left/right.
            let keptWidth = targetAspect / sourceAspect
            return NormalizedRect(x: (1 - keptWidth) / 2, y: 0, width: keptWidth, height: 1)
        }
    }

    /// Compute the scale-to-cover + center-crop plan.
    ///
    /// Mirrors the Python engine exactly:
    /// `scale = max(tw/sw, th/sh)`, round the scaled dimensions, then
    /// center-crop to the target. The scaled size is clamped so it always
    /// fully covers the target even after rounding, which keeps the crop
    /// window inside the image.
    public static func plan(source: PixelSize, target: PixelSize) -> CropPlan {
        precondition(source.width > 0 && source.height > 0, "source size must be non-empty")

        let sw = Double(source.width), sh = Double(source.height)
        let tw = Double(target.width), th = Double(target.height)

        let scale = max(tw / sw, th / sh)
        var newW = Int((sw * scale).rounded())
        var newH = Int((sh * scale).rounded())

        // Guarantee full cover after rounding.
        newW = max(newW, target.width)
        newH = max(newH, target.height)

        let cropX = (newW - target.width) / 2
        let cropY = (newH - target.height) / 2

        return CropPlan(
            scaled: PixelSize(width: newW, height: newH),
            cropX: cropX,
            cropY: cropY,
            output: target
        )
    }
}

#if canImport(AVFoundation)
import Foundation
import AVFoundation
import CoreMedia

/// Crops app preview videos to an exact size using AVFoundation — no external
/// ffmpeg binary, so the app stays easy to notarize and distribute.
public enum VideoCropper {

    /// Crop `source` to exactly `target` (scale-to-cover + center-crop) and
    /// export an H.264 `.mp4` to `output`.
    ///
    /// The layer transform below handles the common upright case. Rotated
    /// footage (a non-identity `preferredTransform`) is the part worth
    /// validating on device — AVFoundation's composition coordinate space is
    /// famously fiddly. See macos/README.md.
    public static func crop(source: URL, to target: PixelSize, output: URL) async throws {
        let asset = AVURLAsset(url: source)

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ForgeError.videoHasNoVideoTrack(source)
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let frameRate = try await track.load(.nominalFrameRate)

        // Size as displayed after the track's own transform (accounts for rotation).
        let displayedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayedWidth = abs(displayedRect.width)
        let displayedHeight = abs(displayedRect.height)

        let plan = CropGeometry.plan(
            source: PixelSize(
                width: Int(displayedWidth.rounded()),
                height: Int(displayedHeight.rounded())
            ),
            target: target
        )
        let scale = CGFloat(plan.scaled.width) / displayedWidth

        // Apply the track transform, scale to cover, then translate so the
        // centered crop window lands at the composition's origin.
        var transform = preferredTransform
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(
            CGAffineTransform(translationX: -CGFloat(plan.cropX), y: -CGFloat(plan.cropY))
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: target.width, height: target.height)
        let fps = frameRate > 0 ? frameRate : 30
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
        videoComposition.instructions = [instruction]

        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ForgeError.videoExportFailed(source, "could not create export session")
        }

        try? FileManager.default.removeItem(at: output)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        export.videoComposition = videoComposition
        export.outputURL = output
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true

        // `exportAsynchronously` works on macOS 13+. On macOS 15+ the async
        // `export()` API is available; swap it in when you raise the minimum.
        await withCheckedContinuation { continuation in
            export.exportAsynchronously { continuation.resume() }
        }

        if export.status != .completed {
            throw ForgeError.videoExportFailed(
                source, export.error?.localizedDescription ?? "unknown error"
            )
        }
    }
}
#endif

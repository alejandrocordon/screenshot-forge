#if canImport(CoreGraphics) && canImport(AVFoundation)
import Foundation

public struct BatchProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let message: String

    public var fraction: Double {
        total == 0 ? 1 : Double(completed) / Double(total)
    }
}

public struct BatchOutcome: Sendable {
    public var processed: Int = 0
    public var failures: [String] = []
}

/// Orchestrates cropping a set of inputs to every selected Apple device size,
/// writing to `outputRoot/ios/<device>/<name>_<w>x<h>.<ext>` — the same layout
/// as the CLI and the shell script.
public actor BatchEngine {

    public init() {}

    public func run(
        inputs: [URL],
        devices: [AppleDevice],
        outputRoot: URL,
        onProgress: @Sendable @escaping (BatchProgress) -> Void = { _ in }
    ) async -> BatchOutcome {
        // Screenshots and app preview videos use *different* Apple resolutions.
        let imageSizes = AppleSizes.sizes(for: devices, kind: .screenshot)
        let videoSizes = AppleSizes.sizes(for: devices, kind: .video)

        let items: [(url: URL, kind: AssetKind)] = inputs.compactMap { url in
            guard let kind = SupportedTypes.kind(of: url) else { return nil }
            return (url, kind)
        }

        let total = items.reduce(0) { partial, item in
            partial + (item.kind == .image ? imageSizes.count : videoSizes.count)
        }
        var completed = 0
        var outcome = BatchOutcome()

        for item in items {
            let stem = item.url.deletingPathExtension().lastPathComponent
            let sizes = item.kind == .image ? imageSizes : videoSizes

            for size in sizes {
                if Task.isCancelled { return outcome }

                let deviceDir = outputRoot
                    .appendingPathComponent("ios", isDirectory: true)
                    .appendingPathComponent(size.device, isDirectory: true)

                do {
                    switch item.kind {
                    case .image:
                        let out = deviceDir.appendingPathComponent("\(stem)_\(size.fileTag).png")
                        try ImageCropper.crop(source: item.url, to: size.pixelSize, output: out)
                    case .video:
                        let out = deviceDir.appendingPathComponent("\(stem)_\(size.fileTag).mp4")
                        try await VideoCropper.crop(source: item.url, to: size.pixelSize, output: out)
                    }
                    outcome.processed += 1
                    completed += 1
                    onProgress(BatchProgress(
                        completed: completed, total: total,
                        message: "\(stem)_\(size.fileTag)"
                    ))
                } catch {
                    outcome.failures.append(
                        "\(item.url.lastPathComponent) → \(size.fileTag): \(error.localizedDescription)"
                    )
                    completed += 1
                    onProgress(BatchProgress(
                        completed: completed, total: total,
                        message: "error: \(item.url.lastPathComponent)"
                    ))
                }
            }
        }

        return outcome
    }
}
#endif

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

/// Options that tweak how outputs are rendered.
public struct ExportOptions: Sendable {
    /// Wrap screenshots in a device bezel (see `BezelRenderer`). Videos are
    /// never framed.
    public var frameScreenshots: Bool
    public var frameStyle: FrameStyle

    public init(frameScreenshots: Bool = false, frameStyle: FrameStyle = .phone) {
        self.frameScreenshots = frameScreenshots
        self.frameStyle = frameStyle
    }
}

/// A single output target: which store folder it belongs to and its size.
private struct Target {
    let folder: String      // "ios" or "android"
    let size: DeviceSize
}

/// Orchestrates cropping a set of inputs to every selected size, writing to
/// `outputRoot/<store>/<device>/<name>_<w>x<h>.<ext>`.
///
/// Progress is delivered as an `AsyncStream<Event>` — the caller just
/// `for await`s it (no `@Sendable` progress closure to capture `self`).
public actor BatchEngine {

    public enum Event: Sendable {
        case progress(BatchProgress)
        case finished(BatchOutcome)
    }

    public init() {}

    /// Start a run and return a stream of progress events ending in `.finished`.
    public nonisolated func run(
        inputs: [URL],
        appleDevices: [AppleDevice],
        googlePlayDevices: [GooglePlayDevice],
        outputRoot: URL,
        options: ExportOptions = ExportOptions()
    ) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task {
                let outcome = await self.perform(
                    inputs: inputs,
                    appleDevices: appleDevices,
                    googlePlayDevices: googlePlayDevices,
                    outputRoot: outputRoot,
                    options: options
                ) { progress in
                    continuation.yield(.progress(progress))
                }
                continuation.yield(.finished(outcome))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func perform(
        inputs: [URL],
        appleDevices: [AppleDevice],
        googlePlayDevices: [GooglePlayDevice],
        outputRoot: URL,
        options: ExportOptions,
        onProgress: @Sendable (BatchProgress) -> Void
    ) async -> BatchOutcome {
        let imageTargets: [Target] =
            AppleSizes.sizes(for: appleDevices, kind: .screenshot).map { Target(folder: "ios", size: $0) }
            + GooglePlaySizes.sizes(for: googlePlayDevices).map { Target(folder: "android", size: $0) }
        let videoTargets: [Target] =
            AppleSizes.sizes(for: appleDevices, kind: .video).map { Target(folder: "ios", size: $0) }

        let items: [(url: URL, kind: AssetKind)] = inputs.compactMap { url in
            guard let kind = SupportedTypes.kind(of: url) else { return nil }
            return (url, kind)
        }

        let total = items.reduce(0) { partial, item in
            partial + (item.kind == .image ? imageTargets.count : videoTargets.count)
        }
        var completed = 0
        var outcome = BatchOutcome()

        for item in items {
            let stem = item.url.deletingPathExtension().lastPathComponent
            let targets = item.kind == .image ? imageTargets : videoTargets

            for target in targets {
                if Task.isCancelled { return outcome }

                let deviceDir = outputRoot
                    .appendingPathComponent(target.folder, isDirectory: true)
                    .appendingPathComponent(target.size.device, isDirectory: true)

                do {
                    switch item.kind {
                    case .image:
                        let out = deviceDir.appendingPathComponent("\(stem)_\(target.size.fileTag).png")
                        if options.frameScreenshots {
                            try BezelRenderer.renderFramed(
                                source: item.url, to: target.size.pixelSize,
                                style: options.frameStyle, output: out
                            )
                        } else {
                            try ImageCropper.crop(source: item.url, to: target.size.pixelSize, output: out)
                        }
                    case .video:
                        let out = deviceDir.appendingPathComponent("\(stem)_\(target.size.fileTag).mp4")
                        try await VideoCropper.crop(source: item.url, to: target.size.pixelSize, output: out)
                    }
                    outcome.processed += 1
                    completed += 1
                    onProgress(BatchProgress(
                        completed: completed, total: total,
                        message: "\(target.folder)/\(target.size.device)/\(stem)_\(target.size.fileTag)"
                    ))
                } catch {
                    outcome.failures.append(
                        "\(item.url.lastPathComponent) → \(target.size.fileTag): \(error.localizedDescription)"
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

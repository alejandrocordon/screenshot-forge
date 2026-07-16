import Foundation

/// One App Store target size for a specific device.
public struct DeviceSize: Identifiable, Equatable, Hashable, Sendable {
    public let device: String
    public let width: Int
    public let height: Int

    public init(device: String, width: Int, height: Int) {
        self.device = device
        self.width = width
        self.height = height
    }

    public var id: String { "\(device)-\(width)x\(height)" }
    public var pixelSize: PixelSize { PixelSize(width: width, height: height) }
    public var isLandscape: Bool { width >= height }
    /// The `WxH` suffix used in output filenames, e.g. `1290x2796`.
    public var fileTag: String { "\(width)x\(height)" }
}

/// The Apple App Store devices this tool targets (matches `sizes.py`).
public enum AppleDevice: String, CaseIterable, Identifiable, Sendable {
    case iphone67 = "6.7inch"
    case iphone65 = "6.5inch"
    case iphone55 = "5.5inch"
    case ipad129  = "ipad_12.9inch"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .iphone67: return "iPhone 6.7\""
        case .iphone65: return "iPhone 6.5\""
        case .iphone55: return "iPhone 5.5\""
        case .ipad129:  return "iPad 12.9\""
        }
    }
}

/// Whether a target size is for a screenshot or an app preview video — Apple
/// defines *different* resolutions for each, so this picks the right table.
public enum AssetSizeKind: Sendable {
    case screenshot
    case video
}

/// The single source of truth for App Store target sizes.
public enum AppleSizes {

    /// Screenshot sizes (App Store screenshots) — ported from `sizes.py`.
    public static let screenshots: [DeviceSize] = [
        // iPhone 6.7"
        DeviceSize(device: "6.7inch", width: 1290, height: 2796),
        DeviceSize(device: "6.7inch", width: 2796, height: 1290),
        // iPhone 6.5"
        DeviceSize(device: "6.5inch", width: 1242, height: 2688),
        DeviceSize(device: "6.5inch", width: 2688, height: 1242),
        DeviceSize(device: "6.5inch", width: 1284, height: 2778),
        DeviceSize(device: "6.5inch", width: 2778, height: 1284),
        // iPhone 5.5"
        DeviceSize(device: "5.5inch", width: 1242, height: 2208),
        DeviceSize(device: "5.5inch", width: 2208, height: 1242),
        // iPad 12.9"
        DeviceSize(device: "ipad_12.9inch", width: 2048, height: 2732),
        DeviceSize(device: "ipad_12.9inch", width: 2732, height: 2048),
    ]

    /// App preview VIDEO resolutions — **different** from the screenshot sizes.
    /// https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/
    public static let videos: [DeviceSize] = [
        // iPhone 6.7" / 6.9"
        DeviceSize(device: "6.7inch", width: 886, height: 1920),
        DeviceSize(device: "6.7inch", width: 1920, height: 886),
        // iPhone 6.5"
        DeviceSize(device: "6.5inch", width: 886, height: 1920),
        DeviceSize(device: "6.5inch", width: 1920, height: 886),
        // iPhone 5.5"
        DeviceSize(device: "5.5inch", width: 1080, height: 1920),
        DeviceSize(device: "5.5inch", width: 1920, height: 1080),
        // iPad 12.9"
        DeviceSize(device: "ipad_12.9inch", width: 1200, height: 1600),
        DeviceSize(device: "ipad_12.9inch", width: 1600, height: 1200),
    ]

    private static func table(for kind: AssetSizeKind) -> [DeviceSize] {
        switch kind {
        case .screenshot: return screenshots
        case .video:      return videos
        }
    }

    public static func sizes(
        for device: AppleDevice,
        kind: AssetSizeKind = .screenshot
    ) -> [DeviceSize] {
        table(for: kind).filter { $0.device == device.rawValue }
    }

    public static func sizes(
        for devices: [AppleDevice],
        kind: AssetSizeKind = .screenshot
    ) -> [DeviceSize] {
        devices.flatMap { sizes(for: $0, kind: kind) }
    }
}

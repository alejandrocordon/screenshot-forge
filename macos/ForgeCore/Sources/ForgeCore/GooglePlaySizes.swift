import Foundation

/// Google Play devices this tool targets (matches `sizes.py`).
public enum GooglePlayDevice: String, CaseIterable, Identifiable, Sendable {
    case phone = "phone"
    case sevenInchTablet = "7inch_tablet"
    case tenInchTablet = "10inch_tablet"
    case chromebook = "chromebook"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .phone:           return "Phone"
        case .sevenInchTablet: return "7\" Tablet"
        case .tenInchTablet:   return "10\" Tablet"
        case .chromebook:      return "Chromebook"
        }
    }
}

/// Google Play screenshot sizes — ported from `sizes.py`.
///
/// Google Play accepts **screenshots** as file uploads; promo videos are a
/// YouTube URL, not a file, so there is no video table here.
public enum GooglePlaySizes {
    public static let screenshots: [DeviceSize] = [
        // Phone
        DeviceSize(device: "phone", width: 1080, height: 1920),
        DeviceSize(device: "phone", width: 1920, height: 1080),
        // 7" tablet
        DeviceSize(device: "7inch_tablet", width: 1200, height: 1920),
        DeviceSize(device: "7inch_tablet", width: 1920, height: 1200),
        // 10" tablet
        DeviceSize(device: "10inch_tablet", width: 1600, height: 2560),
        DeviceSize(device: "10inch_tablet", width: 2560, height: 1600),
        // Chromebook (landscape only)
        DeviceSize(device: "chromebook", width: 1920, height: 1080),
    ]

    public static func sizes(for device: GooglePlayDevice) -> [DeviceSize] {
        screenshots.filter { $0.device == device.rawValue }
    }

    public static func sizes(for devices: [GooglePlayDevice]) -> [DeviceSize] {
        devices.flatMap { sizes(for: $0) }
    }
}

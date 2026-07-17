import Foundation

/// Maps App Store Connect `screenshotDisplayType` values to the screenshot size
/// we crop to. Only the display types this tool targets are mapped.
public enum ScreenshotDisplayType {
    public static func size(for displayType: String) -> DeviceSize? {
        switch displayType {
        case "APP_IPHONE_67":
            return DeviceSize(device: "6.7inch", width: 1290, height: 2796)
        case "APP_IPHONE_65":
            return DeviceSize(device: "6.5inch", width: 1242, height: 2688)
        case "APP_IPHONE_55":
            return DeviceSize(device: "5.5inch", width: 1242, height: 2208)
        case "APP_IPAD_PRO_3GEN_129", "APP_IPAD_PRO_129":
            return DeviceSize(device: "ipad_12.9inch", width: 2048, height: 2732)
        default:
            return nil
        }
    }
}

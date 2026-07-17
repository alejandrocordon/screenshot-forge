import XCTest
@testable import ForgeCore

final class ScreenshotDisplayTypeTests: XCTestCase {

    func testKnownDisplayTypes() {
        XCTAssertEqual(ScreenshotDisplayType.size(for: "APP_IPHONE_67")?.fileTag, "1290x2796")
        XCTAssertEqual(ScreenshotDisplayType.size(for: "APP_IPHONE_65")?.device, "6.5inch")
        XCTAssertEqual(ScreenshotDisplayType.size(for: "APP_IPHONE_55")?.fileTag, "1242x2208")
        XCTAssertEqual(ScreenshotDisplayType.size(for: "APP_IPAD_PRO_129")?.fileTag, "2048x2732")
        XCTAssertEqual(ScreenshotDisplayType.size(for: "APP_IPAD_PRO_3GEN_129")?.fileTag, "2048x2732")
    }

    func testUnknownDisplayTypeIsNil() {
        XCTAssertNil(ScreenshotDisplayType.size(for: "APP_WATCH_ULTRA"))
        XCTAssertNil(ScreenshotDisplayType.size(for: ""))
    }
}

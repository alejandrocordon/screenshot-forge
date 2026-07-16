import XCTest
@testable import ForgeCore

final class AppleSizesTests: XCTestCase {

    func testScreenshotCounts() {
        // Default kind is .screenshot.
        XCTAssertEqual(AppleSizes.sizes(for: .iphone67).count, 2)
        XCTAssertEqual(AppleSizes.sizes(for: .iphone65).count, 4)
        XCTAssertEqual(AppleSizes.sizes(for: .iphone55).count, 2)
        XCTAssertEqual(AppleSizes.sizes(for: .ipad129).count, 2)
        XCTAssertEqual(AppleSizes.screenshots.count, 10)
    }

    func testVideoCounts() {
        XCTAssertEqual(AppleSizes.sizes(for: .iphone67, kind: .video).count, 2)
        XCTAssertEqual(AppleSizes.sizes(for: .iphone65, kind: .video).count, 2)
        XCTAssertEqual(AppleSizes.sizes(for: .iphone55, kind: .video).count, 2)
        XCTAssertEqual(AppleSizes.sizes(for: .ipad129, kind: .video).count, 2)
        XCTAssertEqual(AppleSizes.videos.count, 8)
    }

    func testVideoResolutionsMatchAppleSpec() {
        // https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/
        let v67 = AppleSizes.sizes(for: .iphone67, kind: .video)
        XCTAssertTrue(v67.contains(DeviceSize(device: "6.7inch", width: 886, height: 1920)))
        XCTAssertTrue(v67.contains(DeviceSize(device: "6.7inch", width: 1920, height: 886)))

        let v65 = AppleSizes.sizes(for: .iphone65, kind: .video)
        XCTAssertTrue(v65.contains(DeviceSize(device: "6.5inch", width: 886, height: 1920)))

        let v55 = AppleSizes.sizes(for: .iphone55, kind: .video)
        XCTAssertTrue(v55.contains(DeviceSize(device: "5.5inch", width: 1080, height: 1920)))
        XCTAssertTrue(v55.contains(DeviceSize(device: "5.5inch", width: 1920, height: 1080)))

        let vpad = AppleSizes.sizes(for: .ipad129, kind: .video)
        XCTAssertTrue(vpad.contains(DeviceSize(device: "ipad_12.9inch", width: 1200, height: 1600)))
        XCTAssertTrue(vpad.contains(DeviceSize(device: "ipad_12.9inch", width: 1600, height: 1200)))
    }

    func testScreenshotAndVideoSizesDiffer() {
        // A video must never be exported at a screenshot resolution.
        let screenshotDims = Set(AppleSizes.screenshots.map { PixelSize(width: $0.width, height: $0.height) })
        for video in AppleSizes.videos {
            XCTAssertFalse(
                screenshotDims.contains(PixelSize(width: video.width, height: video.height)),
                "video size \(video.fileTag) must differ from every screenshot size"
            )
        }
    }

    func testIdsAreUnique() {
        let combined = AppleSizes.screenshots + AppleSizes.videos
        let ids = Set(combined.map(\.id))
        XCTAssertEqual(ids.count, combined.count)
    }

    func testFileTagFormat() {
        let size = DeviceSize(device: "6.7inch", width: 886, height: 1920)
        XCTAssertEqual(size.fileTag, "886x1920")
        XCTAssertEqual(size.id, "6.7inch-886x1920")
    }

    func testSizesForMultipleDevicesPreserveOrder() {
        let sizes = AppleSizes.sizes(for: [.iphone67, .ipad129])
        XCTAssertEqual(sizes.count, 4)
        XCTAssertEqual(sizes.first?.device, "6.7inch")
        XCTAssertEqual(sizes.last?.device, "ipad_12.9inch")
    }
}

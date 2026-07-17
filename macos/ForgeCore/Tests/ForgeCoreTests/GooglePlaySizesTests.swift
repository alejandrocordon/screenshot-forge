import XCTest
@testable import ForgeCore

final class GooglePlaySizesTests: XCTestCase {

    func testDeviceCounts() {
        XCTAssertEqual(GooglePlaySizes.sizes(for: .phone).count, 2)
        XCTAssertEqual(GooglePlaySizes.sizes(for: .sevenInchTablet).count, 2)
        XCTAssertEqual(GooglePlaySizes.sizes(for: .tenInchTablet).count, 2)
        XCTAssertEqual(GooglePlaySizes.sizes(for: .chromebook).count, 1) // landscape only
        XCTAssertEqual(GooglePlaySizes.screenshots.count, 7)
    }

    func testKnownResolutions() {
        let phone = GooglePlaySizes.sizes(for: .phone)
        XCTAssertTrue(phone.contains(DeviceSize(device: "phone", width: 1080, height: 1920)))
        XCTAssertTrue(phone.contains(DeviceSize(device: "phone", width: 1920, height: 1080)))

        let ten = GooglePlaySizes.sizes(for: .tenInchTablet)
        XCTAssertTrue(ten.contains(DeviceSize(device: "10inch_tablet", width: 1600, height: 2560)))
    }

    func testIdsAreUnique() {
        let ids = Set(GooglePlaySizes.screenshots.map(\.id))
        XCTAssertEqual(ids.count, GooglePlaySizes.screenshots.count)
    }

    func testEveryPlanIsValidForAPhoneSource() {
        let source = PixelSize(width: 1179, height: 2556)
        for size in GooglePlaySizes.screenshots {
            let plan = CropGeometry.plan(source: source, target: size.pixelSize)
            XCTAssertEqual(plan.output, size.pixelSize)
            XCTAssertGreaterThanOrEqual(plan.scaled.width, size.width)
            XCTAssertGreaterThanOrEqual(plan.scaled.height, size.height)
        }
    }
}

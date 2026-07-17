import XCTest
@testable import ForgeCore

final class CropGeometryTests: XCTestCase {

    func testOutputIsExactTarget() {
        let plan = CropGeometry.plan(
            source: PixelSize(width: 1280, height: 720),
            target: PixelSize(width: 1290, height: 2796)
        )
        XCTAssertEqual(plan.output, PixelSize(width: 1290, height: 2796))
    }

    func testScaledSizeFullyCoversTarget() {
        let plan = CropGeometry.plan(
            source: PixelSize(width: 1280, height: 720),
            target: PixelSize(width: 1290, height: 2796)
        )
        XCTAssertGreaterThanOrEqual(plan.scaled.width, 1290)
        XCTAssertGreaterThanOrEqual(plan.scaled.height, 2796)
    }

    func testCropWindowFitsInsideScaledImage() {
        let plan = CropGeometry.plan(
            source: PixelSize(width: 1280, height: 720),
            target: PixelSize(width: 1290, height: 2796)
        )
        XCTAssertGreaterThanOrEqual(plan.cropX, 0)
        XCTAssertGreaterThanOrEqual(plan.cropY, 0)
        XCTAssertLessThanOrEqual(plan.cropX + plan.output.width, plan.scaled.width)
        XCTAssertLessThanOrEqual(plan.cropY + plan.output.height, plan.scaled.height)
    }

    func testCenteredHorizontalCrop() {
        // 1000x1000 -> 100x200: scale = max(0.1, 0.2) = 0.2 -> 200x200 scaled,
        // horizontal crop centered (50 px each side), no vertical crop.
        let plan = CropGeometry.plan(
            source: PixelSize(width: 1000, height: 1000),
            target: PixelSize(width: 100, height: 200)
        )
        XCTAssertEqual(plan.scaled, PixelSize(width: 200, height: 200))
        XCTAssertEqual(plan.cropX, 50)
        XCTAssertEqual(plan.cropY, 0)
    }

    func testKeptRegionFullWhenAspectsMatch() {
        // Same aspect ratio → nothing is cropped.
        let region = CropGeometry.keptRegion(
            source: PixelSize(width: 1000, height: 2000),
            target: PixelSize(width: 500, height: 1000)
        )
        XCTAssertEqual(region, NormalizedRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testKeptRegionCropsWidthForTallerTarget() {
        // Square source, tall target → keep full height, centered narrow slice.
        let region = CropGeometry.keptRegion(
            source: PixelSize(width: 1000, height: 1000),
            target: PixelSize(width: 100, height: 200)
        )
        XCTAssertEqual(region.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(region.height, 1.0, accuracy: 0.0001)
        XCTAssertEqual(region.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(region.y, 0.0, accuracy: 0.0001)
    }

    func testKeptRegionCropsHeightForWiderTarget() {
        // Square source, wide target → keep full width, centered short band.
        let region = CropGeometry.keptRegion(
            source: PixelSize(width: 1000, height: 1000),
            target: PixelSize(width: 200, height: 100)
        )
        XCTAssertEqual(region.width, 1.0, accuracy: 0.0001)
        XCTAssertEqual(region.height, 0.5, accuracy: 0.0001)
        XCTAssertEqual(region.x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(region.y, 0.25, accuracy: 0.0001)
    }

    func testEveryAppleSizeProducesAValidPlan() {
        let source = PixelSize(width: 1179, height: 2556) // iPhone 15 screenshot
        for size in AppleSizes.screenshots + AppleSizes.videos {
            let plan = CropGeometry.plan(source: source, target: size.pixelSize)
            XCTAssertEqual(plan.output, size.pixelSize, "output must equal target for \(size.id)")
            XCTAssertGreaterThanOrEqual(plan.scaled.width, size.width, "must cover width for \(size.id)")
            XCTAssertGreaterThanOrEqual(plan.scaled.height, size.height, "must cover height for \(size.id)")
            XCTAssertGreaterThanOrEqual(plan.cropX, 0)
            XCTAssertGreaterThanOrEqual(plan.cropY, 0)
        }
    }
}

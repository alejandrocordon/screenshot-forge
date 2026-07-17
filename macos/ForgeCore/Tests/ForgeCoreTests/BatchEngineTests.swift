#if canImport(CoreGraphics) && canImport(AVFoundation) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ForgeCore

final class BatchEngineTests: XCTestCase {

    func testExportsScreenshotsWithExactSizesAndNames() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // A synthetic landscape source that must be cover-cropped to portrait.
        let source = tmp.appendingPathComponent("home.png")
        try Self.writeSolidPNG(width: 1200, height: 900, to: source)

        let outputRoot = tmp.appendingPathComponent("out", isDirectory: true)
        let engine = BatchEngine()

        var outcome: BatchOutcome?
        for await event in engine.run(
            inputs: [source],
            appleDevices: [.iphone67],
            googlePlayDevices: [],
            outputRoot: outputRoot
        ) {
            if case .finished(let value) = event { outcome = value }
        }

        // 6.7" has two sizes (portrait + landscape).
        XCTAssertEqual(outcome?.processed, 2)
        XCTAssertEqual(outcome?.failures.count, 0)

        let portrait = outputRoot.appendingPathComponent("ios/6.7inch/home_1290x2796.png")
        let landscape = outputRoot.appendingPathComponent("ios/6.7inch/home_2796x1290.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: portrait.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: landscape.path))
        XCTAssertEqual(Self.pixelSize(of: portrait), PixelSize(width: 1290, height: 2796))
        XCTAssertEqual(Self.pixelSize(of: landscape), PixelSize(width: 2796, height: 1290))
    }

    func testAndroidGoesToAndroidFolder() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("s.png")
        try Self.writeSolidPNG(width: 1000, height: 1000, to: source)

        let outputRoot = tmp.appendingPathComponent("out", isDirectory: true)
        let engine = BatchEngine()
        for await _ in engine.run(
            inputs: [source], appleDevices: [], googlePlayDevices: [.chromebook],
            outputRoot: outputRoot
        ) {}

        let file = outputRoot.appendingPathComponent("android/chromebook/s_1920x1080.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("ios").path))
    }

    // MARK: - Helpers

    static func writeSolidPNG(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ForgeError.renderFailed(url) }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ForgeError.renderFailed(url) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ForgeError.renderFailed(url) }
    }

    static func pixelSize(of url: URL) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return PixelSize(width: image.width, height: image.height)
    }
}
#endif

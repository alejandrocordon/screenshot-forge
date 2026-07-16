import Foundation

/// A width × height in whole pixels.
public struct PixelSize: Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var isLandscape: Bool { width >= height }
}

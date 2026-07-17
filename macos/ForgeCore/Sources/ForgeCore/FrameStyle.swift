import Foundation

/// Look of the device bezel drawn around a framed screenshot. Fractions are of
/// the target's shorter side, so a frame scales with the output size.
///
/// This is a simple *frameless* rounded bezel (no external mockup assets). Real
/// per-device frame PNGs can be layered on later — see `BezelRenderer`.
public struct FrameStyle: Sendable {
    /// Bezel thickness as a fraction of the shorter side.
    public var bezelFraction: Double
    /// Outer corner radius as a fraction of the shorter side.
    public var outerCornerFraction: Double
    /// Bezel colour as a 0…1 gray value.
    public var bezelGray: Double

    public init(
        bezelFraction: Double = 0.022,
        outerCornerFraction: Double = 0.09,
        bezelGray: Double = 0.06
    ) {
        self.bezelFraction = bezelFraction
        self.outerCornerFraction = outerCornerFraction
        self.bezelGray = bezelGray
    }

    public static let phone = FrameStyle()
}

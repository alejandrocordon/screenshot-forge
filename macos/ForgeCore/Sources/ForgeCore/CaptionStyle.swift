import Foundation

/// Look of a marketing caption drawn above the screenshot. Fractions are of the
/// target's dimensions so it scales with the output size.
public struct CaptionStyle: Sendable {
    /// Height of the title band as a fraction of the target height.
    public var titleAreaFraction: Double
    /// Font size as a fraction of the target's shorter side.
    public var fontSizeFraction: Double
    /// Background gray (0…1) filling the whole canvas.
    public var backgroundGray: Double
    /// Title text gray (0…1).
    public var textGray: Double

    public init(
        titleAreaFraction: Double = 0.22,
        fontSizeFraction: Double = 0.052,
        backgroundGray: Double = 0.10,
        textGray: Double = 0.96
    ) {
        self.titleAreaFraction = titleAreaFraction
        self.fontSizeFraction = fontSizeFraction
        self.backgroundGray = backgroundGray
        self.textGray = textGray
    }

    public static let standard = CaptionStyle()
}

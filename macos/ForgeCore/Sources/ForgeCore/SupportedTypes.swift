import Foundation

public enum AssetKind: Sendable {
    case image
    case video
}

/// Which file extensions the engine knows how to crop.
public enum SupportedTypes {
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif"]
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// The asset kind for a URL, or `nil` if the extension isn't supported.
    public static func kind(of url: URL) -> AssetKind? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        return nil
    }
}

import Foundation

public enum ForgeError: Error, LocalizedError {
    case unsupportedFile(URL)
    case imageDecodeFailed(URL)
    case renderFailed(URL)
    case videoHasNoVideoTrack(URL)
    case videoExportFailed(URL, String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let u):
            return "Unsupported file: \(u.lastPathComponent)"
        case .imageDecodeFailed(let u):
            return "Could not decode image: \(u.lastPathComponent)"
        case .renderFailed(let u):
            return "Could not render output: \(u.lastPathComponent)"
        case .videoHasNoVideoTrack(let u):
            return "No video track in: \(u.lastPathComponent)"
        case .videoExportFailed(let u, let message):
            return "Video export failed for \(u.lastPathComponent): \(message)"
        case .cancelled:
            return "Cancelled."
        }
    }
}

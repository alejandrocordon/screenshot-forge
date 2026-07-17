import Foundation
import SwiftData
import ForgeCore

/// A managed app with its screenshots and preview videos — persisted with
/// SwiftData so the library survives relaunches.
@Model
final class AppProject {
    var name: String
    var createdAt: Date

    // Deleting a project deletes its assets. `inverse:` points at Asset.project.
    @Relationship(deleteRule: .cascade, inverse: \Asset.project)
    var assets: [Asset]

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.assets = []
    }

    var sortedAssets: [Asset] { assets.sorted { $0.addedAt < $1.addedAt } }
    var screenshots: [Asset] { assets.filter { $0.kind == .image } }
    var videos: [Asset] { assets.filter { $0.kind == .video } }
}

/// A single imported file (screenshot or video). We store a **bookmark** rather
/// than a raw path so access survives the file being moved and, if the app is
/// sandboxed, survives relaunch (security-scoped bookmark).
@Model
final class Asset {
    var fileName: String
    /// Persisted as a string; exposed as `AssetKind` below.
    private var kindRaw: String
    var bookmark: Data?
    var addedAt: Date
    var project: AppProject?

    init(fileName: String, kind: AssetKind, bookmark: Data?, addedAt: Date = .now) {
        self.fileName = fileName
        self.kindRaw = (kind == .video) ? "video" : "image"
        self.bookmark = bookmark
        self.addedAt = addedAt
    }

    var kind: AssetKind { kindRaw == "video" ? .video : .image }

    /// Resolve the stored bookmark to a usable URL. If the bookmark carries a
    /// security scope, this starts it — the caller must call
    /// `stopAccessingSecurityScopedResource()` on the URL when `started` is true.
    func resolvedURL() -> (url: URL, started: Bool)? {
        guard let bookmark else { return nil }
        return BookmarkStore.resolve(bookmark)
    }
}

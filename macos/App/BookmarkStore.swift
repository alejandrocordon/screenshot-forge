import Foundation

/// Creates and resolves file bookmarks so imported assets keep working across
/// relaunches (and across file moves). Prefers **security-scoped** bookmarks,
/// which are required if the app is sandboxed, and transparently falls back to
/// plain bookmarks when it isn't — so the same code works in both modes.
enum BookmarkStore {

    /// Make a bookmark for a user-picked file.
    static func makeBookmark(for url: URL) -> Data? {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        // Non-sandboxed apps can't always make security-scoped bookmarks.
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolve a bookmark back to a URL. Returns whether a security scope was
    /// started (the caller is responsible for stopping it).
    static func resolve(_ data: Data) -> (url: URL, started: Bool)? {
        var isStale = false

        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            let started = url.startAccessingSecurityScopedResource()
            return (url, started)
        }
        // Plain (non-security-scoped) bookmark.
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return (url, false)
        }
        return nil
    }
}

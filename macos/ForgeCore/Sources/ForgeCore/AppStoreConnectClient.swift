#if canImport(CryptoKit)
import Foundation
import CryptoKit

public struct AppStoreConnectError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Thin App Store Connect API client. The authorization (ES256 JWT) is complete
/// and `listApps()` works as a credentials check. The screenshot upload is the
/// documented three-step flow, stubbed with the exact requests to make — finish
/// and test it with real credentials.
public final class AppStoreConnectClient {
    private let credentials: AppStoreConnectCredentials
    private let session: URLSession
    private let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!

    public init(credentials: AppStoreConnectCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    /// Verify the credentials by listing the account's apps.
    public func listApps() async throws -> Data {
        let request = try authorizedRequest("/v1/apps?limit=5")
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
        return data
    }

    /// Upload a screenshot to an existing App Store screenshot set.
    ///
    /// Steps (per the App Store Connect API):
    /// 1. **Reserve** — `POST /v1/appScreenshots` with `fileName`, `fileSize` and
    ///    a relationship to `appScreenshotSet` (id = `screenshotSetID`). The
    ///    response's `attributes.uploadOperations` lists the parts to PUT
    ///    (`method`, `url`, `length`, `offset`, `requestHeaders`).
    /// 2. **Upload** — for each operation, PUT that byte range of the file to
    ///    `url` with the provided headers.
    /// 3. **Commit** — `PATCH /v1/appScreenshots/{id}` with
    ///    `attributes.uploaded = true` and `sourceFileChecksum` = the file's MD5.
    public func uploadScreenshot(fileURL: URL, toScreenshotSetID screenshotSetID: String) async throws {
        _ = fileURL
        _ = screenshotSetID
        throw AppStoreConnectError(
            message: "uploadScreenshot is a scaffold — implement steps 1–3 and test with real credentials."
        )
    }

    // MARK: - Helpers

    private func authorizedRequest(_ path: String, method: String = "GET") throws -> URLRequest {
        let token = try AppStoreConnectAuth.makeToken(credentials)
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreConnectError(message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AppStoreConnectError(message: "HTTP \(http.statusCode): \(body)")
        }
    }
}
#endif

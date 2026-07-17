#if canImport(CryptoKit)
import Foundation
import CryptoKit

public struct AppStoreConnectError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// An app as returned by the App Store Connect API.
public struct ASCApp: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
}

/// App Store Connect API client. Authorization (ES256 JWT) is complete and
/// tested; `apps()` verifies credentials; `uploadScreenshot`/`uploadPreview`
/// implement the full reserve → upload → commit flow.
///
/// What's still manual: resolving *which* screenshot/preview set to upload to
/// (app → version → localization → set) — pass the set id in for now.
public final class AppStoreConnectClient: @unchecked Sendable {
    private let credentials: AppStoreConnectCredentials
    private let session: URLSession
    private let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!

    public init(credentials: AppStoreConnectCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: - Credentials check

    /// List the account's apps — a simple way to verify the credentials work.
    public func apps(limit: Int = 100) async throws -> [ASCApp] {
        let data = try await get("/v1/apps?limit=\(limit)")
        return try JSONDecoder().decode(AppsResponse.self, from: data).data.map {
            ASCApp(id: $0.id, name: $0.attributes.name)
        }
    }

    // MARK: - Navigation (app → version → localization → set)

    public func versions(appID: String) async throws -> [ASCVersion] {
        let data = try await get("/v1/apps/\(appID)/appStoreVersions?limit=50")
        return try JSONDecoder().decode(VersionsResponse.self, from: data).data.map {
            ASCVersion(id: $0.id, versionString: $0.attributes.versionString,
                       state: $0.attributes.appStoreState ?? "")
        }
    }

    public func localizations(versionID: String) async throws -> [ASCLocalization] {
        let data = try await get("/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=100")
        return try JSONDecoder().decode(LocalizationsResponse.self, from: data).data.map {
            ASCLocalization(id: $0.id, locale: $0.attributes.locale)
        }
    }

    public func screenshotSets(localizationID: String) async throws -> [ASCScreenshotSet] {
        let data = try await get("/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets?limit=50")
        return try JSONDecoder().decode(ScreenshotSetsResponse.self, from: data).data.map {
            ASCScreenshotSet(id: $0.id, displayType: $0.attributes.screenshotDisplayType)
        }
    }

    // MARK: - Uploads

    /// Upload a screenshot to an existing `appScreenshotSet`.
    public func uploadScreenshot(fileURL: URL, toScreenshotSetID setID: String) async throws {
        try await uploadAsset(
            fileURL: fileURL,
            reserveType: "appScreenshots",
            relationshipKey: "appScreenshotSet",
            relationshipType: "appScreenshotSets",
            setID: setID,
            extraCommitAttributes: [:]
        )
    }

    /// Upload an app preview video to an existing `appPreviewSet`.
    /// `previewFrameTimeCode` (e.g. `"00:00:02:00"`) sets the poster frame.
    public func uploadPreview(
        fileURL: URL,
        toPreviewSetID setID: String,
        previewFrameTimeCode: String? = nil
    ) async throws {
        var extra: [String: Any] = [:]
        if let previewFrameTimeCode { extra["previewFrameTimeCode"] = previewFrameTimeCode }
        try await uploadAsset(
            fileURL: fileURL,
            reserveType: "appPreviews",
            relationshipKey: "appPreviewSet",
            relationshipType: "appPreviewSets",
            setID: setID,
            extraCommitAttributes: extra
        )
    }

    /// The shared reserve → upload → commit flow for screenshots and previews.
    private func uploadAsset(
        fileURL: URL,
        reserveType: String,
        relationshipKey: String,
        relationshipType: String,
        setID: String,
        extraCommitAttributes: [String: Any]
    ) async throws {
        let fileData = try Data(contentsOf: fileURL)

        // 1) Reserve.
        let reserveBody: [String: Any] = [
            "data": [
                "type": reserveType,
                "attributes": ["fileName": fileURL.lastPathComponent, "fileSize": fileData.count],
                "relationships": [
                    relationshipKey: ["data": ["type": relationshipType, "id": setID]],
                ],
            ],
        ]
        let reservationData = try await sendJSON("/v1/\(reserveType)", method: "POST", body: reserveBody)
        let reservation = try JSONDecoder().decode(ReservationResponse.self, from: reservationData)

        // 2) Upload each operation (the URLs are pre-signed — no bearer token).
        for operation in reservation.data.attributes.uploadOperations ?? [] {
            try await upload(operation: operation, fileData: fileData)
        }

        // 3) Commit with the file checksum.
        var attributes: [String: Any] = [
            "uploaded": true,
            "sourceFileChecksum": Self.md5Hex(fileData),
        ]
        attributes.merge(extraCommitAttributes) { _, new in new }
        let commitBody: [String: Any] = [
            "data": ["type": reserveType, "id": reservation.data.id, "attributes": attributes],
        ]
        _ = try await sendJSON("/v1/\(reserveType)/\(reservation.data.id)", method: "PATCH", body: commitBody)
    }

    private func upload(operation: UploadOperation, fileData: Data) async throws {
        guard let url = URL(string: operation.url) else {
            throw AppStoreConnectError(message: "Invalid upload URL")
        }
        let end = operation.offset + operation.length
        guard end <= fileData.count else {
            throw AppStoreConnectError(message: "Upload operation exceeds file size")
        }
        let chunk = fileData.subdata(in: operation.offset ..< end)

        var request = URLRequest(url: url)
        request.httpMethod = operation.method
        for header in operation.requestHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        let (data, response) = try await session.upload(for: request, from: chunk)
        try Self.check(response, data)
    }

    // MARK: - HTTP helpers

    private func authorizedRequest(_ path: String, method: String = "GET") throws -> URLRequest {
        let token = try AppStoreConnectAuth.makeToken(credentials)
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func get(_ path: String) async throws -> Data {
        let request = try authorizedRequest(path)
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
        return data
    }

    private func sendJSON(_ path: String, method: String, body: [String: Any]) async throws -> Data {
        var request = try authorizedRequest(path, method: method)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
        return data
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

    static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Wire models

struct AppsResponse: Decodable {
    struct App: Decodable {
        let id: String
        let attributes: Attributes
        struct Attributes: Decodable { let name: String }
    }
    let data: [App]
}

struct ReservationResponse: Decodable {
    struct Datum: Decodable {
        let id: String
        let attributes: Attributes
        struct Attributes: Decodable {
            let uploadOperations: [UploadOperation]?
        }
    }
    let data: Datum
}

public struct UploadOperation: Decodable, Sendable {
    public let method: String
    public let url: String
    public let length: Int
    public let offset: Int
    public let requestHeaders: [Header]

    public struct Header: Decodable, Sendable {
        public let name: String
        public let value: String
    }
}

// Navigation models

public struct ASCVersion: Decodable, Sendable, Identifiable {
    public let id: String
    public let versionString: String
    public let state: String
}

public struct ASCLocalization: Decodable, Sendable, Identifiable {
    public let id: String
    public let locale: String
}

public struct ASCScreenshotSet: Decodable, Sendable, Identifiable {
    public let id: String
    public let displayType: String
}

struct VersionsResponse: Decodable {
    struct Version: Decodable {
        let id: String
        let attributes: Attributes
        struct Attributes: Decodable {
            let versionString: String
            let appStoreState: String?
        }
    }
    let data: [Version]
}

struct LocalizationsResponse: Decodable {
    struct Localization: Decodable {
        let id: String
        let attributes: Attributes
        struct Attributes: Decodable { let locale: String }
    }
    let data: [Localization]
}

struct ScreenshotSetsResponse: Decodable {
    struct ScreenshotSet: Decodable {
        let id: String
        let attributes: Attributes
        struct Attributes: Decodable { let screenshotDisplayType: String }
    }
    let data: [ScreenshotSet]
}
#endif

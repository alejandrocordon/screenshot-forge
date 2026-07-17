#if canImport(CryptoKit)
import Foundation
import CryptoKit

/// Credentials from an App Store Connect API key.
public struct AppStoreConnectCredentials: Sendable {
    public var issuerID: String
    public var keyID: String
    /// The full contents of the `AuthKey_XXXXXXXXXX.p8` file (PEM, including the
    /// `-----BEGIN PRIVATE KEY-----` header).
    public var privateKeyPEM: String

    public init(issuerID: String, keyID: String, privateKeyPEM: String) {
        self.issuerID = issuerID
        self.keyID = keyID
        self.privateKeyPEM = privateKeyPEM
    }
}

/// Builds the ES256 JWT the App Store Connect API expects. This is the concrete,
/// security-critical piece — it's covered by a unit test that verifies the
/// signature end-to-end with a throwaway key (no Apple account needed).
public enum AppStoreConnectAuth {

    /// A signed bearer token, valid for ~20 minutes.
    public static func makeToken(_ credentials: AppStoreConnectCredentials, now: Date = Date()) throws -> String {
        let header: [String: String] = [
            "alg": "ES256",
            "kid": credentials.keyID,
            "typ": "JWT",
        ]
        let issuedAt = Int(now.timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": credentials.issuerID,
            "iat": issuedAt,
            "exp": issuedAt + 20 * 60,
            "aud": "appstoreconnect-v1",
        ]

        let signingInput = try base64URL(json: header) + "." + base64URL(json: payload)
        let key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        let signature = try key.signature(for: Data(signingInput.utf8))
        return signingInput + "." + base64URL(signature.rawRepresentation)
    }

    // MARK: - base64url helpers

    private static func base64URL(json object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
#endif

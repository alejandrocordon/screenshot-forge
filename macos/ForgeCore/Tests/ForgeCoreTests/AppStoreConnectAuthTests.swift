#if canImport(CryptoKit)
import XCTest
import CryptoKit
@testable import ForgeCore

final class AppStoreConnectAuthTests: XCTestCase {

    func testTokenIsAValidES256JWT() throws {
        let key = P256.Signing.PrivateKey()
        let creds = AppStoreConnectCredentials(
            issuerID: "issuer-uuid",
            keyID: "ABC123DEF4",
            privateKeyPEM: key.pemRepresentation
        )

        let token = try AppStoreConnectAuth.makeToken(
            creds, now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let parts = token.split(separator: ".").map(String.init)
        XCTAssertEqual(parts.count, 3)

        // Header
        let header = try json(parts[0])
        XCTAssertEqual(header["alg"] as? String, "ES256")
        XCTAssertEqual(header["kid"] as? String, "ABC123DEF4")
        XCTAssertEqual(header["typ"] as? String, "JWT")

        // Payload
        let payload = try json(parts[1])
        XCTAssertEqual(payload["iss"] as? String, "issuer-uuid")
        XCTAssertEqual(payload["aud"] as? String, "appstoreconnect-v1")
        let iat = try XCTUnwrap(payload["iat"] as? Int)
        let exp = try XCTUnwrap(payload["exp"] as? Int)
        XCTAssertEqual(exp - iat, 1200) // 20 minutes

        // The signature must verify against the key's public half.
        let signingInput = "\(parts[0]).\(parts[1])"
        let sigData = try XCTUnwrap(Data(base64URL: parts[2]))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: sigData)
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: Data(signingInput.utf8)))
    }

    private func json(_ base64URL: String) throws -> [String: Any] {
        let data = try XCTUnwrap(Data(base64URL: base64URL))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private extension Data {
    /// Decode a base64url string (JWT segments have no padding).
    init?(base64URL string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        self.init(base64Encoded: s)
    }
}
#endif

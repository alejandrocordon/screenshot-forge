#if canImport(CryptoKit)
import XCTest
@testable import ForgeCore

final class AppStoreConnectClientTests: XCTestCase {

    func testMD5HexMatchesKnownVector() {
        // MD5("abc") = 900150983cd24fb0d6963f7d28e17f72
        XCTAssertEqual(
            AppStoreConnectClient.md5Hex(Data("abc".utf8)),
            "900150983cd24fb0d6963f7d28e17f72"
        )
    }

    func testDecodesReservationResponse() throws {
        let json = """
        {
          "data": {
            "id": "SS123",
            "type": "appScreenshots",
            "attributes": {
              "uploadOperations": [
                {
                  "method": "PUT",
                  "url": "https://upload.example/part1",
                  "length": 1024,
                  "offset": 0,
                  "requestHeaders": [
                    { "name": "Content-Type", "value": "image/png" }
                  ]
                }
              ]
            }
          }
        }
        """
        let reservation = try JSONDecoder().decode(ReservationResponse.self, from: Data(json.utf8))
        XCTAssertEqual(reservation.data.id, "SS123")

        let ops = try XCTUnwrap(reservation.data.attributes.uploadOperations)
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops[0].method, "PUT")
        XCTAssertEqual(ops[0].offset, 0)
        XCTAssertEqual(ops[0].length, 1024)
        XCTAssertEqual(ops[0].requestHeaders.first?.name, "Content-Type")
        XCTAssertEqual(ops[0].requestHeaders.first?.value, "image/png")
    }
}
#endif

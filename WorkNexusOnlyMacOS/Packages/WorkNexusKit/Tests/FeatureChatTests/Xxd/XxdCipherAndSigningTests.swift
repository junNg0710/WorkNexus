import XCTest
@testable import FeatureChat

/// Port of test/data/chat/xxd_cipher_test.dart. Vectors come from Node's `crypto.createCipheriv`.
final class XxdCipherAndSigningTests: XCTestCase {
    func testMatchesNodeVectors() throws {
        let fixture = try Fixtures.json("cipher_cases.json")
        let cipher = try XxdCipher(token: fixture["token"]!.string!)
        for c in fixture["cases"]!.array! {
            let plain = c["plain"]!.string!
            let expected = c["cipherBase64"]!.string!
            XCTAssertEqual(cipher.encrypt(plain).base64EncodedString(), expected, plain)
            XCTAssertEqual(try cipher.decrypt(Data(base64Encoded: expected)!), plain)
        }
    }

    func testRejectsShortToken() {
        XCTAssertThrowsError(try XxdCipher(token: "short"))
    }

    func testRejectsBadCiphertext() throws {
        let cipher = try XxdCipher(token: "0123456789abcdef0123456789abcdef")
        XCTAssertThrowsError(try cipher.decrypt(Data("not encrypted".utf8)))
        XCTAssertThrowsError(try cipher.decrypt(Data()))
        let other = try XxdCipher(token: "fedcba9876543210fedcba9876543210")
        XCTAssertThrowsError(try other.decrypt(cipher.encrypt("hello xxd")))
    }

    func testSigning() {
        XCTAssertEqual(XxdSigning.passwordAuthKey("123456"), "e10adc3949ba59abbe56e057f20f883e")
        XCTAssertEqual(XxdSigning.fileSid(sessionId: "c8d0sessionid", fileName: "image.png"), "3dbb5fa00a3f7f779b18992a98309077")
    }

    func testAuthorizeURLs() throws {
        var info = XxdServerInfo(token: "t", chatPort: 11444, version: "", enableClientAes: false)
        info.backendUrl = "https://zt.example.com/"
        info.authToken = "tok"
        let u1 = XxdBackend.authorizeURL(info, account: "thanh", module: "user", method: "cropAvatar", params: [("imageID", "42")])
        XCTAssertEqual(u1?.absoluteString, "https://zt.example.com/im-authorize-thanh-tok60ae136e5d49fbdf037fab5f1d805634-desktop-user_cropAvatar_42.html.html")
        info.authToken = String(repeating: "a", count: 64)
        let u2 = XxdBackend.authorizeURL(info, account: "thanh", module: "file", method: "uploadChatAvatar",
                                         now: Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(u2?.absoluteString, "https://zt.example.com/im-authorize-thanh-b0de6f721aa411f9f2bf70c91bb878075cbfc835197a6fcc2b935020eb72e89b-desktop-file_uploadChatAvatar.html.html")
        info.requestType = "GET"
        let u3 = XxdBackend.authorizeURL(info, account: "a b", module: "file", method: "x", params: [("k", "v")], now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(u3!.absoluteString.hasPrefix("https://zt.example.com/index.php?m=im&f=authorize&account=a%20b&token="))
    }

    func testUserAvatarFileId() {
        XCTAssertEqual(XxdBackend.userAvatarFileId(#"{"fileID":42}"#), "42")
        XCTAssertEqual(XxdBackend.userAvatarFileId(#"{"result":"success","callback":"user-cropavatar-77.html"}"#), "77")
        XCTAssertNil(XxdBackend.userAvatarFileId(#"{"result":"fail"}"#))
    }

    func testCertificateFingerprintFormat() {
        XCTAssertEqual(certificateFingerprint(der: Data([1, 2, 3])),
                       "03:90:58:C6:F2:C0:CB:49:2C:53:3B:0A:4D:14:EF:77:CC:0F:78:AB:CC:CE:D5:28:7D:84:A1:A2:01:1C:FB:81")
    }
}

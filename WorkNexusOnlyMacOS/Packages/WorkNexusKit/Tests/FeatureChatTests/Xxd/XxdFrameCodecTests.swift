import XCTest
@testable import FeatureChat

/// Port of test/data/chat/xxd_frame_codec_test.dart.
final class XxdFrameCodecTests: XCTestCase {
    let token = "0123456789abcdef0123456789abcdef"

    private func codec(serverName: String = "", aes: Bool = true) throws -> XxdFrameCodec {
        XxdFrameCodec(clientVersion: "9.1.2", lang: "vi", serverName: serverName,
                      scheme: ApiSchemeCodec(try Fixtures.json("api_scheme.json").object!),
                      cipher: aes ? try XxdCipher(token: token) : nil)
    }

    func testRequestsPackLikeTheJSClient() throws {
        let cases = try Fixtures.json("frame_cases.json")["cases"]!.array!
        for c in cases {
            let r = c["request"]!
            let req = XxdRequest(r["method"]!.string!, params: r["params"]?.array, rid: r["rid"]?.string, userId: r["userID"]?.intValue)
            XCTAssertEqual(try codec().encodeToText(req), c["text"]?.string, r["method"]!.string!)
        }
    }

    func testUserLoginIsPrefixedWithServerName() throws {
        let text = try codec(serverName: "srv").encodeToText(XxdRequest("userLogin", params: ["srv", "demo", "x", [:]]))
        XCTAssertTrue(text.hasPrefix(#"srv["userloginRequest""#))
    }

    func testChatTypingPacksNamedFields() throws {
        let text = try codec().encodeToText(XxdRequest("chattyping", fields: [("cgid", "31&40"), ("users", [31]), ("typing", true)], userId: 40))
        let packed = try JSONValue.parse(text)
        XCTAssertEqual(packed[0], "chattypingRequest")
        let scheme = ApiSchemeCodec(try Fixtures.json("api_scheme.json").object!)
        XCTAssertEqual(try scheme.decode(packed),
                       ["rid": "", "cgid": "31&40", "users": [31], "typing": true, "userID": 40])
    }

    func testEncryptedFramesDecryptBackToPackedText() throws {
        let c = try codec()
        let req = XxdRequest("ping", userId: 40)
        guard case .binary(let data) = try c.encode(req) else { return XCTFail("expected binary") }
        XCTAssertEqual(try XxdCipher(token: token).decrypt(data), try c.encodeToText(req))
    }

    func testWithoutSchemeRequestIsPlainJSON() throws {
        let c = XxdFrameCodec(clientVersion: "9.1.2", lang: "en")
        guard case .text(let t) = try c.encode(XxdRequest("ping", rid: "r1")) else { return XCTFail() }
        XCTAssertEqual(try JSONValue.parse(t), ["version": "9.1.2", "device": "desktop", "lang": "en", "method": "ping", "rid": "r1"])
        XCTAssertEqual(t, #"{"version":"9.1.2","device":"desktop","lang":"en","method":"ping","rid":"r1"}"#)
    }

    func testDecryptsAndUnpacksPushedMessageSend() throws {
        let cases = try Fixtures.json("codec_cases.json")["cases"]!.array!
        let c = cases.first { $0["name"]?.string == "messagesendResponse" && $0["variant"] == .int(0) }!
        let frame = XxdFrame.binary(try XxdCipher(token: token).encrypt(c["encoded"]!.serialized()))
        let packets = try codec().decode(frame)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(.object(packets[0].raw), c["decoded"])
        XCTAssertFalse(packets[0].apiName.isEmpty)
    }

    func testJSONArrayWithoutSchemeIsABatch() throws {
        let c = XxdFrameCodec(clientVersion: "9.1.2", lang: "en")
        let packets = try c.decode(.text(#"[{"method":"ping"},{"method":"chatGetList","result":"fail"}]"#))
        XCTAssertEqual(packets.map(\.apiName), ["ping", "chatgetlist"])
        XCTAssertEqual(packets.map(\.isSuccess), [true, false])
    }

    func testGarbageFramesRaiseProtocolError() throws {
        let c = try codec()
        XCTAssertThrowsError(try c.decode(.binary(Data("not encrypted".utf8)))) { XCTAssertTrue($0 is XxdProtocolError) }
        XCTAssertThrowsError(try c.decodeText("{oops")) { XCTAssertTrue($0 is XxdProtocolError) }
        XCTAssertThrowsError(try c.decodeText(#"["noSuchScheme", "not props"]"#)) { XCTAssertTrue($0 is XxdProtocolError) }
    }
}

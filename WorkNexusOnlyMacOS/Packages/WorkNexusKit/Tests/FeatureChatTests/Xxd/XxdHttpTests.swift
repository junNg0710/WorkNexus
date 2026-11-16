import CoreDomain
import XCTest
@testable import FeatureChat

/// Ports of the pure parts of test/data/chat/{xxd_http,xxd_backend}_test.dart (reply parsing, signed URLs, form encoding).
final class XxdHttpTests: XCTestCase {
    let http = XxdHttpDatasource(clientVersion: "9.1.2", lang: "vi")

    func testServerInfoParsing() throws {
        let ok = http.parseServerInfo(status: 200, data: Data(#"{"token":"0123456789abcdef0123456789abcdef","chatPort":"11445","version":"v9.2.2","enableClientAES":"1","apiScheme":{"$version":"1"},"uploadFileSize":10485760,"backendURL":"https://zt/","authToken":"tok","requestType":"GET","serverTime":1791345529,"authTokenAuthWindow":30,"socketUrl":""}"#.utf8)).value
        let info = try XCTUnwrap(ok)
        XCTAssertEqual(info.chatPort, 11445); XCTAssertTrue(info.enableClientAes); XCTAssertEqual(info.uploadFileSize, 10_485_760)
        XCTAssertEqual(info.requestType, "GET"); XCTAssertEqual(info.authTokenWindow, 30); XCTAssertNil(info.socketUrl)
        XCTAssertEqual(info.serverTime, Date(timeIntervalSince1970: 1_791_345_529)); XCTAssertEqual(info.apiScheme?["$version"], "1")
        XCTAssertEqual(info.socketURL(server: URL(string: "https://zt.example.com:11443")!)?.absoluteString, "wss://zt.example.com:11445/ws")
        var custom = info; custom.socketUrl = "wss://other:1/ws"
        XCTAssertEqual(custom.socketURL(server: URL(string: "https://a")!)?.absoluteString, "wss://other:1/ws")
        XCTAssertEqual(XxdServerInfo.tryParse(["token": "t", "serverTime": .int(1_791_345_529_000)])?.serverTime, Date(timeIntervalSince1970: 1_791_345_529))
        XCTAssertNil(XxdServerInfo.tryParse(["token": ""]))
    }

    func testServerInfoFailuresAreMapped() {
        XCTAssertEqual(http.parseServerInfo(status: 200, data: Data(#"{"message":"bad account"}"#.utf8)).failure, .auth("bad account"))
        XCTAssertEqual(http.parseServerInfo(status: 403, data: Data("{}".utf8)).failure, .auth("Chat login rejected (HTTP 403)"))
        XCTAssertEqual(http.parseServerInfo(status: 502, data: Data("<html>".utf8)).failure, .parse("Chat server returned non-JSON (HTTP 502)"))
        XCTAssertEqual(http.parseServerInfo(status: 200, data: Data("[1]".utf8)).failure, .parse("Unexpected serverInfo reply (HTTP 200)"))
    }

    func testUploadReplyParsing() {
        XCTAssertEqual(http.parseUpload(status: 200, data: Data(#"{"id":12,"time":1790842835}"#.utf8)).value?.id, 12)
        XCTAssertEqual(http.parseUpload(status: 200, data: Data(#"{"id":12,"time":1790842835}"#.utf8)).value?.time, 1_790_842_835_000)
        XCTAssertEqual(http.parseUpload(status: 200, data: Data(#"{"result":"success","data":{"id":"13","time":1790842835123}}"#.utf8)).value?.time, 1_790_842_835_123)
        XCTAssertEqual(http.parseUpload(status: 413, data: Data(#"{"message":"too big"}"#.utf8)).failure, .network("too big"))
        XCTAssertEqual(http.parseUpload(status: 500, data: Data("oops".utf8)).failure, .network("Upload rejected (HTTP 500)"))
    }

    func testFileDownloadURLIsSigned() throws {
        let url = http.fileDownloadURL(server: URL(string: "https://zt.test:11443")!, userId: 40, sessionId: "c8d0sessionid", fileId: 77, fileName: "image 1.png",
                                       fileTime: 1_790_842_835_000, serverName: "srv", thumbnail: true, preview: true)
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.path, "/fileDownload")
        XCTAssertEqual(items["fileName"], "thumb_image 1.png"); XCTAssertEqual(items["time"], "1790842835"); XCTAssertEqual(items["id"], "77")
        XCTAssertEqual(items["gid"], "40"); XCTAssertEqual(items["ServerName"], "srv"); XCTAssertEqual(items["preview"], "1")
        XCTAssertEqual(items["sid"], XxdSigning.fileSid(sessionId: "c8d0sessionid", fileName: "thumb_image 1.png"))
        XCTAssertTrue(url.absoluteString.contains("fileName=thumb_image%201.png"), url.absoluteString)
    }

    func testFormEncodingMatchesEncodeQueryComponent() {
        XCTAssertEqual(XxdHttpDatasource.formEncode(#"{"a":"b c","d":[1]}"#), "%7B%22a%22%3A%22b+c%22%2C%22d%22%3A%5B1%5D%7D")
        XCTAssertEqual(XxdHttpDatasource.formEncode("a-b_c.d~e"), "a-b_c.d~e")
    }

    func testTLSPolicyNormalizesFingerprints() {
        XCTAssertEqual(normalizeFingerprint("ab:CD:ef"), "ABCDEF")
        let policy = XxdTLSPolicy(pinnedFingerprint: "AB:CD")
        XCTAssertNil(policy.rejected); XCTAssertNil(policy.untrustedFailure())
        let f = xxdMapTransportError(URLError(.cancelled), policy: nil, fallback: "x")
        XCTAssertEqual(f, .cancelled("cancelled"))
        XCTAssertEqual(xxdMapTransportError(URLError(.notConnectedToInternet), policy: nil, fallback: "Cannot reach").message.hasPrefix("Cannot reach: "), true)
    }

    func testCancelTokenFiresHandlersOnceAndImmediatelyWhenLate() {
        let token = ChatCancelToken()
        let hits = Locked(0)
        token.onCancel { hits.with { $0 += 1 } }
        let removed = token.onCancel { hits.with { $0 += 10 } }
        token.removeHandler(removed)
        token.cancel(); token.cancel()
        XCTAssertEqual(hits.current, 1); XCTAssertTrue(token.isCancelled)
        token.onCancel { hits.with { $0 += 100 } }
        XCTAssertEqual(hits.current, 101)
    }
}

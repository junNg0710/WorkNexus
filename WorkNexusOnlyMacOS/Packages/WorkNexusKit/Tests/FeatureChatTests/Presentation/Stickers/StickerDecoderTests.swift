import XCTest
@testable import FeatureChat

final class StickerDecoderTests: XCTestCase {
    func testGunzipInflatesTgsPayload() {
        // gzip of "hello"
        let gz = Data([0x1F, 0x8B, 0x08, 0, 0, 0, 0, 0, 0, 0x03, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00, 0x86, 0xA6, 0x10, 0x36, 0x05, 0, 0, 0])
        XCTAssertTrue(StickerDecoder.isTgs(gz))
        XCTAssertEqual(StickerDecoder.gunzip(gz).flatMap { String(data: $0, encoding: .utf8) }, "hello")
    }

    func testNotGzip() {
        XCTAssertFalse(StickerDecoder.isTgs(Data("RIFF".utf8)))
        XCTAssertNil(StickerDecoder.gunzip(Data("plain data, not gzip at all".utf8)))
    }

    func testEmojiListIsNonEmptyAndEmojiPresented() {
        XCTAssertFalse(ChatEmojiList.all.isEmpty)
        XCTAssertTrue(ChatEmojiList.all.allSatisfy { !$0.isEmpty })
    }
}

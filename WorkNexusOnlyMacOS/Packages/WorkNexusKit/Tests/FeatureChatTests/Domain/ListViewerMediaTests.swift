import XCTest
@testable import FeatureChat

/// What the media viewer steps through: pictures and videos, not stickers.
final class ListViewerMediaTests: XCTestCase {
    private func image(_ name: String, _ w: Int, _ h: Int) -> ImageContent { ImageContent(fileId: 1, name: name, size: 10, time: 0, width: w, height: h) }
    private func msg(_ gid: String, _ content: MessageContent, deleted: Bool = false) -> ChatMessage {
        Make.message(gid, content: content, deleted: deleted)
    }

    func testStickersAreToldFromPictures() {
        let isSticker = IsStickerImage()
        XCTAssertTrue(isSticker(image("anim.tgs", 0, 0)))
        XCTAssertTrue(isSticker(image("028.webp", 256, 256)))
        XCTAssertTrue(isSticker(image("dance.gif", 512, 400)))
        XCTAssertFalse(isSticker(image("big.gif", 1200, 800)), "a GIF sent as a picture is media")
        XCTAssertFalse(isSticker(image("ko_can_biet.png", 256, 256)), "a PNG is a sticker only when its name is one")
        XCTAssertTrue(isSticker(image("ko_can_biet.png", 256, 256), knownNames: ["ko_can_biet.png"]))
        XCTAssertFalse(isSticker(image("ko_can_biet.png", 2000, 2000), knownNames: ["ko_can_biet.png"]))
    }

    func testTheViewerListsPicturesAndVideosButNoStickers() {
        let photo = image("shot.png", 2880, 1800), gif = image("fun.gif", 800, 600), sticker = image("028.webp", 256, 256)
        let named = image("gap.png", 256, 256)
        let video = FileContent(fileId: 2, name: "clip.mp4", size: 99, time: 0, mimeType: "video/mp4")
        let doc = FileContent(fileId: 3, name: "spec.pdf", size: 5, time: 0, mimeType: "application/pdf")
        let messages = [msg("1", .image(photo)), msg("2", .image(sticker)), msg("3", .file(video)), msg("4", .file(doc)),
                        msg("5", .image(gif)), msg("6", .image(named)), msg("7", .image(image("gone.png", 900, 900)), deleted: true)]
        let items = ListViewerMedia()(messages, current: .image(photo), stickerNames: ["gap.png"])
        XCTAssertEqual(items, [.image(photo), .video(video), .image(gif)])
    }

    func testAStickerOnShowStaysInTheList() {
        let sticker = image("028.webp", 256, 256), photo = image("shot.png", 2880, 1800)
        let items = ListViewerMedia()([Make.message("1", content: .image(photo)), Make.message("2", content: .image(sticker))],
                                      current: .image(sticker), stickerNames: [])
        XCTAssertEqual(items, [.image(photo), .image(sticker)])
    }
}

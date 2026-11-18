import CoreDomain
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FeatureChat

/// Ports of test/data/chat/{chat_cache_manager,local_sticker_repository,local_wallpaper_repository,cached_link_preview_repository}_test.dart
/// and the attachment cache behaviour.
final class DataSupportTests: RepositoryTestCase {
    private func pngData(_ w: Int = 4, _ h: Int = 3) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        return out as Data
    }

    // MARK: link previews

    func testOpenGraphParsing() throws {
        let html = #"""
        <html><head><title> Fallback </title>
        <meta property="og:title" content="Release &amp; notes &#x1F680;">
        <META name='description' content='plain desc'>
        <meta property="og:image" content="/img/cover.png"><meta property="og:site_name" content="Acme">
        </head></html>
        """#
        let p = LinkPreviewParser.parse(html: html, pageUrl: URL(string: "https://acme.test/blog/post")!)
        XCTAssertEqual(p?.title, "Release & notes 🚀"); XCTAssertEqual(p?.siteName, "Acme"); XCTAssertEqual(p?.description, "plain desc")
        XCTAssertEqual(p?.imageUrl, "https://acme.test/img/cover.png")
        let bare = LinkPreviewParser.parse(html: "<title>Only title</title>", pageUrl: URL(string: "https://x.test/a")!)
        XCTAssertEqual(bare?.siteName, "x.test"); XCTAssertEqual(bare?.title, "Only title")
        XCTAssertNil(LinkPreviewParser.parse(html: "<p>none</p>", pageUrl: URL(string: "https://x.test")!))
        let oembed = LinkPreviewParser.parseOEmbed(json: #"{"title":"Vid","author_name":"Me","thumbnail_url":"https://i/t.jpg"}"#, url: "https://youtu.be/x")
        XCTAssertEqual(oembed?.siteName, "YouTube"); XCTAssertEqual(oembed?.description, "Me")
        XCTAssertTrue(LinkPreviewHttpDatasource.isYouTube(URL(string: "https://m.youtube.com/watch?v=1")!)); XCTAssertFalse(LinkPreviewHttpDatasource.isYouTube(URL(string: "https://notyoutube.com")!))
    }

    func testLinkPreviewCacheStoresAndReusesIncludingNoPreview() async throws {
        let repo = CachedLinkPreviewRepository(db: db, http: LinkPreviewHttpDatasource(), now: { self.now })
        let none = await repo.preview(url: "ftp://nothing")        // not http(s): "no preview", stored
        XCTAssertNotNil(none.value); XCTAssertNil(none.value!)
        let rows = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM chatLinkPreviews WHERE empty=1") }
        XCTAssertEqual(rows, 1)
        let again = await CachedLinkPreviewRepository(db: db, http: LinkPreviewHttpDatasource(), now: { self.now }).preview(url: "ftp://nothing")
        XCTAssertNil(again.value!)
    }

    // MARK: media helpers

    func testMimeAndImageSize() {
        XCTAssertEqual(ChatMedia.mimeType(forFileName: "A.PNG"), "image/png"); XCTAssertEqual(ChatMedia.mimeType(forFileName: "spec.pdf"), "application/pdf")
        XCTAssertNil(ChatMedia.mimeType(forFileName: "noext"))
        XCTAssertTrue(ChatMedia.isImageMime("image/webp")); XCTAssertFalse(ChatMedia.isImageMime("image/svg+xml")); XCTAssertFalse(ChatMedia.isImageMime(nil))
        let size = ChatMedia.imageSize(pngData(40, 30))
        XCTAssertEqual(size?.width, 40); XCTAssertEqual(size?.height, 30)
        let square = ChatMedia.squareAvatarPng(pngData(60, 30), crop: nil)
        XCTAssertEqual(square.value?.side, 30)
        XCTAssertEqual(ChatMedia.squareAvatarPng(pngData(600, 600), crop: ChatAvatarCrop(left: 10, top: 10, side: 500)).value?.side, 256)
        XCTAssertNotNil(ChatMedia.squareAvatarPng(Data([1, 2, 3]), crop: nil).failure)
    }

    // MARK: file cache + loader

    func testFileCacheTrimsLeastRecentlyUsedFirst() async throws {
        let cache = ChatFileCache(root: filesDir, maxBytes: 100, trimEvery: 0)
        cache.write("a", "old", Data(count: 40)); cache.write("a", "mid", Data(count: 40))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: cache.fileURL("a", "old").path)
        cache.write("a", "new", Data(count: 40))
        await cache.trim()
        XCTAssertNil(cache.open("a", "old")); XCTAssertNotNil(cache.open("a", "new"))
        XCTAssertLessThanOrEqual(cache.totalBytes(), 90)
        XCTAssertEqual(ChatFileCache.diskName("a/b:c?.png"), "a_b_c_.png")
    }

    func testAttachmentIsDownloadedOnceThenServedFromCache() async throws {
        try await connectAndWait()
        _ = try await eventually(repo.watchStatus(accountId: acc)) { $0 == .online(selfUserId: 40) }
        try await Task.sleep(nanoseconds: 50_000_000)   // syssessionid
        http.downloadBytes = pngData(8, 8)
        let content = MessageContent.image(ImageContent(fileId: 9, name: "pic.png", size: 0, time: 1_700_000_000_000, mimeType: "image/png"))
        let first = await repo.loadAttachment(accountId: acc, content: content, thumbnail: false)
        XCTAssertEqual(first.value, http.downloadBytes)
        let second = await repo.loadAttachment(accountId: acc, content: content, thumbnail: false)
        XCTAssertEqual(second.value, http.downloadBytes); XCTAssertEqual(http.downloads.count, 1)
        let url = http.downloads[0]
        XCTAssertTrue(url.absoluteString.hasPrefix("https://zt.test:11443/fileDownload?"))
        XCTAssertTrue(url.query!.contains("fileName=pic.png")); XCTAssertTrue(url.query!.contains("time=1700000000"))
        XCTAssertTrue(url.query!.contains("sid=\(XxdSigning.fileSid(sessionId: "session-1", fileName: "pic.png"))"))
        let cached = await repo.isAttachmentCached(accountId: acc, content: content)
        XCTAssertTrue(cached)
        let path = await repo.attachmentFile(accountId: acc, content: content)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.value ?? ""))
        let usage = await repo.cacheUsage()
        XCTAssertGreaterThan(usage.value?.totalBytes ?? 0, 0)
        let text = await repo.loadAttachment(accountId: acc, content: .text("x", markdown: false), thumbnail: false)
        XCTAssertEqual(text.failure, .notFound("This message has no attachment"))
        let h1 = await repo.clearCache(accountId: nil, chatGid: nil)
        XCTAssertNotNil(h1.value)
        let cleared = await repo.isAttachmentCached(accountId: acc, content: content)
        XCTAssertFalse(cleared)
    }

    func testSendFileUploadsThenDelivers() async throws {
        try await connectAndWait()
        try await Task.sleep(nanoseconds: 50_000_000)
        let png = pngData(10, 5)
        let result = await repo.sendFile(accountId: acc, chatGid: "g1", name: "shot.png", bytes: png, mimeType: nil, replyToId: nil)
        XCTAssertNotNil(result.value)
        XCTAssertEqual(http.uploads.first?.chatGid, "g1"); XCTAssertEqual(http.uploads.first?.size, png.count)
        let m = server.requests("messagesend").last!["params"]![0]![0]!
        XCTAssertEqual(m["contentType"], "image")
        let body = try JSONValue.parse(m["content"]!.string!)
        XCTAssertEqual(body["id"], 7); XCTAssertEqual(body["name"], "shot.png"); XCTAssertEqual(body["type"], "image/png"); XCTAssertEqual(body["width"], 10)
        let sent = try await eventually(repo.watchMessages(accountId: acc, chatGid: "g1")) { $0.contains { $0.isMine && $0.serverId != nil } }
        guard case .image(let img)? = sent.last(where: { $0.isMine })?.content else { return XCTFail() }
        XCTAssertEqual(img.fileId, 7); XCTAssertEqual(img.width, 10)
        // The sender's own copy is cached: no download back.
        let again = await repo.loadAttachment(accountId: acc, content: .image(img), thumbnail: false)
        XCTAssertEqual(again.value, png); XCTAssertTrue(http.downloads.isEmpty)
        // Too large for the server.
        http.uploads.removeAll()
    }

    func testRetractSendsDeletedRowAndKeepsReactionEmoji() async throws {
        try await connectAndWait()
        server.current.push(["method": "messagesend", "result": "success", "data": [
            ["gid": "r1", "cgid": "g1", "id": 400, "index": 101, "user": 40, "date": .int(t0Server + 400), "contentType": "image",
             "content": #"{"type":"emoji","content":":thumbsup:"}"#, "data": #"{"replyTo":100}"#, "deleted": false, "type": "normal"]]])
        _ = try await eventually(repo.watchReplies(accountId: acc, chatGid: "g1")) { $0.contains { $0.gid == "r1" } }
        server.onRequest = { [prev = server.onRequest] req in
            if req["method"] == "messageretract" {
                // The server answers with the emptied, deleted row.
                return ["method": "messageretract", "rid": req["rid"] ?? .null, "result": "success",
                        "data": ["gid": "r1", "cgid": "g1", "id": 400, "index": 101, "user": 40, "date": .int(t0Server + 400), "contentType": "emotion", "content": "",
                                 "data": #"{"replyTo":100}"#, "deleted": true, "type": "normal"]]
            }
            return prev?(req)
        }
        let h2 = await repo.retract(accountId: acc, messageGid: "r1")
        XCTAssertNotNil(h2.value)
        let req = server.requests("messageretract").last!["params"]![0]![0]!
        XCTAssertEqual(req["deleted"], true); XCTAssertEqual(req["gid"], "r1")
        let replies = try await eventually(repo.watchReplies(accountId: acc, chatGid: "g1")) { $0.contains { $0.gid == "r1" && $0.deleted } }
        XCTAssertEqual(replies.first { $0.gid == "r1" }?.content, .emoji("👍"), "the emoji is kept so the retraction still reads as a reaction")
    }

    // MARK: stickers, wallpapers, notifications

    func testStickerRepositoryPacksAndOwnStickers() async throws {
        let dir = filesDir.appendingPathComponent("stickers")
        let bundled = filesDir.appendingPathComponent("bundled/cats", isDirectory: true)
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try pngData().write(to: bundled.appendingPathComponent("a.png"))
        let repo = LocalStickerRepository(bundleRoot: bundled.deletingLastPathComponent(), directory: dir, converter: ImageStickerConverter())
        let h3 = await repo.stickers()
        XCTAssertEqual(h3.value?.map(\.pack), ["cats"])
        let added = await repo.add(bytes: pngData(300, 300), name: "My Pic.jpeg")
        XCTAssertEqual(added.value?.name, "My_Pic.png"); XCTAssertTrue(added.value?.custom ?? false)
        let packed = await repo.addPack("tg:Set", title: "Nice Set", stickers: [(name: "001.png", bytes: pngData(), emoji: "😂"), (name: "002.png", bytes: pngData(), emoji: "")])
        XCTAssertNotNil(packed.value)
        let all = (await repo.stickers()).value ?? []
        // Each sticker keeps the emoji Telegram gave it.
        XCTAssertEqual(all.filter { $0.pack == "tg:Set" }.map(\.emoji), ["😂", ""])
        XCTAssertEqual(all.filter { $0.pack == "tg:Set" }.map(\.name), ["001.png", "002.png"]); XCTAssertEqual(all.first { $0.pack == "tg:Set" }?.packTitle, "Nice Set")
        _ = await repo.rememberPack("tg:Set")
        let h4 = await repo.lastPack()
        XCTAssertEqual(h4.value ?? nil, "tg:Set")
        let h5 = await repo.remove(all.first { $0.pack == "cats" }!)
        XCTAssertNotNil(h5.failure, "bundled stickers stay")
        let h6 = await repo.removePack("tg:Set")
        XCTAssertNotNil(h6.value)
        let h7 = await repo.stickers()
        XCTAssertTrue((h7.value ?? []).filter { $0.pack == "tg:Set" }.isEmpty)
    }

    func testWallpaperRepository() async throws {
        let repo = LocalWallpaperRepository(directory: filesDir.appendingPathComponent("wp"))
        let h8 = await repo.wallpapers()
        XCTAssertEqual(h8.value, [])
        let added = await repo.add(bytes: pngData(), name: "my wall")
        let path = try XCTUnwrap(added.value)
        XCTAssertTrue(path.hasSuffix("my_wall.png"))
        let h9 = await repo.wallpapers()
        XCTAssertEqual(h9.value?.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }, [URL(fileURLWithPath: path).resolvingSymlinksInPath().path])
        let h10 = await repo.remove(path: "/etc/hosts")
        XCTAssertNotNil(h10.failure)
        let h11 = await repo.remove(path: path)
        XCTAssertNotNil(h11.value)
        let h12 = await repo.wallpapers()
        XCTAssertEqual(h12.value, [])
        let h13 = await repo.add(bytes: Data(), name: "x")
        XCTAssertNotNil(h13.failure)
    }

    func testNotificationBridgeDeliversWhatShouldBeSeen() async throws {
        final class Sink: ChatNotificationSink, @unchecked Sendable {
            let got = Locked<[ChatNotification]>([]); var appIsFocused = false
            func deliver(_ n: ChatNotification) { got.with { $0.append(n) } }
            func clear(accountId: String, chatGid: String) {}
        }
        let sink = Sink()
        let bridge = ChatNotificationBridge(repository: repo, sink: sink, preferences: { ChatNotificationPreferences() }, visibleChat: { nil })
        try await connectAndWait()
        _ = try await eventually(repo.watchUsers(accountId: acc)) { $0.contains { $0.userId == 31 } }
        bridge.start(accountIds: [acc])
        try await Task.sleep(nanoseconds: 100_000_000)
        server.current.push(["method": "messagesend", "result": "success", "data": [serverMessage(150, user: 31, content: "hi [@Demo](@#40) **there**")]])
        for _ in 0..<50 where sink.got.current.isEmpty { try await Task.sleep(nanoseconds: 50_000_000) }
        bridge.stop()
        let n = try XCTUnwrap(sink.got.current.first)
        XCTAssertEqual(n.title, "Team"); XCTAssertEqual(n.subtitle, "User 31"); XCTAssertEqual(n.body, "hi @Demo there"); XCTAssertEqual(n.chatGid, "g1")
        XCTAssertEqual(ChatNotificationBridge.preview(.file(FileContent(fileId: 1, name: "a.pdf", size: 1, time: 0))), "File: a.pdf")
        XCTAssertEqual(ChatNotificationBridge.preview(.image(ImageContent(fileId: 1, name: "a.png", size: 1, time: 0))), "Photo")
        let counts = ChatUnreadCounter(repository: repo).counts(accountId: acc)
        var first: Int?
        for await c in counts { first = c; break }
        XCTAssertEqual(first, 51, "last message index 150 − read marker 99")
    }

    func testFeatureFacadeBuildsARepositoryAndServices() async throws {
        let account = Account(id: acc, workspaceId: "ws", providerType: .zentao, handle: "demo", baseUrl: "https://zt.test/zentao", credentialsRef: "secret:acc")
        let repository = ChatFeature.makeRepository(db: db, account: account, credentials: store, applying: AppSettings())
        let services = ChatFeature.makeServices(repository: repository, db: db, credentials: store)
        XCTAssertNotNil(services.stickers); XCTAssertNotNil(services.linkPreviews); XCTAssertNotNil(services.translations); XCTAssertNotNil(services.stickerImport)
        try await Task.sleep(nanoseconds: 100_000_000)
        let row = try await db.writer.read { try String.fetchOne($0, sql: "SELECT serverUrl FROM chatAccounts WHERE accountId='acc'") }
        XCTAssertEqual(row, "https://zt.test:11443")
    }
}

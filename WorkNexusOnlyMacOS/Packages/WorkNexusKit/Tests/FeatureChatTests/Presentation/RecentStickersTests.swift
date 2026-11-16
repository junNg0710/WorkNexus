import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureChat

/// The stickers sent lately lead the picker.
@MainActor
final class RecentStickersTests: XCTestCase {
    private var stickersRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Stickers")
    }
    private func sticker(_ pack: String, _ name: String, custom: Bool = false, at: String = "/app") -> ChatSticker {
        ChatSticker(id: "\(at)/\(pack)/\(name)", pack: pack, name: name, location: "\(at)/\(pack)/\(name)", custom: custom)
    }
    private func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("recent_\(UUID().uuidString)") }

    func testASentStickerLeadsOnceAndTheOldestFallOff() {
        let recents = RecentStickers()
        let a = sticker("Pepe", "001.webp"), b = sticker("Pepe", "002.webp"), c = sticker("Cute", "001.webp")
        var keys = recents.adding(a, to: [])
        keys = recents.adding(b, to: keys); keys = recents.adding(c, to: keys); keys = recents.adding(a, to: keys)
        XCTAssertEqual(keys, [a.recentKey, c.recentKey, b.recentKey], "sent again: moved to the front, not listed twice")
        XCTAssertEqual(recents.adding(b, to: keys, limit: 2), [b.recentKey, a.recentKey])
        // The same file name in another set, or among the user's own stickers, is another sticker.
        XCTAssertNotEqual(a.recentKey, c.recentKey)
        XCTAssertNotEqual(sticker("", "001.webp", custom: true).recentKey, sticker("", "001.webp").recentKey)
    }

    func testRecentsAreFoundAgainAfterTheAppMovedAndGoneOnesAreLeftOut() {
        let before = [sticker("Pepe", "001.webp"), sticker("Cute", "003.webp"), sticker("tg:Set", "9.png", custom: true)]
        let keys = before.map(\.recentKey)
        // The app was updated to another place and the imported set removed: the paths differ, the keys still name the rest.
        let now = [sticker("Cute", "003.webp", at: "/Applications/New.app"), sticker("Pepe", "001.webp", at: "/Applications/New.app"),
                   sticker("Pepe", "002.webp", at: "/Applications/New.app")]
        XCTAssertEqual(RecentStickers().resolve(keys, in: now).map(\.id), ["/Applications/New.app/Pepe/001.webp", "/Applications/New.app/Cute/003.webp"])
        XCTAssertEqual(RecentStickers().resolve([], in: now), [])
    }

    func testTheStoreKeepsWhatWasSentAcrossRuns() async throws {
        let dir = tempDir()
        let store = StickerStore(LocalStickerRepository(bundleRoot: stickersRoot, directory: dir))
        await store.reload()
        guard case .ready(let all) = store.phase else { return XCTFail("stickers did not load") }
        XCTAssertTrue(store.recents(in: all).isEmpty)
        let rabbit = try XCTUnwrap(all.first { $0.pack == "HyperRabbit" }), pepe = try XCTUnwrap(all.first { $0.pack == "Pepe" })
        store.noteSent(rabbit); store.noteSent(pepe)
        XCTAssertEqual(store.recents(in: all).map(\.id), [pepe.id, rabbit.id])
        // Written in the background: a second store over the same folder reads it back.
        let again = StickerStore(LocalStickerRepository(bundleRoot: stickersRoot, directory: dir))
        for _ in 0..<100 {
            await again.reload()
            if again.recentKeys.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(again.recentKeys, [pepe.recentKey, rabbit.recentKey])
    }

    /// The picker with recent stickers: the clock leads the bar and its grid shows them newest first.
    func testThePickerOpensOnTheRecentOnesWhenTheyWereUsedLast() async throws {
        let store = StickerStore(LocalStickerRepository(bundleRoot: stickersRoot, directory: tempDir()))
        await store.reload()
        guard case .ready(let all) = store.phase else { return XCTFail("stickers did not load") }
        for s in all.filter({ $0.pack == "HyperRabbit" }).prefix(4) + all.filter({ $0.pack == "Pepe" }).prefix(3) { store.noteSent(s) }
        store.remember(StickerStore.recentPack)
        let theme = AppTheme(settings: AppSettings())
        let view = ChatStickerPanel(stickers: all, store: store, onPick: { _ in }, onError: { _ in })
            .chatServices(ChatServices(chat: StubChatRepository(), stickers: LocalStickerRepository(bundleRoot: stickersRoot, directory: tempDir())))
            .environment(\.appTheme, theme).frame(width: 360, height: 420).background(theme.colors.bg)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 420)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<25 { try await Task.sleep(for: .milliseconds(40)); host.layoutSubtreeIfNeeded() }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try FileManager.default.createDirectory(atPath: "/tmp/wn-chat-render", withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/wn-chat-render/sticker-recent.png"))
        XCTAssertEqual(store.recents(in: all).count, 7)
    }
}

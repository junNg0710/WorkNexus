/// Ported from: lib/features/chat/presentation/widgets/chat_wallpaper_{picker,colors,custom_color}.dart (state), core/widgets/hsv_color_fields.dart
import CoreUI
import XCTest
@testable import FeatureChat

@MainActor
final class ChatWallpaperPickerTests: XCTestCase {
    func testPreviewShadowsTheSavedWallpaperUntilCleared() {
        let p = ChatWallpaperPreview.shared
        p.clear()
        XCTAssertEqual(p.shown(saved: "pattern"), "pattern")
        p.show("solid:#112233")
        XCTAssertTrue(p.shows("solid:#112233"))
        XCTAssertEqual(p.shown(saved: "pattern"), "solid:#112233")
        p.clear()
        XCTAssertFalse(p.shows("solid:#112233"))
        XCTAssertEqual(p.shown(saved: "none"), "none")
    }

    func testPickedColourKeepsThePatternChoice() {
        let c = ChatWallpaperColor("#A1B2C3", doodles: false)
        XCTAssertEqual(c.value, "solid:#A1B2C3")
        XCTAssertEqual(ChatWallpaperColor.parse(c.value)?.doodles, false)
        var again = ChatWallpaperColor("blue", doodles: true); again.doodles = false
        XCTAssertEqual(again.value, "solid:blue")
    }

    func testHsvRoundTripsHexAndKeepsTheHueOfAGrey() {
        for hex in ["#FF0000", "#00FF00", "#0000FF", "#A9C08E", "#123456"] { XCTAssertEqual(HsvColor(hex: hex)?.hex, hex) }
        XCTAssertEqual(HsvColor(hex: "a9c08e")?.hex, "#A9C08E")
        XCTAssertNil(HsvColor(hex: "#12345"))
        XCTAssertNil(HsvColor(hex: "zzzzzz"))
        let grey = HsvColor(hex: "#808080")
        XCTAssertEqual(grey?.s, 0)
        let red = HsvColor(h: 0, s: 1, v: 1), blue = HsvColor(h: 240, s: 1, v: 1)
        XCTAssertEqual(red.hex, "#FF0000"); XCTAssertEqual(blue.hex, "#0000FF")
    }

    func testWallpaperRepositoryAddsListsAndRemovesOnlyItsOwnFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = LocalWallpaperRepository(directory: dir)
        let added = await repo.add(bytes: Data([1, 2, 3]), name: "sky.jpg")
        guard case .success(let path) = added else { return XCTFail("add failed") }
        let listed = await repo.wallpapers()
        XCTAssertEqual(try listed.get().map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }, [URL(fileURLWithPath: path).resolvingSymlinksInPath().path])
        let outside = await repo.remove(path: "/etc/hosts")
        XCTAssertNotNil(outside.failureValue)
        let removed = await repo.remove(path: path)
        XCTAssertNil(removed.failureValue)
        let after = await repo.wallpapers()
        XCTAssertEqual(try after.get(), [])
        let empty = await repo.add(bytes: Data(), name: "x.png")
        XCTAssertNotNil(empty.failureValue)
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let f) = self { f } else { nil } }
}

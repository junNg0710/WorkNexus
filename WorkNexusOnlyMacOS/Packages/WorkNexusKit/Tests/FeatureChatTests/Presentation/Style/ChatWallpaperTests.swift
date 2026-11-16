/// Ported from: test/core/settings/chat_wallpaper_color_test.dart, test/core/theme/chat_doodle_palette_test.dart
import XCTest
@testable import FeatureChat

final class ChatWallpaperTests: XCTestCase {
    func testParseTintSolidAndDefaultPattern() {
        XCTAssertEqual(ChatWallpaperColor.parse("pattern"), ChatWallpaperColor("green", doodles: true))
        XCTAssertEqual(ChatWallpaperColor.parse("tint:blue"), ChatWallpaperColor("blue", doodles: true))
        XCTAssertEqual(ChatWallpaperColor.parse("solid:#FF8800"), ChatWallpaperColor("#FF8800", doodles: false))
        XCTAssertNil(ChatWallpaperColor.parse("tint:"))
        XCTAssertNil(ChatWallpaperColor.parse("none"))
        XCTAssertNil(ChatWallpaperColor.parse("/Users/me/Pictures/wall.jpg"))
    }

    func testValueRoundTrips() {
        for w in ["tint:blue", "solid:#A1B2C3"] { XCTAssertEqual(ChatWallpaperColor.parse(w)?.value, w) }
    }

    func testIsPicture() {
        XCTAssertFalse(chatWallpaperIsPicture("none"))
        XCTAssertFalse(chatWallpaperIsPicture(""))
        XCTAssertTrue(chatWallpaperIsPicture("pattern"))
        XCTAssertTrue(chatWallpaperIsPicture("/tmp/a.png"))
    }

    func testForColorPresetsAndHex() {
        XCTAssertEqual(ChatDoodlePalette.forColor("green", dark: false), .day)
        XCTAssertEqual(ChatDoodlePalette.forColor("green", dark: true), .night)
        let blueDay = ChatDoodlePalette.forColor("blue", dark: false)
        XCTAssertEqual(blueDay?.base, ChatColor(0xFF9D_B9D9))
        XCTAssertEqual(ChatDoodlePalette.forColor("#112233", dark: false)?.base, ChatColor(0xFF11_2233))
        XCTAssertEqual(ChatDoodlePalette.forColor("112233", dark: true)?.base, ChatColor(0xFF11_2233))
        XCTAssertNil(ChatDoodlePalette.forColor("nope", dark: false))
        XCTAssertNil(ChatDoodlePalette.forColor("#12", dark: false))
    }

    func testFromColorShadesCornersAndPicksInk() {
        let light = ChatDoodlePalette.fromColor(ChatColor(0xFFA9_C08E))
        XCTAssertEqual(light.corners.count, 4)
        XCTAssertGreaterThan(light.corners[0].luminance, light.base.luminance)
        XCTAssertLessThan(light.corners[1].luminance, light.base.luminance)
        XCTAssertEqual(light.ink.a, 0.14, accuracy: 1e-9)
        XCTAssertLessThan(light.ink.luminance, light.base.luminance, "a deep shade on a light colour")
        let dark = ChatDoodlePalette.fromColor(ChatColor(0xFF0B_121B))
        XCTAssertEqual(dark.ink, ChatColor(0x14FF_FFFF))
    }

    func testPresetsAreUniqueAndStartWithGreen() {
        let ids = ChatWallpaperTint.presets.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.first, "green")
    }

    func testDoodleArrangementIsDeterministic() {
        let a = ChatDoodleCanvas.marks(cell: 56), b = ChatDoodleCanvas.marks(cell: 56)
        XCTAssertEqual(a.count, 64)
        XCTAssertEqual(a.map(\.symbol), b.map(\.symbol))
        XCTAssertEqual(a.map(\.at), b.map(\.at))
        for m in a { XCTAssertGreaterThan(m.size, 0) }
    }
}

// Not in the Flutter app: the Hacker theme, a terminal's green on black.
import AppKit
import CoreDomain
import SwiftUI
import XCTest
@testable import CoreUI

final class HackerThemeTests: XCTestCase {
    private func settings(_ variant: ThemeVariant, followsSystem: Bool = false, font: String = "") -> AppSettings {
        var s = AppSettings()
        s.variant = variant; s.themeFollowsSystem = followsSystem; s.fontFamily = font
        return s
    }

    /// Relative luminance of an sRGB colour (WCAG).
    private func luminance(_ color: Color) -> Double {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func lin(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testItIsADarkPaletteOfItsOwn() {
        let p = AppPalette.of(.hacker)
        XCTAssertEqual(p.variant, .hacker)
        XCTAssertTrue(p.isDark)
        XCTAssertEqual(AppTheme(settings: settings(.hacker)).colorScheme, .dark)
        XCTAssertNotEqual(NSColor(p.accent).usingColorSpace(.sRGB), NSColor(AppPalette.dark.accent).usingColorSpace(.sRGB))
    }

    func testGreenOnBlackStaysReadableOnEverySurface() {
        let p = AppPalette.hacker
        for surface in [p.bg, p.panel, p.panel2, p.card, p.titlebar] {
            XCTAssertGreaterThan(contrast(p.tx, surface), 7, "body text")
            XCTAssertGreaterThan(contrast(p.tx2, surface), 4.5, "secondary text")
            XCTAssertGreaterThan(contrast(p.tx3, surface), 4.5, "hints")
            XCTAssertGreaterThan(contrast(p.red, surface), 4.5, "an error still reads as one")
        }
        XCTAssertGreaterThan(contrast(p.accentTx, p.accent), 7, "the label of a filled button")
    }

    func testItIsSetInTheMonospacedFaceUnlessAFontWasChosen() {
        XCTAssertTrue(AppTheme(settings: settings(.hacker)).typography.monospaced)
        XCTAssertFalse(AppTheme(settings: settings(.dark)).typography.monospaced)
        let mono = AppTheme(settings: settings(.hacker)).typography.nsFont(size: 13)
        XCTAssertTrue(mono.isFixedPitch)
        XCTAssertFalse(AppTheme(settings: settings(.dark)).typography.nsFont(size: 13).isFixedPitch)
        XCTAssertEqual(AppTheme(settings: settings(.hacker, font: "Poppins")).typography.family, "Poppins", "a chosen font is kept")
    }

    func testFollowingTheSystemItShowsInDarkModeAndGivesWayToLight() {
        XCTAssertEqual(AppTheme(settings: settings(.hacker, followsSystem: true), systemIsDark: true).colors.variant, .hacker)
        XCTAssertEqual(AppTheme(settings: settings(.hacker, followsSystem: true), systemIsDark: false).colors.variant, .light)
    }

    func testTheChoiceIsKeptAndAnOlderBuildFallsBack() throws {
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings(.hacker)))
        XCTAssertEqual(back.variant, .hacker)
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"variant": "neon"}"#.utf8))
        XCTAssertEqual(unknown.variant, AppSettings().variant, "a theme this build does not know")
    }
}

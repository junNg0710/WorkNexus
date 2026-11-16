/// Ported from: lib/core/theme/contrast.dart (+ the Color maths chat_style.dart and chat_style_palette.dart lean on)
import AppKit
import SwiftUI

/// A plain sRGB colour value the chat style maths run on (alpha blending, luminance, contrast), kept apart from
/// SwiftUI's `Color` so palettes and contrast checks are testable without a view. Literal `0xAARRGGBB` values live in
/// `ChatStylePalette`, which is itself a token table.
public struct ChatColor: Hashable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    /// `0xAARRGGBB`, the Flutter literal format.
    public init(_ argb: UInt32) {
        self.init(r: Double((argb >> 16) & 0xFF) / 255, g: Double((argb >> 8) & 0xFF) / 255,
                  b: Double(argb & 0xFF) / 255, a: Double((argb >> 24) & 0xFF) / 255)
    }

    /// Reads a SwiftUI colour in sRGB (theme colours are fixed sRGB values, not dynamic).
    public init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    public static let clear = ChatColor(r: 0, g: 0, b: 0, a: 0)

    /// The same colour at opacity `alpha` (Flutter `withValues(alpha:)`).
    public func opacity(_ alpha: Double) -> ChatColor { ChatColor(r: r, g: g, b: b, a: alpha) }

    /// `self` drawn over `background` (Flutter `Color.alphaBlend(foreground, background)`).
    public func over(_ background: ChatColor) -> ChatColor {
        let outA = a + background.a * (1 - a)
        if outA == 0 { return .clear }
        func mix(_ f: Double, _ bg: Double) -> Double { (f * a + bg * background.a * (1 - a)) / outA }
        return ChatColor(r: mix(r, background.r), g: mix(g, background.g), b: mix(b, background.b), a: outA)
    }

    /// Linear interpolation (Flutter `Color.lerp`).
    public func lerp(to other: ChatColor, _ t: Double) -> ChatColor {
        ChatColor(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }

    /// Relative luminance (Flutter `computeLuminance`), ignoring alpha.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG contrast ratio between two opaque colours (1-21).
    public static func contrast(_ a: ChatColor, _ b: ChatColor) -> Double {
        let la = a.luminance, lb = b.luminance
        return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05)
    }

    // MARK: HSL

    struct HSL { var h: Double, s: Double, l: Double }

    var hsl: HSL {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        if d == 0 { return HSL(h: 0, s: 0, l: l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h *= 60
        if h < 0 { h += 360 }
        return HSL(h: h, s: s, l: l)
    }

    init(hsl: HSL, a: Double = 1) {
        let c = (1 - abs(2 * hsl.l - 1)) * hsl.s
        let hp = hsl.h.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        let m = hsl.l - c / 2
        self.init(r: r1 + m, g: g1 + m, b: b1 + m, a: a)
    }

    /// This colour with its lightness replaced / hue replaced (kept in range like Flutter's `HSLColor`).
    func withLightness(_ l: Double) -> ChatColor { var h = hsl; h.l = min(max(l, 0), 1); return ChatColor(hsl: h, a: a) }
    func withHue(_ hue: Double) -> ChatColor {
        var h = hsl
        h.h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return ChatColor(hsl: h, a: a)
    }

    /// `ink` made to read at `min`:1 on the opaque `background`, keeping its hue: only its lightness moves — lighter on
    /// dark fills, darker on light ones — so a green stays green and a red stays red on any bubble. When no lightness of
    /// that hue reads, it is mixed towards `towards` (the bubble's text colour) instead.
    public static func readable(_ ink: ChatColor, on background: ChatColor, towards: ChatColor, min minRatio: Double = 4.5) -> ChatColor {
        if contrast(ink, background) >= minRatio { return ink }
        let base = ink.hsl.l
        let lighter = background.luminance < 0.5
        for step in 1...20 {
            let l = Swift.min(Swift.max(base + (lighter ? Double(step) : -Double(step)) * 0.025, 0), 1)
            let shifted = ink.withLightness(l)
            if contrast(shifted, background) >= minRatio { return shifted }
        }
        var t = 0.1
        while t < 1 {
            let mixed = ink.lerp(to: towards, t)
            if contrast(mixed, background) >= minRatio { return mixed }
            t += 0.1
        }
        return towards
    }
}

/// Ported from: lib/core/theme/chat_doodle_palette.dart + lib/core/settings/chat_wallpaper_color.dart
import Foundation

/// A coloured chat wallpaper as kept in `ChatSettings.wallpaper`: `tint:<colour>` (the doodle pattern over it) or
/// `solid:<colour>` (the colour alone), where `<colour>` is a preset id (`ChatWallpaperTint.id`) or `#RRGGBB`.
public struct ChatWallpaperColor: Hashable, Sendable {
    public var color: String
    /// Whether the doodle pattern is drawn over the colour.
    public var doodles: Bool
    public init(_ color: String, doodles: Bool = true) { self.color = color; self.doodles = doodles }

    public static let plain = "none"
    public static let pattern = "pattern"

    /// The colour `wallpaper` names, or nil for any other wallpaper (plain or an image path — paths never start like these).
    public static func parse(_ wallpaper: String) -> ChatWallpaperColor? {
        // The default pattern is the green colour with the pattern over it.
        if wallpaper == pattern { return ChatWallpaperColor("green") }
        for (prefix, doodles) in [("tint:", true), ("solid:", false)] where wallpaper.hasPrefix(prefix) {
            let color = String(wallpaper.dropFirst(prefix.count))
            return color.isEmpty ? nil : ChatWallpaperColor(color, doodles: doodles)
        }
        return nil
    }

    /// The setting value.
    public var value: String { "\(doodles ? "tint:" : "solid:")\(color)" }
}

/// Whether the user's chat background is a picture (the pattern or an image) rather than the plain app background —
/// then separators need a fill of their own to stay readable.
public func chatWallpaperIsPicture(_ wallpaper: String) -> Bool {
    !wallpaper.isEmpty && wallpaper != ChatWallpaperColor.plain
}

/// A preset chat wallpaper colour, with its shade for a light and a dark theme so messages stay readable over it.
public struct ChatWallpaperTint: Hashable, Sendable {
    /// Stored in the wallpaper setting; never shown.
    public let id: String
    public let day: ChatColor
    public let night: ChatColor

    public func of(dark: Bool) -> ChatColor { dark ? night : day }

    /// The default doodle wallpaper's green (`ChatDoodlePalette.day` / `night`).
    public static let green = ChatWallpaperTint(id: "green", day: ChatColor(0xFFA9_C08E), night: ChatColor(0xFF0B_121B))
    public static let presets: [ChatWallpaperTint] = [
        green,
        ChatWallpaperTint(id: "blue", day: ChatColor(0xFF9D_B9D9), night: ChatColor(0xFF0F_1A2B)),
        ChatWallpaperTint(id: "teal", day: ChatColor(0xFF92_CBC4), night: ChatColor(0xFF0D_2224)),
        ChatWallpaperTint(id: "purple", day: ChatColor(0xFFB7_A6D6), night: ChatColor(0xFF1A_1529)),
        ChatWallpaperTint(id: "pink", day: ChatColor(0xFFE0_A9BE), night: ChatColor(0xFF2A_1520)),
        ChatWallpaperTint(id: "orange", day: ChatColor(0xFFE6_C29A), night: ChatColor(0xFF2A_1D10)),
        ChatWallpaperTint(id: "sand", day: ChatColor(0xFFD9_CFB4), night: ChatColor(0xFF1F_1B12)),
        ChatWallpaperTint(id: "gray", day: ChatColor(0xFFC4_C7CC), night: ChatColor(0xFF16_181C)),
    ]
}

/// Colours of the "pattern" chat wallpaper: a soft four-corner gradient (`corners`: top left, top right, bottom right,
/// bottom left, over `base`) under a tiled doodle pattern drawn in `ink`. Shared by every chat style.
public struct ChatDoodlePalette: Hashable, Sendable {
    public var base: ChatColor
    public var corners: [ChatColor]
    public var ink: ChatColor

    /// Telegram's default gradient wallpaper (green / sand).
    public static let day = ChatDoodlePalette(
        base: ChatColor(0xFFA9_C08E),
        corners: [ChatColor(0xFFDB_DDBB), ChatColor(0xFF6B_A587), ChatColor(0xFFD5_D88D), ChatColor(0xFF88_B884)],
        ink: ChatColor(0x1F1D_3A1A))

    public static let night = ChatDoodlePalette(
        base: ChatColor(0xFF0B_121B),
        corners: [ChatColor(0xFF14_232F), ChatColor(0xFF0B_141D), ChatColor(0xFF1A_2A2C), ChatColor(0xFF0E_1A22)],
        ink: ChatColor(0x14FF_FFFF))

    public static func of(dark: Bool) -> ChatDoodlePalette { dark ? night : day }

    /// The wallpaper for a chosen colour: preset id (in the theme's shade) or `#RRGGBB` (as picked, in either theme).
    /// Nil when `color` is neither.
    public static func forColor(_ color: String, dark: Bool) -> ChatDoodlePalette? {
        if color == ChatWallpaperTint.green.id { return of(dark: dark) }
        if let tint = ChatWallpaperTint.presets.first(where: { $0.id == color }) { return fromColor(tint.of(dark: dark)) }
        let hex = color.hasPrefix("#") ? String(color.dropFirst()) : color
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return fromColor(ChatColor(0xFF00_0000 | v))
    }

    /// A doodle wallpaper around `base`: corners a shade lighter and darker so the gradient stays soft, and doodles a deep
    /// shade of the same hue on a light colour (a faint white on a dark one), like the default.
    public static func fromColor(_ base: ChatColor) -> ChatDoodlePalette {
        let hsl = base.hsl
        let light = hsl.l > 0.45
        // Dark colours show a shift sooner, so they move less.
        let step = light ? 0.08 : 0.035
        func shade(_ lightness: Double, _ hue: Double) -> ChatColor {
            base.withLightness(min(max(hsl.l + lightness, 0), 1)).withHue(hsl.h + hue)
        }
        return ChatDoodlePalette(
            base: base, corners: [shade(step, 0), shade(-step, 8), shade(step * 0.7, -8), shade(-step * 0.5, 4)],
            ink: light ? base.withLightness(min(max(hsl.l - 0.5, 0), 1)).opacity(0.14) : ChatColor(0x14FF_FFFF))
    }
}

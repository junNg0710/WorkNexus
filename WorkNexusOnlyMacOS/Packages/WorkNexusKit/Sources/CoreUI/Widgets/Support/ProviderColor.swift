import Foundation

/// Ported from: lib/core/theme/provider_color.dart (pure part).
public enum ProviderColor {
    /// `#RRGGBB` / `RRGGBB` / `#RGB` → 0xAARRGGBB; nil when malformed.
    public static func argb(fromHex value: String?) -> UInt32? {
        guard var hex = value?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return 0xFF00_0000 | v
    }

    /// Relative luminance (sRGB, 0…1) used to choose a readable ink over a provider fill.
    public static func luminance(_ argb: UInt32) -> Double {
        func lin(_ c: UInt32) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin((argb >> 16) & 0xFF) + 0.7152 * lin((argb >> 8) & 0xFF) + 0.0722 * lin(argb & 0xFF)
    }
}

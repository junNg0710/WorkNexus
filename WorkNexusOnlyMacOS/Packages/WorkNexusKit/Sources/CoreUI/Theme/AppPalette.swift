import CoreDomain
import SwiftUI

public extension Color {
    /// 0xAARRGGBB, same literal format as the Flutter palette.
    init(argb: UInt32) {
        self.init(.sRGB, red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}

/// Ported from: lib/core/theme/app_palette.dart
public struct AppPalette: Sendable {
    public var variant: ThemeVariant
    public var isDark: Bool
    public var bg, panel, panel2, card, line, line2, tx, tx2, tx3, accent, accentTx, titlebar, sel, selLine: Color
    public var red, orange, yellow, green, amber, violet, skel, skel2, scrim, onScrim, onColorInk, workspaceFallback: Color

    public static let accentPresets: [UInt32] = [
        0xFF5A57D6, 0xFF2563EB, 0xFF0EA5E9, 0xFF0D9488, 0xFF16A34A, 0xFFD97706, 0xFFEA580C, 0xFFE11D48, 0xFFDB2777, 0xFF7C3AED,
        0xFFA5B4FC, 0xFF93C5FD, 0xFF7DD3FC, 0xFF5EEAD4, 0xFF86EFAC, 0xFFFCD34D, 0xFFFDBA74, 0xFFFDA4AF, 0xFFF9A8D4, 0xFFC4B5FD,
    ]

    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
    private static func c(_ v: UInt32) -> Color { Color(argb: v) }

    public static let light = AppPalette(
        variant: .light, isDark: false, bg: c(0xFFE8E8E8), panel: c(0xFFF8F8F8), panel2: c(0xFFEBEBEB), card: c(0xFFFFFFFF),
        line: c(0xFFDCDCDC), line2: c(0xFFC4C4C4), tx: c(0xFF1C1C1C), tx2: c(0xFF4A4A4A), tx3: c(0xFF666666),
        accent: c(0xFF5A57D6), accentTx: c(0xFFFFFFFF), titlebar: c(0xFFE4E4E4),
        sel: rgba(90, 87, 214, 0.10), selLine: rgba(90, 87, 214, 0.5),
        red: c(0xFFC81E1E), orange: c(0xFFA84C08), yellow: c(0xFF805F00), green: c(0xFF1B7340), amber: c(0xFF935C00),
        violet: c(0xFF744CBF), skel: rgba(0, 0, 0, 0.05), skel2: rgba(0, 0, 0, 0.09), scrim: c(0xFF000000),
        onScrim: c(0xFFFFFFFF), onColorInk: c(0xFF0B0D11), workspaceFallback: c(0xFF888888))

    public static let dark = AppPalette(
        variant: .dark, isDark: true, bg: c(0xFF151515), panel: c(0xFF1C1C1C), panel2: c(0xFF242424), card: c(0xFF252525),
        line: c(0xFF323232), line2: c(0xFF3D3D3D), tx: c(0xFFEDEDED), tx2: c(0xFFB4B4B4), tx3: c(0xFF8F8F8F),
        accent: c(0xFF7F83F0), accentTx: c(0xFFFFFFFF), titlebar: c(0xFF191919),
        sel: rgba(127, 131, 240, 0.18), selLine: rgba(127, 131, 240, 0.5),
        red: c(0xFFEF6B63), orange: c(0xFFE59A4A), yellow: c(0xFFD8B850), green: c(0xFF4CC06B), amber: c(0xFFE3A63C),
        violet: c(0xFF9D8CFF), skel: rgba(255, 255, 255, 0.05), skel2: rgba(255, 255, 255, 0.10), scrim: c(0xFF000000),
        onScrim: c(0xFFFFFFFF), onColorInk: c(0xFF0B0D11), workspaceFallback: c(0xFF888888))

    public static let midnight = AppPalette(
        variant: .midnight, isDark: true, bg: c(0xFF0C0E13), panel: c(0xFF12151D), panel2: c(0xFF181C26), card: c(0xFF1C222E),
        line: c(0xFF2A303D), line2: c(0xFF38404F), tx: c(0xFFE9ECF3), tx2: c(0xFFAAB3C5), tx3: c(0xFF8A95AA),
        accent: c(0xFF6A86FF), accentTx: c(0xFFFFFFFF), titlebar: c(0xFF090B10),
        sel: rgba(106, 134, 255, 0.15), selLine: rgba(106, 134, 255, 0.5),
        red: c(0xFFEF6B63), orange: c(0xFFE59A4A), yellow: c(0xFFD8B850), green: c(0xFF4CC06B), amber: c(0xFFE3A63C),
        violet: c(0xFF9D8CFF), skel: rgba(255, 255, 255, 0.05), skel2: rgba(255, 255, 255, 0.10), scrim: c(0xFF000000),
        onScrim: c(0xFFFFFFFF), onColorInk: c(0xFF0B0D11), workspaceFallback: c(0xFF888888))

    public static func of(_ v: ThemeVariant) -> AppPalette {
        switch v { case .light: .light; case .dark: .dark; case .midnight: .midnight }
    }
    public func withAccent(_ argb: Int?) -> AppPalette {
        guard let argb else { return self }
        var p = self
        let col = Color(argb: UInt32(truncatingIfNeeded: argb))
        p.accent = col; p.sel = col.opacity(isDark ? 0.18 : 0.10); p.selLine = col.opacity(0.5)
        return p
    }
}

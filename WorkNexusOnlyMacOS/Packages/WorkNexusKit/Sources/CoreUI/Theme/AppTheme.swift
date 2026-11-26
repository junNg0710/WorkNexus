import AppKit
import CoreDomain
import SwiftUI

/// Design tokens, one value injected via `\.appTheme` (Flutter: AppColors / AppTypography / AppSpacing / AppRadii /
/// AppBorders / AppSizes / AppMotion ThemeExtensions). Views read `theme.colors.*`, never raw `Color`/numbers (rule 7).
public struct AppTheme: Sendable {
    public var colors: AppPalette
    public var spacing = AppSpacing()
    public var radii: AppRadii
    public var borders = AppBorders()
    public var sizes = AppSizes()
    public var motion = AppMotion()
    public var typography: AppTypography
    public var density: AppDensity
    public var surface: SurfaceStyle

    public init(settings: AppSettings = AppSettings(), systemIsDark: Bool = false) {
        var variant = settings.variant
        if settings.themeFollowsSystem { variant = systemIsDark ? (variant == .light ? .dark : variant) : .light }
        colors = AppPalette.of(variant).withAccent(settings.accentColorValue)
        radii = AppRadii(component: settings.componentRadius)
        // A terminal is set in one width: the Hacker theme takes the system's monospaced face unless a font was chosen.
        typography = AppTypography(family: settings.fontFamily, monospaced: variant == .hacker)
        density = settings.density
        surface = settings.surface
    }

    public var cardPadding: CGFloat { density == .compact ? spacing.s10 : spacing.s14 }
    public var colorScheme: ColorScheme { colors.isDark ? .dark : .light }
}

public struct AppSpacing: Sendable {
    public let s0: CGFloat = 0, s2: CGFloat = 2, s4: CGFloat = 4, s6: CGFloat = 6, s8: CGFloat = 8, s10: CGFloat = 10
    public let s12: CGFloat = 12, s14: CGFloat = 14, s16: CGFloat = 16, s20: CGFloat = 20, s24: CGFloat = 24, s40: CGFloat = 40
}

/// Everything scales from the user-set component radius (presets 0/4/8/12/16).
public struct AppRadii: Sendable {
    public let component: CGFloat
    public init(component: Double) { self.component = CGFloat(component) }
    public var xs: CGFloat { component * 0.5 }
    public var sm: CGFloat { component * 0.75 }
    public var md: CGFloat { component }
    public var lg: CGFloat { component * 1.5 }
    public var xl: CGFloat { component * 2.5 }
    public let dot: CGFloat = 999
    public let pill: CGFloat = 999
}

public struct AppBorders: Sendable {
    public let hairline: CGFloat = 1, medium: CGFloat = 1.5, thick: CGFloat = 2, heavy: CGFloat = 3
}

public struct AppSizes: Sendable {
    public let icon12: CGFloat = 12, icon14: CGFloat = 14, icon16: CGFloat = 16, icon18: CGFloat = 18, icon20: CGFloat = 20, icon24: CGFloat = 24
    public let control32: CGFloat = 32, control36: CGFloat = 36
    public let dialogSm: CGFloat = 400, dialogMd: CGFloat = 480, dialogLg: CGFloat = 640
    public let rail: CGFloat = 76
    public let toolPane: CGFloat = 300, toolPaneCompact: CGFloat = 240
    public let titleBar: CGFloat = 52          // macOS: traffic lights centred in it
    public let detailPanel: CGFloat = 460
    public let boardColumn: CGFloat = 272, boardColumnFolded: CGFloat = 44
}

public struct AppMotion: Sendable {
    public let fast: Double = 0.12, base: Double = 0.18, slow: Double = 0.25
    /// The tokens are constants: views that animate without reading the theme (a cheap row) use `AppMotion()` directly.
    public init() {}
}

public struct AppTypography: Sendable {
    public var family: String
    /// The system's monospaced face stands in for the system font (no family chosen).
    public var monospaced: Bool
    public init(family: String, monospaced: Bool = false) { self.family = family; self.monospaced = monospaced }

    /// Geist Mono is not bundled (Flutter downloads it through google_fonts): when it is not installed the monospaced
    /// system face stands in, so the choice still reads as a monospace UI.
    private static let geistMono = "Geist Mono"
    private static let geistMonoAvailable = NSFont(name: "GeistMono-Regular", size: 12) != nil || NSFont(name: "Geist Mono", size: 12) != nil

    private func f(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if family.isEmpty { return .system(size: size, weight: weight, design: monospaced ? .monospaced : .default) }
        if family == Self.geistMono, !Self.geistMonoAvailable { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(family, size: size).weight(weight)
    }
    public var display: Font { f(28, .bold) }
    public var title: Font { f(20, .semibold) }
    public var titleSm: Font { f(16, .semibold) }
    public var body: Font { f(14) }
    public var bodyStrong: Font { f(14, .semibold) }
    public var paragraph: Font { f(13) }
    public var prose: Font { f(15) }
    public var meta: Font { f(12) }
    public var metaStrong: Font { f(12, .medium) }
    public var caption: Font { f(11) }
    public var label: Font { f(12, .semibold) }
    public var badge: Font { f(10, .bold) }
    public var mono: Font { .custom("Space Mono", size: 12) }
}

private struct AppThemeKey: EnvironmentKey { static let defaultValue = AppTheme() }
public extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

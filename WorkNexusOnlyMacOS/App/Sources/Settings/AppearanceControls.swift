import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The appearance controls shared by the Appearance page and the quick-settings popover (lib/core/widgets/quick_settings_panel.dart):
/// theme (light / dark / midnight / hacker / system), primary colour, surface, font, corner radius and company tint.
struct AppearanceControls: View {
    @Environment(\.appTheme) private var theme
    let shell: ShellModel
    /// Geist Mono is listed as in the Flutter app; without the font installed the monospaced system face stands in.
    static let fonts = ["Space Grotesk", "Be Vietnam Pro", "Poppins", "Geist Mono", ""]

    var body: some View {
        let s = shell.settings
        VStack(alignment: .leading, spacing: theme.spacing.s14) {
            SettingsRow(label: appString("theme", "Theme")) {
                // nil follows the OS light / dark mode.
                SettingsSegmented(values: [(.light, appString("themeLight", "Light")), (.dark, appString("themeDark", "Dark")),
                                           (.midnight, appString("themeMidnight", "Midnight")), (.hacker, appString("themeHacker", "Hacker")),
                                           (nil, appString("themeSystem", "System"))] as [(ThemeVariant?, String)],
                                  value: s.themeFollowsSystem ? nil : s.variant) { v in
                    shell.updateSettings { if let v { $0.variant = v; $0.themeFollowsSystem = false } else { $0.themeFollowsSystem = true } }
                }
            }
            AccentPicker(shell: shell)
            SettingsRow(label: appString("surface", "Surface")) {
                SettingsSegmented(values: [(.flat, appString("surfaceFlat", "Flat")), (.outline, appString("surfaceOutline", "Outline"))] as [(SurfaceStyle, String)],
                                  value: s.surface) { v in shell.updateSettings { $0.surface = v } }
            }
            SettingsRow(label: appString("font", "Font")) {
                AppDropdown(value: s.fontFamily, values: Self.fonts, labelOf: { $0.isEmpty ? appString("fontSystem", "System") : $0 },
                            fontFamilyOf: { $0.isEmpty || $0 == "Geist Mono" ? nil : $0 }) { f in shell.updateSettings { $0.fontFamily = f } }
            }
            SettingsRow(label: appString("cornerRadius", "Corner radius")) {
                SettingsSlider(value: s.componentRadius, range: 0...16, step: 4, format: { "\(Int($0))" }) { v in
                    shell.updateSettings { $0.componentRadius = v }
                }
            }
            SettingsToggleRow(label: appString("companyTint", "Company tint"), isOn: s.companyTint) { on in
                shell.updateSettings { $0.companyTint = on }
            }
        }
    }
}

/// The primary colour: the theme's own accent ("default"), the 20 presets and a last swatch that opens the free picker
/// (showing the custom colour once one is chosen). Two even rows of 11.
struct AccentPicker: View {
    @Environment(\.appTheme) private var theme
    let shell: ShellModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 11)

    var body: some View {
        let selected = shell.settings.accentColorValue.map { UInt32(truncatingIfNeeded: $0) }
        let custom = selected.flatMap { AppPalette.accentPresets.contains($0) ? nil : $0 }
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            Text(appString("primaryColor", "Primary color")).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                AppSwatchButton(size: 24, color: AppPalette.of(theme.colors.variant).accent, selected: selected == nil,
                                help: appString("colorDefault", "Default")) { shell.updateSettings { $0.accentColorValue = nil } }
                ForEach(AppPalette.accentPresets, id: \.self) { argb in
                    AppSwatchButton(size: 24, color: Color(argb: argb), selected: selected == argb) {
                        shell.updateSettings { $0.accentColorValue = Int(argb) }
                    }
                }
                AppSwatchButton(size: 24, color: custom.map { Color(argb: $0) }, selected: custom != nil,
                                help: appString("colorCustom", "Custom color")) { shell.customAccentRequested = true }
            }
        }
    }
}

/// Density, detail layout, language and date format (the "Layout" and "Language & region" groups of the quick settings).
struct LayoutRegionControls: View {
    @Environment(\.appTheme) private var theme
    let shell: ShellModel

    var body: some View {
        let s = shell.settings
        VStack(alignment: .leading, spacing: theme.spacing.s14) {
            SettingsRow(label: appString("density", "Density")) {
                SettingsSegmented(values: [(.comfortable, appString("densityComfortable", "Comfortable")),
                                           (.compact, appString("densityCompact", "Compact"))] as [(AppDensity, String)],
                                  value: s.density) { v in shell.updateSettings { $0.density = v } }
            }
            SettingsRow(label: appString("detailLayout", "Detail layout")) {
                SettingsSegmented(values: [(.twoPane, appString("layoutTwoPane", "Two pane")), (.tabbed, appString("layoutDocument", "Document"))] as [(DetailLayout, String)],
                                  value: s.detailLayout) { v in shell.updateSettings { $0.detailLayout = v } }
            }
            LanguagePicker(shell: shell)
            SettingsRow(label: appString("dateFormat", "Date format")) {
                SettingsSegmented(values: [("iso", appString("dateFormatIso", "ISO")), ("dmy", appString("dateFormatDmy", "DD/MM")),
                                           ("long", appString("dateFormatLong", "Long"))], value: s.dateFormat) { v in
                    shell.updateSettings { $0.dateFormat = v }
                }
            }
        }
    }
}

/// The UI language (English / Vietnamese / Simplified Chinese), each listed by its own name. It acts at once: `AppLanguage` re-points the strings and the root rebuilds.
struct LanguagePicker: View {
    let shell: ShellModel

    var body: some View {
        let code = AppLanguage.supported.contains(shell.settings.localeCode) ? shell.settings.localeCode : "en"
        SettingsRow(label: appString("language", "Language")) {
            AppDropdown(value: code, values: AppLanguage.supported, labelOf: { AppLanguage.nativeName($0) }) { code in
                AppLanguage.apply(code)
                shell.updateSettings { $0.localeCode = code }
            }
        }
        // The app's own text follows at once; what macOS draws (the right-click menu on text, Services) only after a restart.
        if AppLanguage.systemMenusLag(behind: code) { LanguageRestartNote() }
    }
}

/// Under the language picker after a change: macOS's own menus keep the language the app started in until it restarts.
private struct LanguageRestartNote: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            Image(systemName: "info.circle").foregroundStyle(theme.colors.tx3)
            Text(appString("languageRestartHint", "macOS's own menus (right-click on text, Services) switch language after a restart."))
                .font(theme.typography.caption).foregroundStyle(theme.colors.tx2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: theme.spacing.s8)
            AppButton(appString("languageRestartNow", "Restart now"), kind: .ghost) { AppRelaunch.now() }
        }
    }
}

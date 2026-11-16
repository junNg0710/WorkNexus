import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// Ported from: lib/features/translation/presentation/widgets/translation_settings_card.dart
/// One collapsible card for everything translation: the target language and the one provider (with its model) that
/// translates. Collapsed it states what is in force (`Tiếng Việt · Google Gemini`).
struct TranslationSettingsPage: View {
    @Environment(\.appTheme) private var theme
    let root: CompositionRoot
    @State private var expanded = true
    @State private var saved: TranslationApiConfig?
    @State private var loadFailed = false
    @State private var loaded = false

    var body: some View {
        let shell = root.shell, s = shell.settings
        let backend = TranslationSettingsLogic.activePreset(saved)
        let summary = TranslationSettingsLogic.summary(languageName: translationLanguage(for: s.translationLang).nativeName,
                                                       backendName: TranslationApiForm.name(of: backend))
        SettingsPage(title: appString("translation", "Translation")) {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.easeOut(duration: theme.motion.base)) { expanded.toggle() } } label: {
                    HStack(spacing: theme.spacing.s12) {
                        Image(systemName: "character.bubble").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.accent)
                        VStack(alignment: .leading, spacing: theme.spacing.s2) {
                            Text(appString("translationSection", "Translation")).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx)
                            Text(summary).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0)).foregroundStyle(theme.colors.tx3)
                    }
                    .padding(theme.spacing.s16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    TranslationSection(title: appString("translationLanguageSection", "Translation language"),
                                       hint: appString("translationLanguageSubtitle", "The language tickets and chat messages are translated into.")) {
                        TranslationLanguageControl(value: s.translationLang) { v in shell.updateSettings { $0.translationLang = v } }
                    }
                    TranslationSection(title: appString("translationProviderSection", "Translation provider"),
                                       hint: appString("translationProviderSubtitle", "Who translates tickets and chat messages. OpenCode uses the CLI and its login; the others use your own API key.")) {
                        if loaded {
                            TranslationApiForm(root: root, saved: saved, loadFailed: loadFailed) { saved = $0 }
                        } else { AppInlineSpinner() }
                    }
                }
            }
            .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
        .task { await load() }
    }

    private func load() async {
        switch await root.translation.apiConfig.load() {
        case .success(let cfg): saved = cfg
        case .failure: loadFailed = true
        }
        loaded = true
    }
}

/// A titled block inside the card: `trailing` sits beside the title (a short control), the content below it (a form).
private struct TranslationSection<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let hint: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            Divider().overlay(theme.colors.line).padding(.horizontal, -theme.spacing.s16)
            Text(title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).padding(.top, theme.spacing.s12)
            Text(hint).font(theme.typography.caption).foregroundStyle(theme.colors.tx3).fixedSize(horizontal: false, vertical: true)
            content.padding(.top, theme.spacing.s8)
        }
        .padding(.horizontal, theme.spacing.s16).padding(.bottom, theme.spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

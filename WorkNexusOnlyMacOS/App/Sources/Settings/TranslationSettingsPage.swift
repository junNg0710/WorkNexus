import CoreDomain
import CoreUI
import FeatureTranslation
import SwiftUI

/// Ported from: lib/features/translation/presentation/widgets/translation_settings_card.dart (several providers and a choice
/// per purpose: not in the Flutter app)
/// One collapsible card for everything AI: the providers (OpenCode built in, plus endpoints saved with a key), what translation
/// runs on (language, provider, model) and what AI in chat runs on. Collapsed it states what translates
/// (`Tiếng Việt · OpenAI (gpt-5-mini)`).
struct TranslationSettingsPage: View {
    @Environment(\.appTheme) private var theme
    let root: CompositionRoot
    @State private var expanded = true

    var body: some View {
        let shell = root.shell, s = shell.settings, store = root.aiSetup
        let summary = TranslationSettingsLogic.summary(languageName: translationLanguage(for: s.translationLang).nativeName,
                                                       backendName: store.backendName(.translation, legacyModel: s.translationModel))
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
                    if store.loaded {
                        if store.loadFailed {
                            AppInlineNote(appString("aiSetupLoadFailed", "Couldn't read the saved AI providers. Everything runs on OpenCode until you save them again."), isError: true)
                                .padding(.horizontal, theme.spacing.s16).padding(.bottom, theme.spacing.s12)
                        }
                        TranslationSection(title: appString("aiProvidersSection", "AI providers"),
                                           hint: appString("aiProvidersSubtitle", "OpenCode and Claude Code use their own CLI login, no key needed; the others use your own API key, kept in the Keychain. Save as many as you like.")) {
                            AiProvidersSection(root: root)
                        }
                        TranslationSection(title: appString("translationProviderSection", "Translation provider"),
                                           hint: appString("aiTranslationSubtitle", "The language tickets and chat messages are translated into, and who translates them.")) {
                            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                                FieldBlock(label: appString("translationLanguage", "Translation language")) {
                                    TranslationLanguageControl(value: s.translationLang) { v in shell.updateSettings { $0.translationLang = v } }
                                }
                                AiModelChoiceFields(root: root, purpose: .translation)
                            }
                        }
                        TranslationSection(title: appString("aiChatSection", "AI in chat"),
                                           hint: appString("aiChatSubtitle", "Who writes chat summaries, reply ideas and rewrites (✨).")) {
                            AiChatChoiceSection(root: root)
                        }
                    } else {
                        AppInlineSpinner().padding(theme.spacing.s16)
                    }
                }
            }
            .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
        .task { if !root.aiSetup.loaded { await root.aiSetup.load() } }
    }
}

/// A titled block inside the card: a title and hint over its content.
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

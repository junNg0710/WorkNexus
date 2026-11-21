/// Ported from: lib/features/chat/presentation/providers/message_translation_controller.dart + message_translation_view.dart
import CoreDomain
import CoreUI
import Observation
import SwiftUI

/// The translations shown under messages of one thread: running, failed, or done. A stored translation that was left
/// visible comes back when its message is shown.
@MainActor @Observable
final class MessageTranslationController {
    enum Entry: Equatable { case loading, failed(String), done(ChatMessageTranslation) }

    private(set) var entries: [String: Entry] = [:]
    /// The language each shown translation is in (one picked for a message can differ from the usual one).
    private var langs: [String: String] = [:]
    private var restored: Set<String> = []
    let services: ChatServices
    init(services: ChatServices) { self.services = services }

    /// Whether the thread can translate at all (a translator and a store are wired).
    var available: Bool { services.translator != nil && services.translations != nil }

    /// The languages a message can be translated into (Settings › Translation lists them).
    var languages: [ChatAiLanguage] { services.aiLanguages }

    /// The language of the translation shown under `gid`, if one is.
    func language(of gid: String) -> String? { entries[gid] == nil ? nil : langs[gid] }

    /// `code`'s flag and name ("🇨🇳 中文"), when it is a known language.
    func label(of code: String) -> String? { languages.first { $0.code == code }.map { "\($0.flag) \($0.nativeName)" } }

    /// Whether a translation is shown (or being fetched) under `gid`.
    func isShown(_ gid: String) -> Bool { entries[gid] != nil }
    func hasDone(_ gid: String) -> Bool { if case .done = entries[gid] { true } else { false } }

    /// Reads the stored translation of `message` once, so one left visible shows again.
    func restore(_ message: ChatMessage, lang: String) async {
        guard let store = services.translations, message.content.asText != nil, restored.insert(message.gid).inserted else { return }
        if case .success(let t?) = await store.find(accountId: message.accountId, gid: message.gid, targetLang: lang), t.visible, entries[message.gid] == nil {
            entries[message.gid] = .done(t); langs[message.gid] = lang
        }
    }

    /// Translates `message` (a stored translation is reused unless `force`).
    func translate(_ message: ChatMessage, lang: String, model: String, force: Bool = false) async {
        guard let store = services.translations, let service = services.translator else { return }
        // Not linked: the host explains how to link OpenCode; nothing starts.
        if let ready = services.ensureTranslatorReady, !(await ready()) { return }
        // A translation shown in another language is hidden (it stays stored), so only one shows under the message.
        if let shown = langs[message.gid], shown != lang, entries[message.gid] != nil {
            _ = await store.setVisible(accountId: message.accountId, gid: message.gid, targetLang: shown, visible: false)
        }
        entries[message.gid] = .loading; langs[message.gid] = lang
        let result = await TranslateChatMessage(store, service)(message, targetLang: lang, model: model.isEmpty ? nil : model, force: force)
        switch result {
        case .success(let t): entries[message.gid] = .done(t)
        case .failure(let f): entries[message.gid] = .failed(f.message)
        }
    }

    /// Hides the translation under `message` (it stays stored).
    func hide(_ message: ChatMessage, lang: String) async {
        let shown = langs[message.gid] ?? lang
        entries[message.gid] = nil; langs[message.gid] = nil
        _ = await services.translations?.setVisible(accountId: message.accountId, gid: message.gid, targetLang: shown, visible: false)
    }
}

/// The translation of a message, under its text — a spinner while it runs, the translated text, or the reason it failed.
/// Nothing until one is requested.
struct MessageTranslationView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    @Environment(\.chatSettings) private var settings
    let controller: MessageTranslationController
    let message: ChatMessage

    var body: some View {
        let entry = controller.entries[message.gid]
        Group {
            if let entry {
                let font = theme.typography.font(size: ink.fontSize)
                VStack(alignment: .leading, spacing: theme.spacing.s6) {
                    switch entry {
                    case .loading:
                        HStack(spacing: theme.spacing.s8) {
                            ProgressView().controlSize(.small)
                            Text(L.translating).font(font).italic().foregroundStyle(ink.meta.color)
                        }
                    case .failed(let error):
                        Text(L.translateFailed(error)).font(font).italic().foregroundStyle(ink.meta.color)
                    case .done(let t):
                        Text(t.text).font(font).foregroundStyle(ink.text.color).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        // A language picked for this message says which it is.
                        let other = t.targetLang == settings.translationLang ? nil : controller.label(of: t.targetLang)
                        Text([other, L.translatedBy(t.model ?? "OpenCode")].compactMap { $0 }.joined(separator: " · "))
                            .font(theme.typography.caption).foregroundStyle(ink.meta.color)
                    }
                }
                .padding(theme.spacing.s10)
                .background(ink.meta.opacity(0.1).color, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(ink.meta.opacity(0.3).color, lineWidth: theme.borders.hairline))
                .padding(.top, theme.spacing.s6)
            }
        }
        .task(id: message.gid) { await controller.restore(message, lang: settings.translationLang) }
    }
}

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
    private var restored: Set<String> = []
    let services: ChatServices
    init(services: ChatServices) { self.services = services }

    /// Whether the thread can translate at all (a translator and a store are wired).
    var available: Bool { services.translator != nil && services.translations != nil }

    /// Whether a translation is shown (or being fetched) under `gid`.
    func isShown(_ gid: String) -> Bool { entries[gid] != nil }
    func hasDone(_ gid: String) -> Bool { if case .done = entries[gid] { true } else { false } }

    /// Reads the stored translation of `message` once, so one left visible shows again.
    func restore(_ message: ChatMessage, lang: String) async {
        guard let store = services.translations, message.content.asText != nil, restored.insert(message.gid).inserted else { return }
        if case .success(let t?) = await store.find(accountId: message.accountId, gid: message.gid, targetLang: lang), t.visible, entries[message.gid] == nil {
            entries[message.gid] = .done(t)
        }
    }

    /// Translates `message` (a stored translation is reused unless `force`).
    func translate(_ message: ChatMessage, lang: String, model: String, force: Bool = false) async {
        guard let store = services.translations, let service = services.translator else { return }
        // Not linked: the host explains how to link OpenCode; nothing starts.
        if let ready = services.ensureTranslatorReady, !(await ready()) { return }
        entries[message.gid] = .loading
        let result = await TranslateChatMessage(store, service)(message, targetLang: lang, model: model.isEmpty ? nil : model, force: force)
        switch result {
        case .success(let t): entries[message.gid] = .done(t)
        case .failure(let f): entries[message.gid] = .failed(f.message)
        }
    }

    /// Hides the translation under `message` (it stays stored).
    func hide(_ message: ChatMessage, lang: String) async {
        entries[message.gid] = nil
        _ = await services.translations?.setVisible(accountId: message.accountId, gid: message.gid, targetLang: lang, visible: false)
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
                        Text(L.translatedBy(t.model ?? "OpenCode")).font(theme.typography.caption).foregroundStyle(ink.meta.color)
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

import CoreDomain
import Foundation

/// Ported from: lib/features/translation/data/routing_translation_service.dart
/// Translates through the user's API key when one is set up and enabled, and through the OpenCode CLI otherwise.
public final class RoutingTranslationService: TranslationService, @unchecked Sendable {
    private let api: TranslationService
    private let openCode: TranslationService
    private let config: @Sendable () async -> TranslationApiConfig?
    /// Which backend each in-flight run went to, so `cancel` reaches it even when the setting changed meanwhile.
    private let inFlight = Locked<[String: TranslationService]>([:])

    public init(api: TranslationService, openCode: TranslationService, config: @escaping @Sendable () async -> TranslationApiConfig?) {
        self.api = api; self.openCode = openCode; self.config = config
    }

    private func pick() async -> TranslationService { (await config())?.isUsable == true ? api : openCode }
    private func register(_ key: String, _ backend: TranslationService) { inFlight.withLock { $0[key] = backend } }
    private func unregister(_ key: String) { inFlight.withLock { $0[key] = nil } }

    public func contentHash(_ source: TicketSource) -> String { openCode.contentHash(source) }

    public func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String,
                          model: String?) async -> Outcome<TranslationRecord> {
        let backend = await pick()
        register(ticketId, backend)
        defer { unregister(ticketId) }
        return await backend.translate(ticketId: ticketId, source: source, sourceHash: sourceHash, targetLang: targetLang, model: model)
    }

    public func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> {
        let backend = await pick()
        register(key, backend)
        defer { unregister(key) }
        return await backend.translateText(key: key, text: text, targetLang: targetLang, model: model)
    }

    public func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> {
        let backend = await pick()
        register(key, backend)
        defer { unregister(key) }
        return await backend.complete(key: key, prompt: prompt, model: model)
    }

    public func cancel(_ ticketId: String) async {
        await inFlight.withLock { $0[ticketId] }?.cancel(ticketId)
    }
}

import CoreDomain
import Foundation

/// Ported from: lib/features/translation/data/routing_translation_service.dart
/// Sends each run to the backend its purpose is set up with (several providers and a choice per purpose: not in the Flutter
/// app): `translate` / `translateText` follow the translation choice, `complete` (chat's AI help) the chat choice. A saved
/// provider runs through the API backend with that provider's key and the chosen model; OpenCode runs through the CLI with
/// the chosen model, or the one the caller passed when the choice has none.
public final class RoutingTranslationService: TranslationService, @unchecked Sendable {
    private let api: ConfiguredTranslationBackend
    private let openCode: TranslationService
    private let claudeCode: TranslationService
    private let setup: @Sendable () async -> AiSetup
    private let resolve = ResolveAiBackend()
    /// Which backend each in-flight run went to, so `cancel` reaches it even when the setting changed meanwhile.
    private let inFlight = Locked<[String: @Sendable (String) async -> Void]>([:])

    public init(api: ConfiguredTranslationBackend, openCode: TranslationService, claudeCode: TranslationService = ClaudeCodeTranslationService(),
                setup: @escaping @Sendable () async -> AiSetup) {
        self.api = api; self.openCode = openCode; self.claudeCode = claudeCode; self.setup = setup
    }

    private func backend(_ purpose: AiPurpose, _ model: String?) async -> AiBackend {
        resolve(await setup(), purpose: purpose, callerModel: model)
    }

    /// Runs `body` with `key` registered against the backend that serves it, so a cancel meanwhile reaches that backend.
    private func tracked<T>(_ key: String, _ backend: AiBackend, _ body: () async -> T) async -> T {
        let api = api, openCode = openCode, claudeCode = claudeCode
        let cancel: @Sendable (String) async -> Void = switch backend {
        case .api: { await api.cancel($0) }
        case .openCode: { await openCode.cancel($0) }
        case .claudeCode: { await claudeCode.cancel($0) }
        }
        inFlight.withLock { $0[key] = cancel }
        defer { inFlight.withLock { $0[key] = nil } }
        return await body()
    }

    public func contentHash(_ source: TicketSource) -> String { openCode.contentHash(source) }

    public func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String,
                          model: String?) async -> Outcome<TranslationRecord> {
        let b = await backend(.translation, model)
        return await tracked(ticketId, b) {
            switch b {
            case .api(_, let config):
                await api.translate(ticketId: ticketId, source: source, sourceHash: sourceHash, targetLang: targetLang, config: config)
            case .openCode(let m):
                await openCode.translate(ticketId: ticketId, source: source, sourceHash: sourceHash, targetLang: targetLang, model: m)
            case .claudeCode(let m):
                await claudeCode.translate(ticketId: ticketId, source: source, sourceHash: sourceHash, targetLang: targetLang, model: m)
            }
        }
    }

    public func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> {
        let b = await backend(.translation, model)
        return await tracked(key, b) {
            switch b {
            case .api(_, let config): await api.translateText(key: key, text: text, targetLang: targetLang, config: config)
            case .openCode(let m): await openCode.translateText(key: key, text: text, targetLang: targetLang, model: m)
            case .claudeCode(let m): await claudeCode.translateText(key: key, text: text, targetLang: targetLang, model: m)
            }
        }
    }

    /// Chat's AI help: runs on the chat choice (the translation one unless AI in chat has its own).
    public func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> {
        let b = await backend(.chat, model)
        return await tracked(key, b) {
            switch b {
            case .api(_, let config): await api.complete(key: key, prompt: prompt, config: config)
            case .openCode(let m): await openCode.complete(key: key, prompt: prompt, model: m)
            case .claudeCode(let m): await claudeCode.complete(key: key, prompt: prompt, model: m)
            }
        }
    }

    public func cancel(_ ticketId: String) async {
        await inFlight.withLock { $0[ticketId] }?(ticketId)
    }
}

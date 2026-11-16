import CoreDomain

/// Ported from: lib/features/translation/domain/adapters/translation_service.dart
/// The translatable content of a ticket.
public struct TicketSource: Sendable, Equatable {
    public var title: String
    public var body: String
    public init(title: String, body: String) { self.title = title; self.body = body }
}

/// A free-form text translation and the model that produced it — which may differ from the one asked for when the
/// user's API key is in charge. `model` is nil when the backend picked its own default and did not say which.
public struct TextTranslation: Sendable, Equatable {
    public var text: String
    public var model: String?
    public init(_ text: String, model: String? = nil) { self.text = text; self.model = model }
}

/// Produces a translation of a ticket (or a chat message) into a chosen language. Caching and state are orchestrated by
/// `ResolveTranslationState` + `TranslationRepository`; this only performs the translation. Implementations must not run
/// forever — a stalled backend has to come back as a `Failure` so the UI can leave its loading state.
public protocol TranslationService: Sendable {
    /// Stable content hash used both to key the cache and to detect outdatedness.
    func contentHash(_ source: TicketSource) -> String

    /// `model` pins the `provider/model` to translate with; nil leaves the choice to the backend's own default.
    func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String,
                   model: String?) async -> Outcome<TranslationRecord>

    /// `key` identifies the run so `cancel` can stop it. Nothing is cached — the caller owns the result.
    func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation>

    /// Aborts the in-flight translation for `ticketId`; a no-op when there is none. The pending call still completes (with a failure).
    func cancel(_ ticketId: String) async
}

import Foundation

/// Ported from: lib/features/translation/domain/entities/translation_record.dart
/// A cached, successful translation of a ticket's title + body. The cache is keyed on `sourceHash`; when the ticket's
/// current content hash differs from this, the translation is considered outdated.
public struct TranslationRecord: Sendable, Equatable {
    public var ticketId: String
    public var sourceHash: String
    public var targetLang: String
    public var translatedTitle: String
    public var translatedBody: String
    public var model: String
    public var templateVersion: String
    public var createdAt: Date

    public init(ticketId: String, sourceHash: String, targetLang: String, translatedTitle: String, translatedBody: String,
                model: String, templateVersion: String, createdAt: Date) {
        self.ticketId = ticketId; self.sourceHash = sourceHash; self.targetLang = targetLang
        self.translatedTitle = translatedTitle; self.translatedBody = translatedBody; self.model = model
        self.templateVersion = templateVersion; self.createdAt = createdAt
    }
}

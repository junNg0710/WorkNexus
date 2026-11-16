/// Ported from: lib/features/translation/data/mappers/translation_mappers.dart
extension TranslationRecord {
    init(row r: TranslationRow) {
        self.init(ticketId: r.ticketId, sourceHash: r.sourceHash, targetLang: r.targetLang, translatedTitle: r.translatedTitle,
                  translatedBody: r.translatedBody, model: r.model, templateVersion: r.templateVersion, createdAt: r.createdAt)
    }
}

extension TranslationRow {
    init(record t: TranslationRecord) {
        self.init(ticketId: t.ticketId, sourceHash: t.sourceHash, targetLang: t.targetLang, translatedTitle: t.translatedTitle,
                  translatedBody: t.translatedBody, model: t.model, templateVersion: t.templateVersion, createdAt: t.createdAt)
    }
}

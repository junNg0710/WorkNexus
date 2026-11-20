import Foundation

/// Ported from: lib/features/translation/data/translation_prompts.dart
/// Prompts and reply parsing shared by every translation backend, so a ticket or chat message is asked for the same way
/// whichever one runs it.
func ticketPrompt(_ s: TicketSource, _ languageName: String) -> String {
    "Translate this software ticket into natural, technical \(languageName). "
        + "Preserve code, identifiers, file paths, URLs and Markdown. "
        // A ZenTao body is HTML: its tags are the layout (lists, bold, images) and must come back as they went.
        + "If the body is HTML, keep every tag and attribute exactly as it is and translate only the text between the tags. "
        // Seen with a Chinese ticket: the model polished the Chinese instead of translating it.
        + "The source may be Chinese or another language: write the title and body in \(languageName), never in the source language. "
        + "Return ONLY a JSON object with keys \"title\" and \"body\".\n"
        + "Title: <<<\(s.title)>>>\nBody: <<<\(s.body)>>>"
}

func textPrompt(_ text: String, _ languageName: String) -> String {
    "Translate this chat message into natural \(languageName). "
        + "Preserve code, identifiers, URLs, emoji, @mentions and Markdown. "
        + "Write it in \(languageName) whatever language it is in. "
        + "Return ONLY the translation, with no preface or quotes.\n"
        + "Message: <<<\(text)>>>"
}

/// The `{"title", "body"}` object in a model reply, which may wrap it in prose or a code fence; nil when there is none.
func extractTicketJson(_ out: String) -> [String: Any]? {
    guard let start = out.firstIndex(of: "{"), let end = out.lastIndex(of: "}"), start < end else { return nil }
    guard let data = String(out[start...end]).data(using: .utf8),
          let decoded = try? JSONSerialization.jsonObject(with: data) else { return nil }
    return decoded as? [String: Any]
}

/// `parsed[key]` as Dart's `toString()` would show it (nil and JSON null → nil).
func stringValue(_ parsed: [String: Any], _ key: String) -> String? {
    guard let v = parsed[key], !(v is NSNull) else { return nil }
    if let s = v as? String { return s }
    return "\(v)"
}

/// The record for a reply that parsed into a ticket translation.
func ticketRecord(parsed: [String: Any], ticketId: String, source: TicketSource, sourceHash: String, lang: String,
                  model: String, templateVersion: String) -> TranslationRecord {
    TranslationRecord(ticketId: ticketId, sourceHash: sourceHash, targetLang: lang,
                      translatedTitle: stringValue(parsed, "title") ?? source.title,
                      translatedBody: stringValue(parsed, "body") ?? source.body,
                      model: model, templateVersion: templateVersion, createdAt: Date())
}

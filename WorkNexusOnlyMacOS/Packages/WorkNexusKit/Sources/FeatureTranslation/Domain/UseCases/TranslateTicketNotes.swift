import CoreDomain
import Foundation

/// A comment or a history note of a ticket, to translate along with it: its id among the ticket's notes, and its text
/// as the provider keeps it (HTML for ZenTao, Markdown elsewhere).
public struct TicketNote: Sendable, Equatable {
    public var id: String
    public var text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}

/// Not in the Flutter app. Translates the comments and history notes of a ticket - what a ticket's own translation
/// (title and body) left in the source language.
///
/// All the notes that have no translation yet go out in one request and each is kept on its own (in the translations
/// cache, under the ticket's id and the note's), so a ticket translated again after a new comment asks only for that
/// comment. A note whose text changed counts as not translated.
public struct TranslateTicketNotes: Sendable {
    private let service: TranslationService
    private let repository: TranslationRepository

    public static let templateVersion = "notes-1"
    /// How many notes one request carries: a long history goes out in several.
    public static let batch = 20

    public init(service: TranslationService, repository: TranslationRepository) {
        self.service = service; self.repository = repository
    }

    /// Where a note's translation is kept.
    public static func recordId(ticketId: String, noteId: String) -> String { "\(ticketId)#note:\(noteId)" }

    /// The translations kept for `notes` in `targetLang` whose text has not changed since, by note id.
    public func kept(ticketId: String, notes: [TicketNote], targetLang: String) async -> [String: String] {
        var out: [String: String] = [:]
        for note in notes {
            guard case .success(let record?) = await repository.translation(ticketId: Self.recordId(ticketId: ticketId, noteId: note.id)),
                  record.targetLang == targetLang, record.sourceHash == hash(note) else { continue }
            out[note.id] = record.translatedBody
        }
        return out
    }

    /// Translates the notes that `kept` lacks, keeps them, and returns every translation there is now. A request that
    /// fails leaves what was translated before it in place and reports the failure.
    public func callAsFunction(ticketId: String, notes: [TicketNote], targetLang: String, model: String?) async -> Outcome<[String: String]> {
        var done = await kept(ticketId: ticketId, notes: notes, targetLang: targetLang)
        let missing = notes.filter { done[$0.id] == nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let language = translationLanguage(for: targetLang).englishName
        var start = 0
        while start < missing.count {
            let part = Array(missing[start..<min(start + Self.batch, missing.count)])
            start += part.count
            switch await service.complete(key: ticketId, prompt: Self.prompt(part, languageName: language), model: model) {
            case .failure(let failure): return .failure(failure)
            case .success(let reply):
                guard let texts = Self.parse(reply.text, count: part.count) else {
                    return .failure(.parse("The translation of the comments came back in a form that could not be read"))
                }
                for (note, text) in zip(part, texts) {
                    guard let text else { continue }
                    let record = TranslationRecord(ticketId: Self.recordId(ticketId: ticketId, noteId: note.id), sourceHash: hash(note),
                                                   targetLang: targetLang, translatedTitle: "", translatedBody: text,
                                                   model: reply.model ?? model ?? "", templateVersion: Self.templateVersion, createdAt: Date())
                    _ = await repository.saveTranslation(record)
                    done[note.id] = text
                }
            }
        }
        return .success(done)
    }

    private func hash(_ note: TicketNote) -> String { service.contentHash(TicketSource(title: "", body: note.text)) }

    /// The request for `notes`: each under a number, the reply a JSON object of those numbers.
    static func prompt(_ notes: [TicketNote], languageName: String) -> String {
        var out = "Translate each of these comments on a software ticket into natural, technical \(languageName). "
            + "Preserve code, identifiers, file paths, URLs, @mentions and Markdown. "
            + "If a comment is HTML, keep every tag and attribute exactly as it is and translate only the text between the tags. "
            + "The source may be Chinese or another language: write every translation in \(languageName), never in the source language. "
            + "Return ONLY a JSON object whose keys are the comment numbers as strings and whose values are the translations.\n"
        for (index, note) in notes.enumerated() { out += "Comment \(index + 1): <<<\(note.text)>>>\n" }
        return out
    }

    /// The translations in a reply, in the order asked (nil where the reply left one out); nil when it holds no JSON object.
    static func parse(_ reply: String, count: Int) -> [String?]? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let object = (try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8))) as? [String: Any] else { return nil }
        return (1...max(count, 1)).prefix(count).map { number in
            (object["\(number)"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
    }
}

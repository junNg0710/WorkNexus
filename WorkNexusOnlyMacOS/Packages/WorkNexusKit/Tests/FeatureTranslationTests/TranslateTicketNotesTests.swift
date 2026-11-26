// Not in the Flutter app: a ticket's comments and history notes are translated with it, each kept on its own.
import CoreDomain
import XCTest
@testable import FeatureTranslation

private final class NotesService: TranslationService, @unchecked Sendable {
    var prompts: [String] = []
    var reply: Outcome<TextTranslation> = .success(TextTranslation("{}", model: "m1"))
    func contentHash(_ source: TicketSource) -> String { "h:\(source.title)|\(source.body)" }
    func translate(ticketId: String, source: TicketSource, sourceHash: String, targetLang: String, model: String?) async -> Outcome<TranslationRecord> {
        .failure(.unexpected("not used"))
    }
    func translateText(key: String, text: String, targetLang: String, model: String?) async -> Outcome<TextTranslation> { .failure(.unexpected("not used")) }
    func complete(key: String, prompt: String, model: String?) async -> Outcome<TextTranslation> { prompts.append(prompt); return reply }
    func cancel(_ ticketId: String) async {}
}

private final class NotesStore: TranslationRepository, @unchecked Sendable {
    var records: [String: TranslationRecord] = [:]
    func watchTranslation(ticketId: String) -> AsyncStream<TranslationRecord?> { AsyncStream { $0.finish() } }
    func translation(ticketId: String) async -> Outcome<TranslationRecord?> { .success(records[ticketId]) }
    func saveTranslation(_ record: TranslationRecord) async -> Outcome<Void> { records[record.ticketId] = record; return .success(()) }
}

final class TranslateTicketNotesTests: XCTestCase {
    private let notes = [TicketNote(id: "c1", text: "<p>Please recheck</p>"), TicketNote(id: "e2", text: "Fixed in build 5")]

    func testEveryNoteGoesOutInOneRequestAndIsKeptOnItsOwn() async {
        let service = NotesService(), store = NotesStore()
        service.reply = .success(TextTranslation("Here you go:\n```json\n{\"1\": \"<p>Vui lòng kiểm tra lại</p>\", \"2\": \"Đã sửa ở bản 5\"}\n```", model: "m1"))
        let done = await TranslateTicketNotes(service: service, repository: store)(ticketId: "t1", notes: notes, targetLang: "vi", model: nil)
        XCTAssertEqual(done.value, ["c1": "<p>Vui lòng kiểm tra lại</p>", "e2": "Đã sửa ở bản 5"])
        XCTAssertEqual(service.prompts.count, 1)
        XCTAssertTrue(service.prompts[0].contains("into natural, technical Vietnamese"))
        XCTAssertTrue(service.prompts[0].contains("Comment 1: <<<<p>Please recheck</p>>>>"))
        XCTAssertTrue(service.prompts[0].contains("Comment 2: <<<Fixed in build 5>>>"))
        let record = store.records["t1#note:c1"]
        XCTAssertEqual(record?.translatedBody, "<p>Vui lòng kiểm tra lại</p>")
        XCTAssertEqual(record?.targetLang, "vi")
        XCTAssertEqual(record?.model, "m1")
        XCTAssertNil(store.records["t1"], "the ticket's own translation is another record")
    }

    func testOnlyWhatIsNotTranslatedYetIsAskedFor() async {
        let service = NotesService(), store = NotesStore()
        let use = TranslateTicketNotes(service: service, repository: store)
        service.reply = .success(TextTranslation("{\"1\": \"một\", \"2\": \"hai\"}"))
        _ = await use(ticketId: "t1", notes: notes, targetLang: "vi", model: nil)
        // A new comment, and one whose text changed.
        let later = [notes[0], TicketNote(id: "e2", text: "Fixed in build 6"), TicketNote(id: "c3", text: "Thanks")]
        let kept = await use.kept(ticketId: "t1", notes: later, targetLang: "vi")
        XCTAssertEqual(kept, ["c1": "một"], "a changed text is not translated any more")
        service.reply = .success(TextTranslation("{\"1\": \"sửa ở bản 6\", \"2\": \"cảm ơn\"}"))
        let done = await use(ticketId: "t1", notes: later, targetLang: "vi", model: nil)
        XCTAssertEqual(done.value, ["c1": "một", "e2": "sửa ở bản 6", "c3": "cảm ơn"])
        XCTAssertEqual(service.prompts.count, 2)
        XCTAssertFalse(service.prompts[1].contains("Please recheck"), "the comment already translated is left out")
        // Nothing new: no request at all.
        _ = await use(ticketId: "t1", notes: later, targetLang: "vi", model: nil)
        XCTAssertEqual(service.prompts.count, 2)
        // Another language starts over.
        let english = await use.kept(ticketId: "t1", notes: later, targetLang: "en")
        XCTAssertTrue(english.isEmpty)
    }

    func testAReplyThatLeavesOneOutKeepsTheOthersAndAnUnreadableOneFails() async {
        let service = NotesService(), store = NotesStore()
        let use = TranslateTicketNotes(service: service, repository: store)
        service.reply = .success(TextTranslation("{\"2\": \"hai\"}"))
        let partial = await use(ticketId: "t1", notes: notes, targetLang: "vi", model: nil)
        XCTAssertEqual(partial.value, ["e2": "hai"])
        service.reply = .success(TextTranslation("sorry, I cannot"))
        let unreadable = await use(ticketId: "t2", notes: notes, targetLang: "vi", model: nil)
        XCTAssertNotNil(unreadable.failure)
        service.reply = .failure(.network("offline"))
        let offline = await use(ticketId: "t3", notes: notes, targetLang: "vi", model: nil)
        XCTAssertEqual(offline.failure, .network("offline"))
    }

    func testEmptyNotesAreNotSentAndALongHistoryGoesOutInBatches() async {
        let service = NotesService(), store = NotesStore()
        let use = TranslateTicketNotes(service: service, repository: store)
        _ = await use(ticketId: "t1", notes: [TicketNote(id: "c1", text: "  \n")], targetLang: "vi", model: nil)
        XCTAssertTrue(service.prompts.isEmpty)
        let many = (1...(TranslateTicketNotes.batch + 3)).map { TicketNote(id: "c\($0)", text: "note \($0)") }
        service.reply = .success(TextTranslation("{}"))
        _ = await use(ticketId: "t2", notes: many, targetLang: "vi", model: nil)
        XCTAssertEqual(service.prompts.count, 2)
        XCTAssertTrue(service.prompts[1].contains("Comment 3: <<<note \(TranslateTicketNotes.batch + 3)>>>"))
    }
}

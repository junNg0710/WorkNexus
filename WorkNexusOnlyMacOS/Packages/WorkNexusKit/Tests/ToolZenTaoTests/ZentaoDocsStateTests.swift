import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import ToolZenTao

/// An in-memory `ZenTaoDocRepository`: what its `refresh*` calls were asked and what its `watch*` streams answer.
final class FakeDocRepo: ZenTaoDocRepository, @unchecked Sendable {
    private let lock = NSLock()
    var libs: [ZenTaoDocLib] = []
    var docs: [String: [ZenTaoDocSummary]] = [:]
    var doc: ZenTaoDoc?
    var history: [ZenTaoDocAction] = []
    var pins = ZenTaoDocPins()
    var refreshResult: Outcome<Void> = .success(())
    private(set) var calls: [String] = []
    private(set) var savedPins: [ZenTaoDocPins] = []

    private func note(_ s: String) { lock.withLock { calls.append(s) } }
    private func once<T: Sendable>(_ v: T) -> AsyncStream<T> { AsyncStream { $0.yield(v); $0.finish() } }

    func watchLibs(accountId: String) -> AsyncStream<[ZenTaoDocLib]> { once(libs) }
    func watchDocs(accountId: String, libId: String) -> AsyncStream<[ZenTaoDocSummary]> { once(docs[libId] ?? []) }
    func watchDoc(accountId: String, docId: String) -> AsyncStream<ZenTaoDoc?> { once(doc) }
    func refreshLibs(account: Account) async -> Outcome<Void> { note("libs"); return refreshResult }
    func refreshDocs(account: Account, libId: String) async -> Outcome<Void> { note("docs:\(libId)"); return refreshResult }
    func refreshDoc(account: Account, docId: String) async -> Outcome<Void> { note("doc:\(docId)"); return refreshResult }
    func watchHistory(accountId: String, docId: String) -> AsyncStream<[ZenTaoDocAction]> { once(history) }
    func refreshHistory(account: Account, docId: String) async -> Outcome<Void> { note("history:\(docId)"); return refreshResult }
    func watchPins(accountId: String) -> AsyncStream<ZenTaoDocPins> { once(pins) }
    func savePins(accountId: String, pins: ZenTaoDocPins) async -> Outcome<Void> { lock.withLock { savedPins.append(pins) }; return .success(()) }
    func fetchImage(account: Account, url: String) async -> Data? { nil }
    func readFile(account: Account, file: TicketAttachment) async -> Outcome<Data> { .success(Data()) }
    func saveFile(account: Account, file: TicketAttachment) async -> Outcome<String> { .success("/tmp/x") }
    func readBackup(accountId: String, docId: String) async -> Outcome<String> { .success("{}") }
    func saveText(fileName: String, text: String) async -> Outcome<String> { .success("/tmp/\(fileName)") }
}

final class FakeSettingsRepo: SettingsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var value: AppSettings
    private(set) var saved: [AppSettings] = []
    init(_ value: AppSettings = AppSettings()) { self.value = value }
    func load() async -> AppSettings { lock.withLock { value } }
    func save(_ settings: AppSettings) async -> Outcome<Void> { lock.withLock { saved.append(settings); value = settings }; return .success(()) }
    func watch() -> AsyncStream<AppSettings> { let v = lock.withLock { value }; return AsyncStream { $0.yield(v); $0.finish() } }
}

/// Ported from: test/unit/{zentao_doc_sync_lifetime,zentao_doc_reader_brightness}_test.dart (the session state of Docs).
@MainActor
final class ZentaoDocsStateTests: XCTestCase {
    private let account = Account(id: "a1", workspaceId: "w1", providerType: .zentao, handle: "thanh", baseUrl: "https://zt.example")

    private func eventually(_ what: String = "", timeout: Double = 2, _ cond: @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(cond(), what)
    }

    func testTheOpenDocumentIsKeptPerAccountAndScopesTheLocation() {
        var scopes: [String] = []
        let state = ZentaoDocsState(repo: FakeDocRepo(), openScope: { lib, acct in scopes.append("\(acct):\(lib)") })
        state.open(accountId: "a1", libId: "247", docId: "115")
        state.open(accountId: "a2", libId: "89", docId: "50")
        state.open(accountId: "a1", libId: "89", docId: "59")
        XCTAssertEqual(state.openDoc(for: "a1"), ZentaoOpenDoc(libId: "89", docId: "59"))
        XCTAssertEqual(state.openDoc(for: "a2"), ZentaoOpenDoc(libId: "89", docId: "50"))
        XCTAssertNil(state.openDoc(for: "a3"))
        XCTAssertEqual(scopes, ["a1:247", "a2:89", "a1:89"])
    }

    func testTheTreeFilterIsKeptPerAccount() {
        let state = ZentaoDocsState(repo: FakeDocRepo())
        state.setFilter("wal", accountId: "a1")
        XCTAssertEqual(state.filter(for: "a1"), "wal")
        XCTAssertEqual(state.filter(for: "a2"), "")
    }

    func testLibrariesExpandAndFoldPerAccount() {
        let state = ZentaoDocsState(repo: FakeDocRepo())
        state.toggleExpanded(accountId: "a1", libId: "7")
        XCTAssertTrue(state.isExpanded(accountId: "a1", libId: "7"))
        XCTAssertFalse(state.isExpanded(accountId: "a2", libId: "7"))
        state.expand(accountId: "a1", libId: "7")
        state.toggleExpanded(accountId: "a1", libId: "7")
        XCTAssertFalse(state.isExpanded(accountId: "a1", libId: "7"))
    }

    func testThePaneFoldsAwayPerAccountAndSection() {
        let state = ZentaoDocsState(repo: FakeDocRepo())
        state.setPane(collapsed: true, accountId: "a1", section: ZentaoSection.docs)
        XCTAssertTrue(state.isPaneCollapsed(accountId: "a1", section: ZentaoSection.docs))
        XCTAssertFalse(state.isPaneCollapsed(accountId: "a1", section: ZentaoSection.tasks))
        state.setPane(collapsed: false, accountId: "a1", section: ZentaoSection.docs)
        XCTAssertFalse(state.isPaneCollapsed(accountId: "a1", section: ZentaoSection.docs))
    }

    // MARK: reader brightness

    func testSwitchingADarkAppReadsOnLightAndSwitchingBackFollowsTheApp() {
        XCTAssertEqual(ZentaoDocsState.nextReaderBrightness(currentDark: true, appDark: true), "light")
        XCTAssertNil(ZentaoDocsState.nextReaderBrightness(currentDark: false, appDark: true))
        XCTAssertEqual(ZentaoDocsState.nextReaderBrightness(currentDark: false, appDark: false), "dark")
    }

    func testTheBrightnessChoiceIsSavedToTheSettingsAndReadBackOnStart() async {
        let settings = FakeSettingsRepo()
        let state = ZentaoDocsState(repo: FakeDocRepo(), settings: settings)
        XCTAssertNil(state.readerForcedDark)
        state.toggleReaderBrightness(currentDark: true, appDark: true)
        XCTAssertEqual(state.readerForcedDark, false)
        await eventually("saved") { settings.saved.last?.docsReaderBrightness == "light" }

        // A restart seeds the state with what was saved.
        let restarted = ZentaoDocsState(repo: FakeDocRepo(), settings: settings)
        restarted.start()
        await eventually("read back") { restarted.readerForcedDark == false }
    }

    // MARK: cache reads

    func testTheCachedLibrariesAndPinsAreFollowedOnceWatched() async {
        let repo = FakeDocRepo()
        repo.libs = [ZenTaoDocLib(id: "1", name: "API")]
        repo.pins = ZenTaoDocPins(libs: [ZenTaoDocLib(id: "1", name: "API")])
        let state = ZentaoDocsState(repo: repo)
        XCTAssertNil(state.libs["a1"])
        state.watchAccount("a1"); state.watchAccount("a1")
        await eventually { state.libs["a1"]?.map(\.name) == ["API"] && state.pins["a1"]?.hasLib("1") == true }
    }

    func testALibrarysDocumentsAreFollowed() async {
        let repo = FakeDocRepo()
        repo.docs["9"] = [ZenTaoDocSummary(id: "5", title: "Spec", libId: "9")]
        let state = ZentaoDocsState(repo: repo)
        state.watchLib(accountId: "a1", libId: "9")
        await eventually { state.docLists[ZentaoDocsState.libKey("a1", "9")]?.first?.title == "Spec" }
    }

    func testADocumentIsAnsweredEvenWhenTheCacheHasNothing() async {
        let repo = FakeDocRepo()
        let state = ZentaoDocsState(repo: repo)
        await state.observeDoc(accountId: "a1", docId: "5")
        XCTAssertTrue(state.isDocAnswered(accountId: "a1", docId: "5"))
        XCTAssertNil(state.doc(accountId: "a1", docId: "5"))
        repo.doc = ZenTaoDoc(id: "5", title: "T", libId: "9", html: "<p>x</p>")
        await state.observeDoc(accountId: "a1", docId: "5")
        XCTAssertEqual(state.doc(accountId: "a1", docId: "5")?.title, "T")
    }

    func testAHistoryIsFollowedWhileItsPanelIsOpen() async {
        let repo = FakeDocRepo()
        repo.history = [ZenTaoDocAction(id: "1", action: "edited", summary: "s", actor: "x")]
        let state = ZentaoDocsState(repo: repo)
        await state.observeHistory(accountId: "a1", docId: "5")
        XCTAssertEqual(state.history(accountId: "a1", docId: "5").count, 1)
    }

    // MARK: fetching

    func testLeavingDocsBrieflyDoesNotFetchAgainButALongAbsenceDoes() async {
        let repo = FakeDocRepo()
        var clock = Date(timeIntervalSince1970: 1_000)
        let state = ZentaoDocsState(repo: repo, now: { clock })
        let fetch = ZentaoDocFetch.libs(accountId: "a1")

        await state.ensure(fetch, account: account)
        XCTAssertEqual(repo.calls, ["libs"]); XCTAssertEqual(state.sync(fetch), .done)

        clock += 60
        await state.ensure(fetch, account: account)
        XCTAssertEqual(repo.calls, ["libs"], "still fresh")

        clock += ZentaoDocsState.idleLife + 1
        await state.ensure(fetch, account: account)
        XCTAssertEqual(repo.calls, ["libs", "libs"])
    }

    func testRetryFetchesAgainAndAFailureIsKeptBesideTheCachedRows() async {
        let repo = FakeDocRepo()
        repo.refreshResult = .failure(.network("down"))
        let state = ZentaoDocsState(repo: repo)
        let fetch = ZentaoDocFetch.docs(accountId: "a1", libId: "9")
        await state.ensure(fetch, account: account)
        XCTAssertEqual(state.sync(fetch), .failed(.network("down")))
        XCTAssertTrue(state.sync(fetch).hasFailed)

        repo.refreshResult = .success(())
        await state.ensure(fetch, account: account)   // a failed fetch is not fresh
        XCTAssertEqual(state.sync(fetch), .done)
        await state.ensure(fetch, account: account, force: true)
        XCTAssertEqual(repo.calls, ["docs:9", "docs:9", "docs:9"])
    }

    func testEachKindOfFetchAsksItsOwnRefresh() async {
        let repo = FakeDocRepo()
        let state = ZentaoDocsState(repo: repo)
        await state.ensure(.doc(accountId: "a1", docId: "5"), account: account)
        await state.ensure(.history(accountId: "a1", docId: "5"), account: account)
        XCTAssertEqual(repo.calls, ["doc:5", "history:5"])
    }

    func testPinningALibraryOrADocumentTogglesItInTheSavedPins() async {
        let repo = FakeDocRepo()
        let lib = ZenTaoDocLib(id: "1", name: "API")
        let doc = ZenTaoDocSummary(id: "5", title: "Spec", libId: "1")
        let state = ZentaoDocsState(repo: repo)
        _ = await state.togglePin(accountId: "a1", lib: lib)
        XCTAssertEqual(repo.savedPins.last?.libs, [lib])
        repo.pins = ZenTaoDocPins(libs: [lib])
        _ = await state.togglePin(accountId: "a1", doc: doc)
        XCTAssertEqual(repo.savedPins.last?.docs, [doc]); XCTAssertEqual(repo.savedPins.last?.libs, [lib])
    }

    func testExportSavesTheDocumentThroughTheUseCase() async {
        let state = ZentaoDocsState(repo: FakeDocRepo())
        let doc = ZenTaoDoc(id: "5", title: "Spec", libId: "1", html: "<p>x</p>")
        let saved = await state.export(account: account, doc: doc, format: .backup)
        XCTAssertEqual(saved.value, "/tmp/Spec.json")
        XCTAssertTrue(state.markdown(doc).contains("Spec"))
    }
}

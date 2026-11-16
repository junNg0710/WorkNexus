import CoreDomain
import CorePersistence
import GRDB
import XCTest
@testable import ToolZenTao

/// Ported from: test/data/zentao_{notification,dashboard,doc}_repository_test.dart, source_list_cache_test.dart,
/// local_ticket_draft_repository_test.dart - over an in-memory GRDB database with `ZenTaoMigrations`.
final class ZenTaoLocalTests: XCTestCase {
    private func makeDB() throws -> AppDatabase { try AppDatabase.inMemory(registrars: [ZenTaoMigrations.registrar]) }

    private func first<T>(_ stream: AsyncStream<T>) async -> T? {
        for await v in stream { return v }
        return nil
    }

    private let account = Account(id: "a1", workspaceId: "w1", providerType: .zentao, handle: "thanh",
                                  baseUrl: "https://zt.example/zentao", credentialsRef: "ref")

    // MARK: Migration

    func testTheMigrationCreatesTheModuleTablesOnce() throws {
        let db = try makeDB()
        let tables = try db.writer.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }
        for t in ["zenTaoProfiles", "dashboardSnapshots", "sourceListSnapshots", "zenTaoDocSnapshots", "zenTaoNotifications", "ticketDrafts"] {
            XCTAssertTrue(tables.contains(t), t)
        }
        let applied = try db.writer.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
        XCTAssertTrue(applied.contains(ZenTaoMigrations.migrationId))
        XCTAssertEqual(ZenTaoMigrations.migrationId, "zentao_v1")
        // Core tables stay untouched by this module.
        XCTAssertTrue(tables.contains("tickets"))
    }

    // MARK: Notifications

    private func message(_ id: String, read: Bool = false) -> JSON {
        ["id": id, "status": read ? "read" : "sended", "createdDate": "2026-10-09 11:0\(id):00", "data": "Message \(id)"]
    }

    private final class Server: @unchecked Sendable {
        var lists: [String: [JSON]]
        var actions: [String] = []
        var actionResult: Outcome<Void> = .success(())
        init(_ lists: [String: [JSON]]) { self.lists = lists }
    }

    private func makeNotifications(_ db: AppDatabase, _ server: Server) -> GRDBZenTaoNotificationRepository {
        GRDBZenTaoNotificationRepository(
            db: db,
            fetch: { accountId in .success(ZenTaoRawReply(["allMessages": ["day": server.lists[accountId] ?? []] as JSON])) },
            run: { accountId, action in server.actions.append("\(accountId) \(action)"); return server.actionResult })
    }

    func testRefreshStoresAnAccountAndReplacesOnlyItsRows() async throws {
        let db = try makeDB()
        let server = Server(["a1": [message("1"), message("2", read: true)], "a2": [message("3")]])
        let repo = makeNotifications(db, server)
        _ = await repo.refresh(accountId: "a1")
        _ = await repo.refresh(accountId: "a2")
        server.lists["a1"] = [message("4")]
        _ = await repo.refresh(accountId: "a1")
        let ids = await first(repo.watchAll())?.map { "\($0.accountId):\($0.id)" }
        XCTAssertEqual(Set(ids ?? []), ["a1:4", "a2:3"])
    }

    func testAnUnchangedServerListLeavesTheStoreAlone() async throws {
        let db = try makeDB()
        let server = Server(["a1": [message("1"), message("2", read: true)]])
        let repo = makeNotifications(db, server)
        _ = await repo.refresh(accountId: "a1")
        let before = try await db.writer.read { try Row.fetchAll($0, sql: "SELECT rowid FROM zenTaoNotifications ORDER BY rowid").map { $0["rowid"] as Int64 } }
        _ = await repo.refresh(accountId: "a1")
        let after = try await db.writer.read { try Row.fetchAll($0, sql: "SELECT rowid FROM zenTaoNotifications ORDER BY rowid").map { $0["rowid"] as Int64 } }
        XCTAssertEqual(before, after, "nothing changed, so nothing was rewritten")
        server.lists["a1"] = [message("1"), message("2")]
        _ = await repo.refresh(accountId: "a1")
        let stored = await first(repo.watchAll()) ?? []
        XCTAssertTrue(stored.filter(\.read).isEmpty)
    }

    func testMarkReadUpdatesTheStoreAndRunsTheZenTaoAction() async throws {
        let db = try makeDB()
        let server = Server(["a1": [message("1"), message("2", read: true)]])
        let repo = makeNotifications(db, server)
        _ = await repo.refresh(accountId: "a1")
        let res = await repo.markRead(accountId: "a1", id: "1")
        XCTAssertNotNil(res.value)
        XCTAssertEqual(server.actions, ["a1 ajaxMarkRead-1"])
        let stored = await first(repo.watchAll()) ?? []
        XCTAssertTrue(stored.allSatisfy(\.read))
    }

    func testMarkReadWithoutAnIdMarksTheWholeAccount() async throws {
        let db = try makeDB()
        let server = Server(["a1": [message("1")], "a2": [message("3")]])
        let repo = makeNotifications(db, server)
        _ = await repo.refresh(accountId: "a1")
        _ = await repo.refresh(accountId: "a2")
        _ = await repo.markRead(accountId: "a1", id: nil)
        XCTAssertEqual(server.actions, ["a1 ajaxMarkRead-all"])
        let all = await first(repo.watchAll()) ?? []
        XCTAssertEqual(all.filter { !$0.read }.map(\.id), ["3"])
        _ = await repo.markUnread(accountId: "a1", id: "1")
        XCTAssertEqual(server.actions.last, "a1 ajaxMarkUnread-1")
    }

    func testDeleteReadRemovesOnlyReadNotifications() async throws {
        let db = try makeDB()
        let server = Server(["a1": [message("1"), message("2", read: true)]])
        let repo = makeNotifications(db, server)
        _ = await repo.refresh(accountId: "a1")
        _ = await repo.deleteRead(accountId: "a1")
        XCTAssertEqual(server.actions, ["a1 ajaxDelete-allread"])
        let remaining = await first(repo.watchAll()) ?? []
        XCTAssertEqual(remaining.map(\.id), ["1"])
    }

    func testARefusedActionIsReportedAndTheServerListRestored() async throws {
        let db = try makeDB()
        let server = Server(["a1": [message("1"), message("2", read: true)]])
        let repo = makeNotifications(db, server)
        _ = await repo.refresh(accountId: "a1")
        server.actionResult = .failure(.network("offline"))
        let res = await repo.delete(accountId: "a1", id: "1")
        XCTAssertEqual(res.failure, .network("offline"))
        let restored = await first(repo.watchAll()) ?? []
        XCTAssertEqual(Set(restored.map(\.id)), ["1", "2"])
    }

    func testNotificationsComeNewestFirst() async throws {
        let db = try makeDB()
        let server = Server(["a1": [message("1"), message("2"), message("3")]])
        let repo = makeNotifications(db, server)
        _ = await repo.refresh(accountId: "a1")
        let all = await first(repo.watchAll()) ?? []
        XCTAssertEqual(all.map(\.id), ["3", "2", "1"])
    }

    // MARK: Dashboard

    private final class UserInfo: @unchecked Sendable {
        var reply: Outcome<ZenTaoRawReply> = .success(ZenTaoRawReply([
            "profile": ["account": "thanh", "realname": "Thanh"] as JSON,
            "bug": ["total": 2, "bugs": [["id": 1, "title": "One"] as JSON]] as JSON,
        ]))
        var calls: [String] = []
    }

    private func makeDashboard(_ db: AppDatabase, _ info: UserInfo, now: Date) -> GRDBZenTaoDashboardRepository {
        GRDBZenTaoDashboardRepository(db: db, fetch: { id, fields, limit in info.calls.append("\(id)|\(fields)|\(limit)"); return info.reply },
                                      syncAssigned: { _ in .success(0) }, now: { now })
    }

    func testNothingIsStoredBeforeTheFirstDashboardRefresh() async throws {
        let repo = makeDashboard(try makeDB(), UserInfo(), now: Date())
        let cached = await repo.cached(accountId: "a1")
        XCTAssertNil(cached)
    }

    func testDashboardRefreshAsksForTheFieldsAndStoresTheReply() async throws {
        let info = UserInfo()
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = makeDashboard(try makeDB(), info, now: fetched)
        let res = await repo.refresh(accountId: "a1")
        XCTAssertNotNil(res.value)
        XCTAssertEqual(info.calls, ["a1|\(kZenTaoDashboardFields)|\(kZenTaoDashboardListLimit)"])
        let stored = await repo.cached(accountId: "a1")
        XCTAssertEqual(stored?.profile.realname, "Thanh")
        XCTAssertEqual(stored?.bugTotal, 2)
        XCTAssertEqual(stored?.bugs.first?.title, "One")
        XCTAssertEqual(stored?.fetchedAt.timeIntervalSince1970 ?? 0, fetched.timeIntervalSince1970, accuracy: 0.01)
    }

    func testWatchEmitsTheStoredDashboardAfterARefresh() async throws {
        let repo = makeDashboard(try makeDB(), UserInfo(), now: Date())
        _ = await repo.refresh(accountId: "a1")
        let d = await first(repo.watch(accountId: "a1"))
        XCTAssertEqual(d??.profile.account, "thanh")
    }

    func testAFailedDashboardFetchIsReturnedAndKeepsTheStoredSnapshot() async throws {
        let info = UserInfo()
        let repo = makeDashboard(try makeDB(), info, now: Date())
        _ = await repo.refresh(accountId: "a1")
        info.reply = .failure(.network("offline"))
        let res = await repo.refresh(accountId: "a1")
        XCTAssertEqual(res.failure, .network("offline"))
        let kept = await repo.cached(accountId: "a1")
        XCTAssertEqual(kept?.bugTotal, 2)
    }

    // MARK: Documents

    private func docRepository(_ db: AppDatabase, _ server: StubServer?, downloads: URL? = nil) -> GRDBZenTaoDocRepository {
        let client = server.map { makeClient($0, base: "https://zt.example/zentao") }
        return GRDBZenTaoDocRepository(db: db, remote: { _ in client }, downloads: { downloads })
    }

    private func docServer(_ docs: @escaping (StubRequest) -> StubResponse) -> StubServer {
        StubServer { req in req.path.hasSuffix("/tokens") ? .json(["token": "t"]) : docs(req) }
    }

    func testRefreshLibsStoresTheLibrariesTheStreamThenEmits() async throws {
        let db = try makeDB()
        let repo = docRepository(db, docServer { _ in .json(["libs": [["id": 247, "name": "Notification"] as JSON]]) })
        let res = await repo.refreshLibs(account: account)
        XCTAssertNotNil(res.value)
        let libs = await first(repo.watchLibs(accountId: "a1"))
        XCTAssertEqual(libs?.first?.name, "Notification")
        let other = await first(repo.watchLibs(accountId: "other"))
        XCTAssertEqual(other, [])
    }

    func testRefreshDocsKeepsEachLibraryApart() async throws {
        let db = try makeDB()
        let repo = docRepository(db, docServer { req in
            req.query("lib") == "247" ? .json(["docs": [["id": 115, "title": "Payloads"] as JSON]]) : .json(["docs": [Any]()])
        })
        _ = await repo.refreshDocs(account: account, libId: "247")
        _ = await repo.refreshDocs(account: account, libId: "248")
        let a = await first(repo.watchDocs(accountId: "a1", libId: "247"))
        XCTAssertEqual(a?.first?.id, "115")
        let b = await first(repo.watchDocs(accountId: "a1", libId: "248"))
        XCTAssertEqual(b, [])
    }

    func testAnUnreadableDocumentKeepsTheCachedCopy() async throws {
        let db = try makeDB()
        var readable = true
        let repo = docRepository(db, docServer { _ in
            readable ? .json(["id": 111, "title": "Doc 111", "lib": 247, "type": "text", "content": "<p>Hi</p>"]) : .json(["error": "denied"])
        })
        _ = await repo.refreshDoc(account: account, docId: "111")
        readable = false
        let res = await repo.refreshDoc(account: account, docId: "111")
        XCTAssertEqual(res.failure, .notFound("ZenTao document is not readable"))
        let doc = await first(repo.watchDoc(accountId: "a1", docId: "111"))
        XCTAssertEqual(doc??.html, "<p>Hi</p>")
    }

    func testA403FromTheServerIsANotFoundFailure() async throws {
        let db = try makeDB()
        let repo = docRepository(db, docServer { _ in .json(["error": "no"], status: 403) })
        let res = await repo.refreshDoc(account: account, docId: "9")
        guard case .notFound? = res.failure else { return XCTFail("expected notFound, got \(String(describing: res.failure))") }
        let doc = await first(repo.watchDoc(accountId: "a1", docId: "9"))
        XCTAssertEqual(doc, .some(nil))
    }

    func testNoCredentialsIsAnAuthFailure() async throws {
        let repo = docRepository(try makeDB(), nil)
        let res = await repo.refreshLibs(account: account)
        guard case .auth? = res.failure else { return XCTFail("expected auth") }
    }

    func testSaveFileWritesToDownloadsWithoutOverwriting() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zentao_docs_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = docRepository(try makeDB(), docServer { _ in .bytes(Data([1, 2, 3]), contentType: "application/octet-stream") }, downloads: dir)
        let file = TicketAttachment(id: "1", title: "notes.md", url: "https://zt.example/zentao/file-download-1.md")
        let first = try await repo.saveFile(account: account, file: file).get()
        let second = try await repo.saveFile(account: account, file: file).get()
        XCTAssertTrue(first.hasSuffix("notes.md"))
        XCTAssertTrue(second.hasSuffix("notes (2).md"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: second)), Data([1, 2, 3]))
        let unsafe = try await repo.saveText(fileName: "a/b:c.json", text: "{}").get()
        XCTAssertTrue(unsafe.hasSuffix("a_b_c.json"))
    }

    func testPinsAreStoredPerAccountAndReadBack() async throws {
        let repo = docRepository(try makeDB(), nil)
        let pins = ZenTaoDocPins(libs: [ZenTaoDocLib(id: "1", name: "A <B>")], docs: [ZenTaoDocSummary(id: "9", title: "Post & More", libId: "1")])
        let saved = await repo.savePins(accountId: "a1", pins: pins)
        XCTAssertNotNil(saved.value)
        let a1 = await first(repo.watchPins(accountId: "a1"))
        XCTAssertEqual(a1, pins)
        let a2 = await first(repo.watchPins(accountId: "a2"))
        XCTAssertEqual(a2, ZenTaoDocPins())
    }

    func testRefreshHistoryStoresTheDocumentHistory() async throws {
        let repo = docRepository(try makeDB(), docServer { _ in
            .json(wrapped([["id": 1, "action": "edited", "content": "2026-10-29 11:25:30, edited by <strong>Vi</strong> ."] as JSON]))
        })
        let res = await repo.refreshHistory(account: account, docId: "111")
        XCTAssertNotNil(res.value)
        let history = await first(repo.watchHistory(accountId: "a1", docId: "111"))
        XCTAssertEqual(history?.first?.actor, "Vi")
        let other = await first(repo.watchHistory(accountId: "a1", docId: "222"))
        XCTAssertEqual(other, [])
    }

    func testBackupIsTheCachedRecordAsIndentedJson() async throws {
        let repo = docRepository(try makeDB(), docServer { _ in .json(["id": 111, "title": "T", "lib": 1, "content": "<p>x</p>"]) })
        _ = await repo.refreshDoc(account: account, docId: "111")
        let backup = try await repo.readBackup(accountId: "a1", docId: "111").get()
        XCTAssertTrue(backup.hasPrefix("{\n  \""))
        XCTAssertTrue(backup.contains("\"title\": \"T\""))
        let missing = await repo.readBackup(accountId: "a1", docId: "nope")
        XCTAssertNotNil(missing.failure)
    }

    // MARK: Source lists

    func testSourceListsRoundTripWithTheirGrouping() async throws {
        let cache = GRDBZenTaoSourceListCache(db: try makeDB())
        let none = await cache.readProducts(accountId: "a1")
        XCTAssertNil(none)
        await cache.saveProducts(accountId: "a1", items: [
            ProviderProduct(id: "8", name: "Wallet", accountId: "a1", programId: "1", programName: "VN", lineId: "3", lineName: "Mobile"),
            ProviderProduct(id: "9", name: "Daily", accountId: "a1"),
        ])
        let products = await cache.readProducts(accountId: "a1")
        XCTAssertEqual(products?.map(\.programName), ["VN", nil])
        XCTAssertEqual(products?.map(\.lineName), ["Mobile", nil])
        await cache.saveProjects(accountId: "a1", items: [ProviderProject(id: "7", name: "Wallet", accountId: "a1", programId: "3", programName: "VN Program")])
        let projects = await cache.readProjects(accountId: "a1")
        XCTAssertEqual(projects?.first?.programName, "VN Program")
    }

    func testProgramNamesAFetchCouldNotGetComeFromTheLastCachedList() async throws {
        let cache = GRDBZenTaoSourceListCache(db: try makeDB())
        await cache.saveProjects(accountId: "a1", items: [ProviderProject(id: "7", name: "Wallet", accountId: "a1", programId: "3", programName: "VN Program")])
        let fetched = [ProviderProject(id: "7", name: "Wallet", accountId: "a1", programId: "3"), ProviderProject(id: "8", name: "Daily", accountId: "a1")]
        let named = await cache.withKnownProgramNames(accountId: "a1", projects: fetched)
        XCTAssertEqual(named.map(\.programName), ["VN Program", nil])
    }

    // MARK: Drafts

    func testDraftsAreKeptReadBackAndDeletedWithoutTheirFileBytes() async throws {
        let repo = GRDBZenTaoTicketDraftRepository(db: try makeDB())
        var bug = BugDraft(product: "4")
        bug.title = "Crash"; bug.os = ["ios"]; bug.severity = 2
        bug.files = [TicketAttachment(id: "10", title: "a.png", url: "https://z/a.png", extension: "png", size: 7)]
        bug.newFiles = [DraftFile(name: "big.mov", bytes: Data(repeating: 1, count: 100))]
        var task = TaskDraft(execution: "31")
        task.name = "Build"; task.estimate = 2.5
        let older = ZenTaoSavedDraft(id: "d1", accountId: "a1", uid: "u1", updatedAt: Date(timeIntervalSince1970: 1_000), content: .bug(bug))
        let newer = ZenTaoSavedDraft(id: "d2", accountId: "a1", uid: "u2", updatedAt: Date(timeIntervalSince1970: 2_000), content: .task(task))
        _ = await repo.save(older)
        _ = await repo.save(newer)

        let all = await first(repo.watchAll()) ?? []
        XCTAssertEqual(all.map(\.id), ["d2", "d1"])           // most recently changed first
        let read = try await repo.read(id: "d1").get()
        guard case .bug(let got)? = read?.content else { return XCTFail("expected a bug draft") }
        XCTAssertEqual(got.title, "Crash")
        XCTAssertEqual(got.os, ["ios"])
        XCTAssertEqual(got.severity, 2)
        XCTAssertEqual(got.files.map(\.id), ["10"])
        XCTAssertTrue(got.newFiles.isEmpty)                    // only bytes: left out
        XCTAssertEqual(read?.uid, "u1")
        XCTAssertEqual(read?.title, "Crash")
        guard case .task(let t)? = try await repo.read(id: "d2").get()?.content else { return XCTFail() }
        XCTAssertEqual(t.estimate, 2.5)
        XCTAssertEqual(t.execution, "31")

        _ = await repo.delete(id: "d1")
        let gone = try await repo.read(id: "d1").get()
        XCTAssertNil(gone)
    }

    func testAnUnreadableDraftRowIsSkipped() async throws {
        let db = try makeDB()
        try await db.writer.write { try TicketDraftRow(id: "x", accountId: "a", kind: "weird", uid: "u", json: "{}", updatedAt: Date()).save($0) }
        let repo = GRDBZenTaoTicketDraftRepository(db: db)
        let all = await first(repo.watchAll())
        XCTAssertEqual(all, [])
    }

    // MARK: Profile

    func testProfileRefreshStoresTheProfileWithItsDepartmentPathAndUpdateSendsOnlyChanges() async throws {
        let db = try makeDB()
        let server = StubServer { req in
            if req.path.hasSuffix("/tokens") { return .json(["token": "t"]) }
            if req.method == "PUT" { return .json(["id": 12]) }
            if req.path.hasSuffix("/api.php/v1/user") {
                return .json(["profile": ["id": 12, "account": "thanh", "realname": "Thanh", "dept": 2, "email": "t@x.io", "avatar": "/zentao/a.png",
                                          "role": ["code": "dev", "name": "Developer"] as JSON] as JSON])
            }
            if req.path.hasSuffix("/api.php/v1/departments") {
                return .json(["departments": [["id": 1, "name": "VN", "parent": 0] as JSON, ["id": 2, "name": "Flutter VN", "parent": 1] as JSON]])
            }
            return .json([:])
        }
        let credentials = InMemoryCredentialStore()
        _ = await credentials.write("ref", value: "pw")
        let repo = GRDBZenTaoProfileRepository(db: db, credentials: credentials, clientFactory: { _, _ in makeClient(server, base: "https://zt.example/zentao") })
        let profile = try await repo.refresh(account: account).get()
        XCTAssertEqual(profile.department, "VN > Flutter VN")
        XCTAssertEqual(profile.avatarUrl, "https://zt.example/zentao/a.png")
        let watched = await first(repo.watch(accountId: "a1"))
        XCTAssertEqual(watched??.realname, "Thanh")
        let departments = await first(repo.watchDepartments(accountId: "a1"))
        XCTAssertEqual(departments?.map(\.name), ["VN", "Flutter VN"])

        let updated = try await repo.update(account: account, changes: ZenTaoProfileUpdate(realname: "Thanh N", email: "t@x.io", mobile: "", phone: "")).get()
        XCTAssertEqual(updated.account, "thanh")
        let put = try XCTUnwrap(server.requests.first { $0.method == "PUT" })
        XCTAssertTrue(put.path.hasSuffix("/api.php/v1/users/12"))
        let body = try XCTUnwrap(asMap(put.jsonBody))
        XCTAssertEqual(body["realname"] as? String, "Thanh N")
        XCTAssertNil(body["email"])                           // unchanged fields are not sent
    }

    func testProfileRefreshWithoutCredentialsFails() async throws {
        let repo = GRDBZenTaoProfileRepository(db: try makeDB(), credentials: InMemoryCredentialStore())
        let noRef = await repo.refresh(account: Account(id: "a", workspaceId: "w", providerType: .zentao, handle: "t", baseUrl: "https://z"))
        XCTAssertEqual(noRef.failure, .auth("No ZenTao connection credentials"))
        let noPassword = await repo.refresh(account: account)
        XCTAssertEqual(noPassword.failure, .auth("ZenTao password is missing"))
    }

    // MARK: Services over the stores

    private struct FixedAdapters: ZenTaoAdapterProvider, ZenTaoAccountLookup {
        var adapter: ProviderAdapter?
        var accounts: [Account]
        func adapter(accountId: String) async -> ProviderAdapter? { adapter }
        func account(id: String) async -> Account? { accounts.first { $0.id == id } }
        func zentaoAccounts() async -> [Account] { accounts }
    }

    private final class MemoryTickets: TicketRepository, @unchecked Sendable {
        var stored: [Ticket] = []
        func watchTickets() -> AsyncStream<[Ticket]> { AsyncStream { $0.finish() } }
        func ticket(id: String) async -> Outcome<Ticket?> { .success(stored.first { $0.id == id }) }
        func upsertTickets(_ tickets: [Ticket]) async -> Outcome<Void> { stored += tickets; return .success(()) }
        func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { .success(()) }
    }

    func testViewPagesAreStoredAsTheyArrive() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                req.path.contains("bug-browse-") ? .json(wrapped(["bugs": [["id": 5, "title": "A", "status": "active"] as JSON], "pager": ["recTotal": 1] as JSON])) : .json([:])
            }
        }
        let fixed = FixedAdapters(adapter: makeAdapter(server), accounts: [account])
        let tickets = MemoryTickets()
        let service = ZenTaoTicketServiceImpl(accounts: fixed, adapters: fixed, tickets: tickets)
        let page = try await service.syncProductBugsPage(accountId: "a1", productId: "4", browseType: "all", page: 1, limit: 10, sort: .newest, cancel: nil).get()
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(tickets.stored.map(\.externalKey), ["5"])
        let missing = await service.syncProductBugsPage(accountId: "nope", productId: "4", browseType: "all", page: 1, limit: 10, sort: .newest, cancel: nil)
        XCTAssertEqual(missing.failure, .auth("ZenTao account not found"))
    }

    func testAZenTaoTicketLinkIsFetchedAndStoredByHost() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                req.path.hasSuffix("/api.php/v1/bugs/6492") ? .json(["id": 6492, "title": "Linked", "status": "active", "pri": 2]) : .json([:])
            }
        }
        let fixed = FixedAdapters(adapter: makeAdapter(server), accounts: [account])
        let tickets = MemoryTickets()
        let service = ZenTaoTicketServiceImpl(accounts: fixed, adapters: fixed, tickets: tickets)
        let id = try await service.fetchZenTaoTicket(host: "zt.example", type: "bug", id: "6492").get()
        XCTAssertEqual(id, "zt:bug:6492")
        XCTAssertEqual(tickets.stored.first?.title, "Linked")
        let unknown = await service.fetchZenTaoTicket(host: "other.example", type: "bug", id: "1")
        XCTAssertEqual(unknown.failure, .notFound("No ZenTao account for this link"))
    }

    func testTaskBugsAreReadOnceWhileTheirCoverageIsFresh() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                req.path.contains("execution-bug-")
                    ? .json(wrapped(["bugs": [["id": 1, "title": "B", "status": "active", "task": 7] as JSON], "pager": ["recTotal": 1] as JSON])) : .json([:])
            }
        }
        let fixed = FixedAdapters(adapter: makeAdapter(server), accounts: [account])
        let tickets = MemoryTickets()
        let service = ZenTaoTicketServiceImpl(accounts: fixed, adapters: fixed, tickets: tickets)
        _ = await service.syncTaskBugs(accountId: "a1", executionId: "31", taskId: "7")
        _ = await service.syncTaskBugs(accountId: "a1", executionId: "31", taskId: "7")
        XCTAssertEqual(server.requests.filter { $0.path.contains("execution-bug-") }.count, 1)
        XCTAssertEqual(tickets.stored.count, 1)
        let notANumber = await service.syncTaskBugs(accountId: "a1", executionId: "31", taskId: "x")
        XCTAssertNotNil(notANumber.value)
    }

    func testTheAdapterFactoryBuildsOnlyForZenTaoAccountsWithAServer() {
        XCTAssertNotNil(ZentaoAdapterFactory.makeAdapter(account: account, secret: "pw"))
        XCTAssertNil(ZentaoAdapterFactory.makeAdapter(account: Account(id: "g", workspaceId: "w", providerType: .gitlab, handle: "h", baseUrl: "https://g"), secret: "x"))
        XCTAssertNil(ZentaoAdapterFactory.makeAdapter(account: Account(id: "z", workspaceId: "w", providerType: .zentao, handle: "h"), secret: "x"))
        XCTAssertEqual(ZentaoAdapterFactory.makeAdapter(account: account, secret: "pw")?.providerType, .zentao)
    }
}

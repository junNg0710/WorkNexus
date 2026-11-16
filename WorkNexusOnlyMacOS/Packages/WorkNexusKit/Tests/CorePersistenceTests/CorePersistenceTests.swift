import CoreDomain
import GRDB
import XCTest
@testable import CorePersistence

final class CorePersistenceTests: XCTestCase {
    func testTicketRoundTripAndHashSkip() async throws {
        let db = try AppDatabase.inMemory()
        let repo = GRDBTicketRepository(db: db)
        let bug = ZenTaoBugEntity(product: "1", severity: 2, attachments: [TicketAttachment(id: "a", title: "x.png", url: "u")])
        var t = Ticket(id: "t1", accountId: "a1", projectId: "p", providerType: .zentao, externalKey: "BUG-1", title: "T",
                       body: "B", priority: .high, status: .todo, providerStatus: "active", sourceHash: "h1",
                       labels: ["x"], providerEntity: .zentaoBug(bug))
        let first = await repo.upsertTickets([t])
        XCTAssertNotNil(first.value)
        t.title = "changed"
        _ = await repo.upsertTickets([t])                    // same hash → skipped
        let fetched = await repo.ticket(id: "t1")
        let got = try XCTUnwrap(fetched.value ?? nil)
        XCTAssertEqual(got.title, "T")
        XCTAssertEqual(got.providerEntity, .zentaoBug(bug))
        XCTAssertEqual(got.priority, .high)
    }

    func testSettingsDefaultsAndRoundTrip() async throws {
        let repo = GRDBSettingsRepository(db: try AppDatabase.inMemory())
        var s = await repo.load()
        XCTAssertEqual(s.sidebarWidth, 290)
        s.variant = .midnight; s.viewModes = ["zentao.bugs": "list"]
        _ = await repo.save(s)
        let again = await repo.load()
        XCTAssertEqual(again.variant, .midnight)
        XCTAssertEqual(again.viewModes["zentao.bugs"], "list")
        // old/partial JSON still decodes
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).chatAppearance, .worknexus)
    }

    func testWorkspaceAccountsWatch() async throws {
        let repo = GRDBWorkspaceRepository(db: try AppDatabase.inMemory())
        _ = await repo.createWorkspace(Workspace(id: "w", name: "W", shortCode: "W", colorValue: 1))
        _ = await repo.upsertAccount(Account(id: "gl", workspaceId: "w", providerType: .gitlab, handle: "h"))
        _ = await repo.upsertAccount(Account(id: "zt", workspaceId: "w", providerType: .zentao, handle: "h"))
        var it = repo.watchAccounts().makeAsyncIterator()
        let accounts = await it.next()
        XCTAssertEqual(accounts?.map(\.id), ["zt", "gl"])
    }
}

final class PersistenceSyncTests: XCTestCase {
    func testLastSyncedAtSurvivesARestart() async throws {
        let db = try AppDatabase.inMemory()
        let first = GRDBSyncStatusRepository(db: db)
        let initial = await first.status(accountId: "a")
        XCTAssertEqual(initial, .idle(lastSyncedAt: nil))
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        first.report(accountId: "a", status: .syncing)
        first.report(accountId: "a", status: .idle(lastSyncedAt: at))
        for _ in 0..<100 {
            let stored = try await db.writer.read { try Date.fetchOne($0, sql: "SELECT lastSyncedAt FROM accountSyncState WHERE accountId = 'a'") }
            if stored != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        // A new repository (a new launch) starts from the stored time; other statuses are not persisted.
        let second = GRDBSyncStatusRepository(db: db)
        var it = second.watch(accountId: "a").makeAsyncIterator()
        let seen = await it.next()
        guard case .idle(let when?)? = seen else { return XCTFail("expected idle with a date, got \(String(describing: seen))") }
        XCTAssertEqual(when.timeIntervalSince1970, at.timeIntervalSince1970, accuracy: 0.01)
        first.report(accountId: "a", status: .offline)
        let current = await first.status(accountId: "a")
        XCTAssertEqual(current, .offline)
    }

    func testSavedFilterStoreRoundTrip() async throws {
        let store = GRDBSavedFilterStore(db: try AppDatabase.inMemory())
        let a = SavedFilterRecord(id: "1", name: "Mine", filterJson: "{}", createdAt: Date(timeIntervalSince1970: 100))
        let b = SavedFilterRecord(id: "2", name: "Urgent", filterJson: "{\"search\":\"x\"}", createdAt: Date(timeIntervalSince1970: 200))
        _ = await store.upsert(a); _ = await store.upsert(b)
        var it = store.watch().makeAsyncIterator()
        let list = await it.next()
        XCTAssertEqual(list?.map(\.id), ["2", "1"], "newest first")
        var renamed = a; renamed.name = "Mine!"
        _ = await store.upsert(renamed)
        _ = await store.delete(id: "2")
        var again = store.watch().makeAsyncIterator()
        let after = await again.next()
        XCTAssertEqual(after?.map(\.name), ["Mine!"])
    }

    func testDetailStoreReplacesTogetherAndKeepsInternalNotes() async throws {
        let db = try AppDatabase.inMemory()
        let comments = GRDBCommentRepository(db: db), activity = GRDBActivityRepository(db: db)
        let store = GRDBDetailStore(db: db)
        let now = Date()
        _ = await comments.upsertComments([
            Comment(id: "old", ticketId: "t", authorName: "x", body: "gone on server", createdAt: now, origin: .provider),
            Comment(id: "note", ticketId: "t", authorName: "me", body: "mine", createdAt: now, origin: .internalNote),
        ])
        _ = await activity.upsertActivity([ActivityEvent(id: "ev-old", ticketId: "t", actor: "x", action: "old", at: now)])
        let result = await store.replaceDetail(
            ticketId: "t",
            comments: [Comment(id: "new", ticketId: "t", authorName: "y", body: "fresh", createdAt: now, origin: .provider)],
            events: [ActivityEvent(id: "ev-new", ticketId: "t", actor: "y", action: "new", at: now)])
        XCTAssertNotNil(result.value)
        var c = comments.watchComments(ticketId: "t").makeAsyncIterator()
        let cs = await c.next()
        XCTAssertEqual(Set(cs?.map(\.id) ?? []), ["new", "note"])
        var a = activity.watchActivity(ticketId: "t").makeAsyncIterator()
        let evs = await a.next()
        XCTAssertEqual(evs?.map(\.id), ["ev-new"])
        // nil leaves a list alone
        _ = await store.replaceDetail(ticketId: "t", comments: nil, events: [])
        var c2 = comments.watchComments(ticketId: "t").makeAsyncIterator()
        let stillThere = await c2.next()
        XCTAssertEqual(stillThere?.count, 2)
    }

    func testSourceListSnapshotsWithoutTheOwnerTableAreAMiss() async throws {
        let db = try AppDatabase.inMemory()
        let snaps = GRDBSourceListSnapshots(db: db)
        let miss = await snaps.read(accountId: "a", kind: "products")
        XCTAssertNil(miss)
        await snaps.write(accountId: "a", kind: "products", json: "[]")      // no table: silently nothing
        try await db.writer.write { d in
            try d.execute(sql: "CREATE TABLE sourceListSnapshots (accountId TEXT NOT NULL, kind TEXT NOT NULL, json TEXT NOT NULL, fetchedAt DATETIME NOT NULL, PRIMARY KEY (accountId, kind))")
        }
        await snaps.write(accountId: "a", kind: "products", json: "[1]")
        await snaps.write(accountId: "a", kind: "products", json: "[2]")
        let got = await snaps.read(accountId: "a", kind: "products")
        XCTAssertEqual(got, "[2]")
    }
}

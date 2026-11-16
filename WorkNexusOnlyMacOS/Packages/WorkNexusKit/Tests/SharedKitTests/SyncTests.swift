import CoreDomain
import XCTest
@testable import SharedKit

/// Tests for lib/shared/sync (SyncCoordinator, TicketStore, ProviderAdapterPool, SourceListCache, caches) — new tests (no
/// Dart counterpart besides account_sync_status_test.dart / account_sync_at_launch_test.dart's behaviour).
final class SyncTests: XCTestCase {
    private let account = Account(id: "zt1", workspaceId: "w", providerType: .zentao, handle: "me", baseUrl: "https://zt", credentialsRef: "secret:zt1")

    private func ticket(_ id: String, title: String = "T", labels: [String] = []) -> Ticket {
        makeTicket(id, account: "zt1", project: "zt1:p7", provider: .zentao, key: id, title: title, labels: labels, type: "Bug")
    }

    private struct Rig {
        let store = FakeStore(), adapter = FakeAdapter(), registry = FakeRegistry(), status = RecordingStatus()
        let coordinator: SyncCoordinator
        init(account: Account) {
            registry.adapter = adapter
            store.accounts[account.id] = account
            store.secrets["secret:zt1"] = "pw"
            coordinator = SyncCoordinator(tickets: store, workspaces: store, comments: store, activity: store, credentials: store, registry: registry,
                                          statusRepository: status, attachmentCache: AttachmentFileCache(root: FileManager.default.temporaryDirectory.appendingPathComponent("wn-\(UUID())")))
        }
    }

    final class RecordingStatus: SyncStatusRepository, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var reports: [AccountSyncStatus] = []
        func watch(accountId: String) -> AsyncStream<AccountSyncStatus> { AsyncStream { $0.finish() } }
        func status(accountId: String) async -> AccountSyncStatus { reports.last ?? .idle(lastSyncedAt: nil) }
        func report(accountId: String, status: AccountSyncStatus) { lock.withLock { reports.append(status) } }
    }

    func testSyncWritesTicketsAccountAndProjectsOnce() async {
        let r = Rig(account: account)
        r.adapter.assigned = [ticket("1"), ticket("2")]
        let res = await r.coordinator.sync(accountId: "zt1")
        XCTAssertNotNil(res.value)
        XCTAssertEqual(r.store.tickets.count, 2)
        XCTAssertEqual(r.store.projects["zt1:p7"]?.name, "p7")
        XCTAssertEqual(r.store.ticketWrites, 2)
    }

    func testUnchangedSyncLeavesTablesUntouched() async {
        let r = Rig(account: account)
        r.adapter.assigned = [ticket("1"), ticket("2")]
        _ = await r.coordinator.sync(accountId: "zt1")
        let (t, a, p) = (r.store.ticketWrites, r.store.accountWrites, r.store.projectWrites)
        _ = await r.coordinator.sync(accountId: "zt1")
        XCTAssertEqual(r.store.ticketWrites, t, "no ticket row should be rewritten")
        XCTAssertEqual(r.store.accountWrites, a); XCTAssertEqual(r.store.projectWrites, p)
        r.adapter.assigned = [ticket("1"), ticket("2", title: "Changed")]
        _ = await r.coordinator.sync(accountId: "zt1")
        XCTAssertEqual(r.store.ticketWrites, t + 1, "only the changed row is written")
    }

    func testListSyncKeepsSyntheticMembershipLabels() async {
        let r = Rig(account: account)
        r.store.tickets["1"] = ticket("1", labels: ["zentao-product:10", "bug"])
        r.adapter.assigned = [ticket("1", labels: ["bug"])]
        _ = await r.coordinator.sync(accountId: "zt1")
        XCTAssertEqual(r.store.tickets["1"]?.labels, ["bug", "zentao-product:10"])
    }

    func testConcurrentSyncsOfOneAccountShareOneFetch() async {
        let r = Rig(account: account)
        r.adapter.assigned = [ticket("1")]
        r.adapter.delay = .milliseconds(150)
        async let a = r.coordinator.sync(accountId: "zt1")
        async let b = r.coordinator.sync(accountId: "zt1")
        _ = await (a, b)
        XCTAssertEqual(r.adapter.listCalls, 1)
        _ = await r.coordinator.sync(accountId: "zt1")
        XCTAssertEqual(r.adapter.listCalls, 2, "a finished sync no longer shares")
    }

    func testStatusReportedAroundSync() async {
        let r = Rig(account: account)
        _ = await r.coordinator.sync(accountId: "zt1")
        XCTAssertEqual(r.status.reports.first, .syncing)
        if case .idle(let at)? = r.status.reports.last { XCTAssertNotNil(at) } else { XCTFail("expected idle") }
        r.adapter.failure = .auth("expired")
        _ = await r.coordinator.sync(accountId: "zt1")
        XCTAssertEqual(r.status.reports.last, .authExpired)
        r.adapter.failure = .network("down")
        _ = await r.coordinator.sync(accountId: "zt1")
        XCTAssertEqual(r.status.reports.last, .offline)
        r.adapter.failure = .parse("bad")
        _ = await r.coordinator.sync(accountId: "zt1")
        XCTAssertEqual(r.status.reports.last, .error("bad"))
    }

    func testMissingAccountOrSecret() async {
        let r = Rig(account: account)
        let v1 = await r.coordinator.sync(accountId: "nope").failure
        XCTAssertEqual(v1, .notFound("No such account"))
        r.store.secrets = [:]
        let v2 = await r.coordinator.sync(accountId: "zt1").failure
        XCTAssertEqual(v2, .auth("Stored credentials not found in keychain"))
    }

    func testAdapterIsPooledUntilTheSecretChanges() async {
        let r = Rig(account: account)
        _ = await r.coordinator.adapterFor("zt1"); _ = await r.coordinator.adapterFor("zt1")
        XCTAssertEqual(r.registry.created, 1)
        r.store.secrets["secret:zt1"] = "new-password"
        _ = await r.coordinator.adapterFor("zt1")
        XCTAssertEqual(r.registry.created, 2)
    }

    func testDetailRefreshWritesChangedRowAndReplacesCommentsOnlyWhenTheyDiffer() async {
        let r = Rig(account: account)
        let base = ticket("1")
        r.store.tickets["1"] = base
        var detail = base; detail.body = "full body"; r.adapter.detail = detail
        let c = Comment(id: "c1", ticketId: "1", authorName: "A", body: "hi", createdAt: Date(timeIntervalSince1970: 100.0004))
        r.adapter.comments = [c]
        r.adapter.activity = [ActivityEvent(id: "e1", ticketId: "1", actor: "A", action: "created", at: Date(timeIntervalSince1970: 50))]
        _ = await r.coordinator.refresh(ticket: base)
        XCTAssertEqual(r.store.tickets["1"]?.body, "full body")
        XCTAssertEqual(r.store.commentWrites, 1); XCTAssertEqual(r.store.activityWrites, 1)
        _ = await r.coordinator.refresh(ticket: r.store.tickets["1"]!)
        XCTAssertEqual(r.store.commentWrites, 1, "same set (compared at stored precision): no write")
        XCTAssertEqual(r.store.activityWrites, 1)
    }

    func testPostCommentRefreshesTheTicket() async {
        let r = Rig(account: account)
        r.store.tickets["1"] = ticket("1")
        r.adapter.comments = [Comment(id: "c9", ticketId: "1", authorName: "me", body: "x", createdAt: Date())]
        let v3 = await r.coordinator.postComment(ticket: ticket("1"), body: "x").value
        XCTAssertNotNil(v3)
        XCTAssertNotNil(r.store.comments["c9"])
    }

    func testTicketImagesAreCachedAndMissesRest() async {
        let r = Rig(account: account)
        let t = ticket("1")
        r.adapter.imageBytes = Data([1, 2, 3])
        let v4 = await r.coordinator.fetchTicketImage(t, url: "/a.png")
        XCTAssertEqual(v4, Data([1, 2, 3]))
        _ = await r.coordinator.fetchTicketImage(t, url: "/a.png")
        XCTAssertEqual(r.adapter.imageCalls, 1)
        r.adapter.imageBytes = nil
        let v5 = await r.coordinator.fetchTicketImage(t, url: "/dead.png")
        XCTAssertNil(v5)
        let v6 = await r.coordinator.fetchTicketImage(t, url: "/dead.png")
        XCTAssertNil(v6)
        XCTAssertEqual(r.adapter.imageCalls, 2, "a refused image rests instead of asking again at once")
    }

    func testOptimisticActionRollsBackOnFailureAndRefreshesOnSuccess() async {
        let r = Rig(account: account)
        let original = ticket("1")
        r.store.tickets["1"] = original
        var guess = original; guess.status = .done; guess.sourceHash = "guess"
        let failed = await r.coordinator.runOptimisticAction(original, optimistic: guess) { .failure(.network("x")) }
        XCTAssertEqual(failed.failure, .network("x"))
        XCTAssertEqual(r.store.tickets["1"]?.status, original.status)
    }

    // MARK: Helpers
    func testMergeDetailLabelsAndLabelColors() {
        XCTAssertEqual(mergeDetailLabels(["a"], ["gitlab-project:1", "a", "zentao-product:2", "old"]), ["a", "gitlab-project:1", "zentao-product:2"])
        let existing = TicketProviderEntity.gitlabItem(GitLabItemEntity(labelColors: ["bug": "#f00"], labelTextColors: ["bug": "#fff"]))
        let fresh = TicketProviderEntity.gitlabItem(GitLabItemEntity())
        XCTAssertEqual(preserveLabelColors(fresh, existing), existing)
        XCTAssertEqual(preserveLabelColors(existing, fresh), existing)
    }

    func testSourceListCacheRoundTripsAndKeepsKnownProgramNames() async {
        let cache = SourceListCache()
        let none = await cache.readProducts("a")
        XCTAssertNil(none)
        await cache.saveProducts("a", [ProviderProduct(id: "1", name: "P", accountId: "a", programId: "9", programName: "Prog", lineId: "3", lineName: "L")])
        let products = await cache.readProducts("a")
        XCTAssertEqual(products, [ProviderProduct(id: "1", name: "P", accountId: "a", programId: "9", programName: "Prog", lineId: "3", lineName: "L")])
        await cache.saveProjects("a", [ProviderProject(id: "7", name: "Proj", accountId: "a", programId: "9", programName: "Prog")])
        let fetched = [ProviderProject(id: "7", name: "Proj", accountId: "a", programId: "9", programName: nil)]
        let named = await cache.withKnownProgramNames("a", fetched)
        XCTAssertEqual(named.first?.programName, "Prog")
    }

    func testByteLruCacheEvictsOldest() {
        let c = ByteLruCache(maxBytes: 10)
        c.put("a", Data(count: 4)); c.put("b", Data(count: 4))
        _ = c.get("a")                       // a is now the most recent
        c.put("c", Data(count: 4))           // 12 > 10: evict the oldest (b)
        XCTAssertNotNil(c.get("a")); XCTAssertNil(c.get("b")); XCTAssertNotNil(c.get("c"))
        c.put("huge", Data(count: 11)); XCTAssertNil(c.get("huge"))
    }

    func testAttachmentFileCacheStoresReusesAndEvictsOldest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wn-att-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AttachmentFileCache(root: root, maxBytes: 10)
        XCTAssertNil(cache.existing("1", "a.png"))
        let p1 = try cache.store("1", "a.png", Data(count: 6))
        XCTAssertEqual(cache.existing("1", "a.png"), p1)
        Thread.sleep(forTimeInterval: 0.02)
        let p2 = try cache.store("2", "b.png", Data(count: 6))     // 12 > 10: the oldest goes
        XCTAssertNil(cache.existing("1", "a.png")); XCTAssertEqual(cache.existing("2", "b.png"), p2)
        XCTAssertEqual(cache.sizeBytes(), 6)
        cache.purge(); XCTAssertEqual(cache.sizeBytes(), 0)
    }

    func testSafeNameReplacesPathCharacters() { XCTAssertEqual(SyncCoordinator.safeName(#"a/b\c:d*e?f"g<h>i|j.png"#), "a_b_c_d_e_f_g_h_i_j.png") }
}

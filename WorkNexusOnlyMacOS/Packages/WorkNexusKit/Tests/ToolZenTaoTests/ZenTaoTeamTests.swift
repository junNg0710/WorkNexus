import CoreDomain
import CorePersistence
import XCTest
@testable import ToolZenTao

/// A leader's team groups and the reading of a person's work across executions and products.
final class ZenTaoTeamTests: XCTestCase {
    private let account = Account(id: "zt", workspaceId: "w", providerType: .zentao, handle: "lead", baseUrl: "https://zentao.example.com")

    private struct Fixed: ZenTaoAdapterProvider, ZenTaoAccountLookup {
        var adapter: ProviderAdapter?
        var accounts: [Account]
        func adapter(accountId: String) async -> ProviderAdapter? { adapter }
        func account(id: String) async -> Account? { accounts.first { $0.id == id } }
        func zentaoAccounts() async -> [Account] { accounts }
    }

    private final class Memory: TicketRepository, @unchecked Sendable {
        var stored: [Ticket] = []
        func watchTickets() -> AsyncStream<[Ticket]> { AsyncStream { $0.finish() } }
        func ticket(id: String) async -> Outcome<Ticket?> { .success(stored.first { $0.id == id }) }
        func upsertTickets(_ tickets: [Ticket]) async -> Outcome<Void> { stored += tickets; return .success(()) }
        func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { .success(()) }
    }

    private var users: JSON {
        ["users": [["id": 7, "account": "thanh", "realname": "Thanh Pham"] as JSON, ["id": 9, "account": "cat", "realname": "Cat Le"] as JSON]]
    }

    private func task(_ id: Int, execution: Int) -> JSON { ["id": id, "name": "Task \(id)", "status": "doing", "execution": execution, "assignedTo": "thanh"] }

    // MARK: Reading a person's work

    func testTasksOfAPersonAreReadPageByPageFromEveryExecution() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                if req.path.hasSuffix("/api.php/v1/users") { return .json(self.users) }
                guard req.path.contains("user-task-7-assignedTo") else { return .json([:]) }
                let page = req.path.contains("-0-2-2.json") ? [self.task(3, execution: 12)] : [self.task(1, execution: 11), self.task(2, execution: 12)]
                return .json(wrapped(["tasks": page, "pager": ["recTotal": 3] as JSON]))
            }
        }
        let tickets = Memory()
        let fixed = Fixed(adapter: makeAdapter(server), accounts: [account])
        // `limit` is fixed at 100 by the service, so ask the adapter for the paging itself.
        let adapter = makeAdapter(server)
        let id = try await adapter.userId(of: "thanh").get()
        XCTAssertEqual(id, "7")
        let first = try await adapter.listAssignedWorkPage(userId: id, bugs: false, page: 1, limit: 2, cancel: nil).get()
        let second = try await adapter.listAssignedWorkPage(userId: id, bugs: false, page: 2, limit: 2, cancel: nil).get()
        XCTAssertEqual(first.tickets.map(\.externalKey), ["1", "2"])
        XCTAssertTrue(first.hasMore)
        XCTAssertEqual(second.tickets.map(\.externalKey), ["3"])
        XCTAssertFalse(second.hasMore)
        XCTAssertEqual(first.tickets[0].labels.filter { $0.hasPrefix("zentao-execution:") }, ["zentao-execution:11"])
        XCTAssertTrue(server.requests.map(\.path).contains { $0.contains("user-task-7-assignedTo-id_desc-0-2-1.json") })
        // The user list is read once.
        XCTAssertEqual(server.requests.filter { $0.path.hasSuffix("/api.php/v1/users") }.count, 1)

        let service = ZenTaoTicketServiceImpl(accounts: fixed, adapters: fixed, tickets: tickets)
        let work = try await service.syncAssignedWork(accountId: "zt", login: "thanh", bugs: false, cap: 500, cancel: nil).get()
        XCTAssertEqual(work.ids.count, 2)                                       // the stub answers the same first page each time but one
        XCTAssertFalse(work.truncated)
        XCTAssertEqual(Set(tickets.stored.map(\.externalKey)), ["1", "2"])
    }

    func testBugsOfAPersonCarryTheirProductLabelAndTheCapCutsALongRead() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                if req.path.hasSuffix("/api.php/v1/users") { return .json(self.users) }
                guard req.path.contains("user-bug-9-assignedTo") else { return .json([:]) }
                // Every page is full of new bugs: the total says there is more.
                let page = Int(req.path.split(separator: "-").last?.replacingOccurrences(of: ".json", with: "") ?? "1") ?? 1
                let bugs = (0..<100).map { ["id": page * 1000 + $0, "title": "B", "status": "active", "product": 4] as JSON }
                return .json(wrapped(["bugs": bugs, "pager": ["recTotal": 900] as JSON]))
            }
        }
        let fixed = Fixed(adapter: makeAdapter(server), accounts: [account])
        let tickets = Memory()
        let service = ZenTaoTicketServiceImpl(accounts: fixed, adapters: fixed, tickets: tickets)
        let work = try await service.syncAssignedWork(accountId: "zt", login: "cat", bugs: true, cap: 250, cancel: nil).get()
        XCTAssertEqual(work.ids.count, 250)
        XCTAssertTrue(work.truncated)
        XCTAssertEqual(work.total, 900)
        XCTAssertTrue(tickets.stored.allSatisfy { $0.labels.contains("zentao-product:4") })
    }

    func testARefusedPersonPageIsAFailureNotAnEmptyList() async throws {
        let server = StubServer { req in
            .tokenOr(req) {
                if req.path.hasSuffix("/api.php/v1/users") { return .json(self.users) }
                return .json(wrapped(["locate": "/user-login.html"]))
            }
        }
        let fixed = Fixed(adapter: makeAdapter(server), accounts: [account])
        let service = ZenTaoTicketServiceImpl(accounts: fixed, adapters: fixed, tickets: Memory())
        let refused = await service.syncAssignedWork(accountId: "zt", login: "thanh", bugs: false, cap: 100, cancel: nil)
        XCTAssertNotNil(refused.failure)
        let unknown = await service.syncAssignedWork(accountId: "zt", login: "nobody", bugs: false, cap: 100, cancel: nil)
        XCTAssertNotNil(unknown.failure)
    }

    // MARK: Groups

    func testAGroupNeedsANameAndPeopleAndHasEachOnce() {
        let build = BuildTeamGroup()
        let an = ZenTaoTeamMember(login: "an", name: "An"), binh = ZenTaoTeamMember(login: "binh", name: "Binh")
        XCTAssertEqual(build(accountId: "a", name: "  ", members: [an]).failureValue, .noName)
        XCTAssertEqual(build(accountId: "a", name: "Mobile", members: []).failureValue, .noMembers)
        XCTAssertEqual(build(accountId: "a", name: "Mobile", members: [ZenTaoTeamMember(login: "", name: "?")]).failureValue, .noMembers)
        let ok = try? build(accountId: "a", name: " Mobile ", members: [an, binh, an]).get()
        XCTAssertEqual(ok?.name, "Mobile")
        XCTAssertEqual(ok?.members.map(\.login), ["an", "binh"])
    }

    func testGroupsAreStoredPerAccountAndWatched() async throws {
        let db = try AppDatabase.inMemory(registrars: [ZenTaoMigrations.registrar])
        let repo = GRDBZenTaoTeamGroupRepository(db: db)
        let a = ZenTaoTeamGroup(id: "g1", accountId: "zt", name: "Mobile", members: [ZenTaoTeamMember(login: "an", name: "An")],
                                createdAt: Date(timeIntervalSince1970: 100))
        let b = ZenTaoTeamGroup(id: "g2", accountId: "zt", name: "Backend", members: [ZenTaoTeamMember(login: "binh", name: "Binh")],
                                createdAt: Date(timeIntervalSince1970: 200))
        let other = ZenTaoTeamGroup(id: "g3", accountId: "elsewhere", name: "Other", members: [ZenTaoTeamMember(login: "x", name: "X")])
        for g in [b, a, other] { _ = await repo.save(g) }
        var it = repo.watchGroups(accountId: "zt").makeAsyncIterator()
        let all = await it.next()
        XCTAssertEqual(all?.map(\.name), ["Mobile", "Backend"])             // oldest first, this account only
        XCTAssertEqual(all?.first?.members, [ZenTaoTeamMember(login: "an", name: "An")])
        var edited = a; edited.name = "Mobile team"
        _ = await repo.save(edited)
        _ = await repo.delete(id: "g2")
        var again = repo.watchGroups(accountId: "zt").makeAsyncIterator()
        let after = await again.next()
        XCTAssertEqual(after?.map(\.name), ["Mobile team"])
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let f) = self { f } else { nil } }
}

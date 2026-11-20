import CoreDomain
import XCTest
@testable import FeatureChat

/// The profile popup's groups in common and open work.
final class PersonProfileUseCaseTests: XCTestCase {
    private final class Groups: StubChatRepository, @unchecked Sendable {
        var chats: [ChatConversation] = []
        var memberships: [String: Outcome<[Int]>] = [:]
        override func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]> {
            let chats = chats
            return AsyncStream { $0.yield(chats); $0.finish() }
        }
        override func members(accountId: String, chatGid: String) async -> Outcome<[Int]> { memberships[chatGid] ?? .success([]) }
    }

    private func group(_ gid: String, active: TimeInterval, archived: Bool = false, type: ChatType = .group) -> ChatConversation {
        var c = ChatConversation(accountId: "a", gid: gid, type: type, name: gid)
        c.lastActiveAt = Date(timeIntervalSince1970: active); c.archived = archived
        return c
    }

    func testSharedGroupsAreThoseWithThePersonNewestFirst() async throws {
        let repo = Groups()
        repo.chats = [group("old", active: 1), group("new", active: 9), group("other", active: 5),
                      group("gone", active: 10, archived: true), group("dm", active: 11, type: .one2one)]
        repo.memberships = ["old": .success([7, 1]), "new": .success([7]), "other": .success([1]), "gone": .success([7]), "dm": .success([7])]
        let shared = try await FindSharedGroups(repo, parallel: 2)(accountId: "a", userId: 7).get()
        XCTAssertEqual(shared.map(\.gid), ["new", "old"])
    }

    func testAGroupThatDoesNotAnswerIsSkippedUnlessNoneDo() async throws {
        let repo = Groups()
        repo.chats = [group("a", active: 1), group("b", active: 2)]
        repo.memberships = ["a": .failure(.network("down")), "b": .success([7])]
        let some = try await FindSharedGroups(repo)(accountId: "a", userId: 7).get()
        XCTAssertEqual(some.map(\.gid), ["b"])
        repo.memberships = ["a": .failure(.network("down")), "b": .failure(.network("down"))]
        let none = await FindSharedGroups(repo)(accountId: "a", userId: 7)
        XCTAssertEqual(none.failure?.message, "down")
    }

    private func ticket(_ key: String, account: String = "a", assignee: String?, opener: String? = nil, status: UnifiedStatus = .todo,
                        updated: TimeInterval = 0) -> Ticket {
        Ticket(id: key, accountId: account, projectId: "p", providerType: .zentao, externalKey: key, title: key, body: "", priority: .medium,
               status: status, providerStatus: "active", sourceHash: key, externalType: "Bug", assignee: assignee,
               updatedAt: Date(timeIntervalSince1970: updated), providerEntity: .zentaoBug(ZenTaoBugEntity(openedByHandle: opener)))
    }

    func testOpenWorkIsAssignedThenReportedCaseAside() {
        let all = [ticket("1", assignee: "Bull", updated: 1), ticket("2", assignee: "bull", updated: 5),
                   ticket("3", assignee: "an", opener: "BULL"), ticket("4", assignee: "bull", status: .done),
                   ticket("5", account: "other", assignee: "bull"), ticket("6", assignee: "an")]
        let work = ListPersonTickets()(all, accountId: "a", handle: "bull")
        XCTAssertEqual(work.assigned.map(\.id), ["2", "1"])
        XCTAssertEqual(work.reported.map(\.id), ["3"])
        XCTAssertEqual(work.count, 3)
        XCTAssertEqual(ListPersonTickets()(all, accountId: "a", handle: " ").count, 0)
    }
}

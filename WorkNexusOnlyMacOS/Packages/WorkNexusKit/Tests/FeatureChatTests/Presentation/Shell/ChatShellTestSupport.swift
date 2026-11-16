import CoreDomain
import Foundation
import XCTest
@testable import FeatureChat

/// A repository whose streams the test drives and whose calls it records.
final class ShellFakeRepository: StubChatRepository, @unchecked Sendable {
    var statusCont: AsyncStream<ChatConnectionStatus>.Continuation?
    var conversationsCont: AsyncStream<[ChatConversation]>.Continuation?
    var usersCont: AsyncStream<[ChatUser]>.Continuation?
    var typingCont: AsyncStream<ChatTypingSignal>.Continuation?
    var searchResults: [ChatMessage] = []
    var searchCalls: [(query: String, limit: Int?)] = []
    var markReadCalls: [String] = []
    var refreshCalls: [String] = []
    var starredCalls: [(String, Bool)] = []
    var openDirectResult: Outcome<String> = .success("direct-1")
    var trustResult: Outcome<Void> = .success(())
    var trusted: [String] = []
    var extent: Outcome<ChatTimelineExtent> = .success(ChatTimelineExtent(count: 5, oldestServerId: 1, reachesStart: true))

    override func watchStatus(accountId: String) -> AsyncStream<ChatConnectionStatus> { AsyncStream { statusCont = $0 } }
    override func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]> { AsyncStream { conversationsCont = $0 } }
    override func watchUsers(accountId: String) -> AsyncStream<[ChatUser]> { AsyncStream { usersCont = $0 } }
    override func watchTyping(accountId: String) -> AsyncStream<ChatTypingSignal> { AsyncStream { typingCont = $0 } }
    override func searchMessages(accountId: String, chatGid: String?, query: String, since: Date?, limit: Int?) async -> Outcome<[ChatMessage]> {
        searchCalls.append((query, limit))
        return .success(Array(searchResults.prefix(limit ?? .max)))
    }
    override func refreshMessages(accountId: String, chatGid: String) async -> Outcome<Void> { refreshCalls.append(chatGid); return .success(()) }
    override func markRead(accountId: String, chatGid: String) async -> Outcome<Void> { markReadCalls.append(chatGid); return .success(()) }
    override func memberCount(accountId: String, chatGid: String) async -> Outcome<Int> { .success(7) }
    override func setChatStarred(accountId: String, chatGid: String, starred: Bool) async -> Outcome<Void> { starredCalls.append((chatGid, starred)); return .success(()) }
    override func openDirectChat(accountId: String, userId: Int) async -> Outcome<String> { openDirectResult }
    override func trustCertificate(accountId: String, fingerprint: String) async -> Outcome<Void> { trusted.append(fingerprint); return trustResult }
    override func timelineExtent(accountId: String, chatGid: String) async -> Outcome<ChatTimelineExtent> { extent }
}

enum ShellMake {
    static func user(_ id: Int, _ name: String, account: String? = nil, role: String? = nil, status: String? = nil) -> ChatUser {
        ChatUser(accountId: "a", userId: id, account: account ?? name.lowercased(), realname: name, role: role, status: status)
    }

    static func chat(_ gid: String, type: ChatType = .group, name: String = "", peer: Int? = nil, at: TimeInterval? = nil, starred: Bool = false,
                     unread: Int = 0, hidden: Bool = false, archived: Bool = false) -> ChatConversation {
        ChatConversation(accountId: "a", gid: gid, type: type, name: name, unreadCount: unread,
                         lastActiveAt: at.map { Date(timeIntervalSince1970: $0) }, peerUserId: peer, hidden: hidden,
                         archived: archived, starred: starred)
    }

    @MainActor static func expectEventually(file: StaticString = #filePath, line: UInt = #line, _ condition: @MainActor () -> Bool) async {
        let ok = await eventually(condition)
        XCTAssertTrue(ok, "condition not met in time", file: file, line: line)
    }

    /// Waits (up to two seconds) for `condition` — the models read their streams from tasks.
    @MainActor static func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

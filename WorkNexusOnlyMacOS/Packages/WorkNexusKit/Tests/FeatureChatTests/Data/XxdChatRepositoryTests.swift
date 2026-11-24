import CoreDomain
import XCTest
@testable import FeatureChat

/// Port of test/data/chat/xxd_chat_repository_test.dart (connection, ingest, sending, history, read state).
final class XxdChatRepositoryTests: RepositoryTestCase {
    func testConnectStoresChatListPeersAndOwnUserId() async throws {
        let r1 = await repo.connect(accountId: acc)
        XCTAssertNotNil(r1.value)
        let chats = try await eventually(repo.watchConversations(accountId: acc)) { $0.count == 2 && $0.contains { $0.gid == "31&40" && $0.peerUserId == 31 } }
        let users = try await eventually(repo.watchUsers(accountId: acc)) { $0.contains { $0.userId == 31 } }
        let group = byGid(chats, "g1")!
        XCTAssertEqual(group.type, .group); XCTAssertEqual(group.unreadCount, 1)
        XCTAssertEqual(group.lastMessage?.content, .text("hello", markdown: false)); XCTAssertFalse(group.lastMessage?.isMine ?? true)
        XCTAssertEqual(chats.first?.gid, "g1", "most recently active first")
        XCTAssertEqual(users.first { $0.userId == 31 }?.realname, "User 31")
        var status: ChatConnectionStatus?
        for await s in repo.watchStatus(accountId: acc) { status = s; break }
        XCTAssertEqual(status, .online(selfUserId: 40))
        XCTAssertEqual(opened.current.first?.server, URL(string: "https://zt.test:11443"))
        XCTAssertEqual(opened.current.first?.account, "demo"); XCTAssertEqual(opened.current.first?.password, "pw")
    }

    func testPushedMessageIsStoredAndBumpsUnread() async throws {
        try await connectAndWait()
        server.current.push(["method": "messagesend", "result": "success", "data": [serverMessage(101, content: "new", type: "text")]])
        let chats = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.unreadCount == 2 }
        XCTAssertEqual(byGid(chats, "g1")?.lastMessage?.content, .text("new", markdown: true))
        var messages: [ChatMessage] = []
        for await m in repo.watchMessages(accountId: acc, chatGid: "g1") { messages = m; break }
        XCTAssertEqual(messages.last?.gid, "m101")
    }

    func testSearchIsNarrowedByKindSenderAndChat() async throws {
        try await connectAndWait()
        let file = #"{"name":"Báo cáo quý.zip","size":3,"id":7,"time":1,"type":"application/zip"}"#
        let image = #"{"name":"bao-cao.png","size":3,"id":8,"time":1,"type":"image/png","width":10,"height":10}"#
        let link = #"{"type":"url","url":"https://zt.test/bao-cao-view-4158.html"}"#
        let code = #"{"lang":"swift","code":"let baoCao = 1","name":"Snippet"}"#
        server.current.push(["method": "messagesend", "result": "success", "data": [
            serverMessage(201, user: 31, content: file, type: "file"), serverMessage(202, user: 32, content: image, type: "image"),
            serverMessage(203, user: 31, content: link, type: "object"), serverMessage(204, user: 32, content: code, type: "code"),
            serverMessage(205, user: 32, content: "báo cáo ở https://zt.test/x nhé"), serverMessage(206, cgid: "g2", user: 31, content: "báo cáo khác")]])
        _ = try await eventually(repo.watchMessages(accountId: acc, chatGid: "g1")) { $0.last?.gid == "m205" }
        func ids(_ search: ChatMessageSearch) async -> [Int] {
            ((await repo.searchMessages(accountId: acc, matching: search)).value ?? []).compactMap(\.serverId).sorted()
        }
        // Everything but pictures, which have only a file name to go by.
        let all = await ids(ChatMessageSearch(query: "bao cao"))
        XCTAssertEqual(all, [201, 203, 204, 205, 206])
        let files = await ids(ChatMessageSearch(query: "bao cao", kind: .files)); XCTAssertEqual(files, [201])
        let images = await ids(ChatMessageSearch(query: "bao", kind: .images)); XCTAssertEqual(images, [202])
        let links = await ids(ChatMessageSearch(query: "", kind: .links)); XCTAssertEqual(links, [203, 205], "a shared link, and text with an address")
        let written = await ids(ChatMessageSearch(query: "baocao", kind: .messages)); XCTAssertEqual(written, [204], "code is searched as what was written")
        let fromOne = await ids(ChatMessageSearch(query: "bao cao", senderIds: [32])); XCTAssertEqual(fromOne, [204, 205], "not the picture")
        let inChat = await ids(ChatMessageSearch(query: "bao cao", chatGids: ["g2"])); XCTAssertEqual(inChat, [206])
        // Nothing typed lists what the rest lets through; with nothing at all there is nothing to look for.
        let sent = await ids(ChatMessageSearch(senderIds: [31], kind: .files)); XCTAssertEqual(sent, [201])
        let nothing = await ids(ChatMessageSearch()); XCTAssertEqual(nothing, [])
    }

    func testLiveMessageFromSomeoneElseIsAnnouncedOnce() async throws {
        try await connectAndWait()
        let stream = repo.watchIncoming()
        let collector = Task { () -> [String] in var seen: [String] = []; for await m in stream { seen.append(m.gid); if seen.count == 2 { break } }; return seen }
        let push: JSONValue = ["method": "messagesend", "result": "success", "data": [serverMessage(102, user: 77)]]
        server.current.push(push.object!)
        _ = try await eventually(repo.watchMessages(accountId: acc, chatGid: "g1")) { $0.contains { $0.gid == "m102" } }
        server.current.push(push.object!)    // re-delivery
        server.current.push(["method": "messagesend", "result": "success", "data": [serverMessage(103, user: 78)]])
        let seen = await collector.value
        XCTAssertEqual(seen, ["m102", "m103"])
    }

    func testPinAndUnpinPushesReplaceThePinnedList() async throws {
        try await connectAndWait()
        server.current.push(["method": "chatPinMessages", "result": "success", "data": ["cgid": "g1", "pinned": [101], "allPinned": [100, 101]]])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.pinnedMessageIds.count == 2 }
        server.current.push(["method": "chatUnpinMessages", "result": "success", "data": ["cgid": "g1", "unpinned": [100], "allPinned": [101]]])
        let chats = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.pinnedMessageIds.count == 1 }
        XCTAssertEqual(byGid(chats, "g1")?.pinnedMessageIds, [101])
    }

    func testSendTextIsPendingThenSent() async throws {
        try await connectAndWait()
        let seen = Locked<[SendState]>([])
        let stream = repo.watchMessages(accountId: acc, chatGid: "g1")
        let watcher = Task { for await l in stream { if let m = l.last(where: \.isMine) { seen.with { $0.append(m.sendState) } } } }
        let result = await repo.sendText(accountId: acc, chatGid: "g1", text: "xin chào", replyToId: nil, markdown: false)
        let sent = try await eventually(repo.watchMessages(accountId: acc, chatGid: "g1")) { $0.contains { $0.isMine && $0.serverId != nil } }
        watcher.cancel()
        XCTAssertNotNil(result.value)
        let mine = sent.last { $0.isMine }!
        XCTAssertEqual(mine.sendState, .sent); XCTAssertEqual(mine.content, .text("xin chào", markdown: false))
        XCTAssertEqual(seen.current.first, .pending)
        let req = server.requests("messagesend").last!
        let m = req["params"]?[0]?[0]
        XCTAssertEqual(m?["cgid"], "g1"); XCTAssertEqual(m?["contentType"], "plain"); XCTAssertEqual(m?["user"], 40)
    }

    func testSendCodeAndForward() async throws {
        try await connectAndWait()
        _ = await repo.sendCode(accountId: acc, chatGid: "g1", code: "x := 1", language: "go", name: "main.go", replyToId: 100)
        let code = server.requests("messagesend").last!["params"]![0]![0]!
        XCTAssertEqual(code["contentType"], "code")
        XCTAssertEqual(try JSONValue.parse(code["content"]!.string!), ["lang": "go", "code": "x := 1", "name": "main.go"])
        XCTAssertEqual(try JSONValue.parse(code["data"]!.string!), ["replyTo": 100])
        let sent = try await eventually(repo.watchMessages(accountId: acc, chatGid: "g1")) { $0.contains { $0.isMine && $0.serverId != nil } }
        let gid = sent.last { $0.isMine }!.gid
        let fwd = await repo.forwardMessage(accountId: acc, messageGid: gid, toChatGid: "31&40")
        XCTAssertNotNil(fwd.value)
        let req = server.requests("messagesend").last!["params"]![0]![0]!
        XCTAssertEqual(req["cgid"], "31&40"); XCTAssertEqual(req["contentType"], "code")
    }

    func testSendingOfflineFailsAndRetryDelivers() async throws {
        let failed = await repo.sendText(accountId: acc, chatGid: "g1", text: "later", replyToId: nil, markdown: false)
        XCTAssertNotNil(failed.failure)
        try await connectAndWait()
        let row = try await eventually(repo.watchMessages(accountId: acc, chatGid: "g1")) { $0.contains { $0.sendState == .failed } }
        let gid = row.first { $0.sendState == .failed }!.gid
        let r2 = await repo.retrySend(accountId: acc, messageGid: gid)
        XCTAssertNotNil(r2.value)
        let sent = try await eventually(repo.watchMessages(accountId: acc, chatGid: "g1")) { $0.contains { $0.gid == gid && $0.sendState == .sent } }
        XCTAssertNotNil(sent.first { $0.gid == gid }?.serverId)
    }

    func testRefreshThenLoadOlderPageBackwards() async throws {
        try await connectAndWait()
        let r3 = await repo.refreshMessages(accountId: acc, chatGid: "g1")
        XCTAssertNotNil(r3.value)
        let r4 = await repo.loadOlderMessages(accountId: acc, chatGid: "g1", beforeServerId: nil, inWindow: false, pageSize: nil)
        XCTAssertEqual(r4.value, 50)
        let r5 = await repo.loadOlderMessages(accountId: acc, chatGid: "g1", beforeServerId: nil, inWindow: false, pageSize: nil)
        XCTAssertEqual(r5.value, 20)
        let r6 = await repo.loadOlderMessages(accountId: acc, chatGid: "g1", beforeServerId: nil, inWindow: false, pageSize: nil)
        XCTAssertEqual(r6.value, 0)
        var all: [ChatMessage] = []
        for await m in repo.watchMessages(accountId: acc, chatGid: "g1", limit: 500, reactions: true) { all = m; break }
        XCTAssertEqual(all.map(\.serverId), (1...120).map { $0 })
    }

    func testDownloadHistoryStoresAllOfItForSearch() async throws {
        history.with { $0[5] = serverMessage(5, content: "Đã gửi bản phát hành cũ") }
        try await connectAndWait()
        _ = await repo.refreshMessages(accountId: acc, chatGid: "g1")
        // A reply parent far back: older than the timeline, not part of it.
        let r7 = await repo.fetchMessages(accountId: acc, chatGid: "g1", serverIds: [3])
        XCTAssertNotNil(r7.value)
        var extent = (await repo.timelineExtent(accountId: acc, chatGid: "g1")).value!
        XCTAssertEqual(extent.count, 50); XCTAssertEqual(extent.oldestServerId, 71)
        let r8 = await repo.searchMessages(accountId: acc, chatGid: nil, query: "phat hanh", since: nil, limit: nil)
        XCTAssertEqual(r8.value?.count, 0)
        var progress: [ChatHistoryProgress] = []
        for await r in DownloadChatHistory(repo)(accountId: acc, chatGid: "g1") { progress.append(r.value!) }
        XCTAssertEqual(progress.first, ChatHistoryProgress(stored: 50, total: 120))
        XCTAssertEqual(progress.last, ChatHistoryProgress(stored: 120, total: 120, complete: true))
        let sizes = Set(server.requests("messagesync").compactMap { $0["params"]?[3]?.intValue })
        XCTAssertEqual(sizes, [50, 200])
        extent = (await repo.timelineExtent(accountId: acc, chatGid: "g1")).value!
        XCTAssertEqual(extent.count, 120); XCTAssertEqual(extent.oldestServerId, 1); XCTAssertTrue(extent.reachesStart)
        let found = await repo.searchMessages(accountId: acc, chatGid: nil, query: "phat hanh", since: nil, limit: nil)
        XCTAssertEqual(found.value?.map(\.serverId), [5])
        // Every word has to be there, in any order; words in quotes as a phrase.
        let anyOrder = await repo.searchMessages(accountId: acc, chatGid: nil, query: "hanh GUI", since: nil, limit: nil)
        XCTAssertEqual(anyOrder.value?.map(\.serverId), [5])
        let phrase = await repo.searchMessages(accountId: acc, chatGid: nil, query: "\"hanh phat\"", since: nil, limit: nil)
        XCTAssertEqual(phrase.value?.count, 0)
        let missing = await repo.searchMessages(accountId: acc, chatGid: nil, query: "phat hanh moi", since: nil, limit: nil)
        XCTAssertEqual(missing.value?.count, 0)
    }

    func testReplyParentFetchedByIdStaysOutOfTimeline() async throws {
        try await connectAndWait()
        _ = await repo.refreshMessages(accountId: acc, chatGid: "g1")
        let r9 = await repo.fetchMessages(accountId: acc, chatGid: "g1", serverIds: [3])
        XCTAssertNotNil(r9.value)
        var one: ChatMessage?
        for await m in repo.watchMessage(accountId: acc, chatGid: "g1", serverId: 3) { one = m; break }
        XCTAssertEqual(one?.serverId, 3)
        var shown: [ChatMessage] = []
        for await m in repo.watchMessages(accountId: acc, chatGid: "g1", limit: 51, reactions: true) { shown = m; break }
        XCTAssertEqual(shown.map(\.serverId), (71...120).map { $0 })
        let r10 = await repo.countOlderMessages(accountId: acc, chatGid: "g1", before: shown[0].sentAt)
        XCTAssertEqual(r10.value, 0)
    }

    func testJumpWindowThenNewerPagesUntilItJoinsTheTimeline() async throws {
        try await connectAndWait()
        _ = await repo.refreshMessages(accountId: acc, chatGid: "g1")
        let span = (await repo.loadMessagesAround(accountId: acc, chatGid: "g1", serverId: 3)).value!
        XCTAssertEqual(span?.from, 1); XCTAssertEqual(span?.to, 52)
        var window: [ChatMessage] = []
        for await m in repo.watchMessagesInRange(accountId: acc, chatGid: "g1", fromIndex: 1, toIndex: 52, reactions: true) { window = m; break }
        XCTAssertEqual(window.map(\.serverId), (1...52).map { $0 })
        var latest: [ChatMessage] = []
        for await m in repo.watchMessages(accountId: acc, chatGid: "g1", limit: 500, reactions: true) { latest = m; break }
        XCTAssertEqual(latest.first?.serverId, 71, "window is not part of the timeline yet")
        let r11 = await repo.loadNewerMessages(accountId: acc, chatGid: "g1", afterServerId: 52)
        XCTAssertGreaterThan(r11.value ?? 0, 0)
        let r12 = await repo.joinWindowToTimeline(accountId: acc, chatGid: "g1", fromIndex: 1, toIndex: 101)
        XCTAssertEqual(r12.value!, 120)
        var joined: [ChatMessage] = []
        for await m in repo.watchMessages(accountId: acc, chatGid: "g1", limit: 500, reactions: true) { joined = m; break }
        XCTAssertEqual(joined.map(\.serverId), (1...120).map { $0 })
    }

    func testRefreshThatSkipsAheadCutsOffStaleHistory() async throws {
        try await connectAndWait()
        // Pages 1-50 were stored in an earlier session.
        let r13 = await repo.loadOlderMessages(accountId: acc, chatGid: "g1", beforeServerId: 51, inWindow: false, pageSize: nil)
        XCTAssertNotNil(r13.value)
        let r14 = await repo.refreshMessages(accountId: acc, chatGid: "g1")
        XCTAssertNotNil(r14.value)
        let extent = (await repo.timelineExtent(accountId: acc, chatGid: "g1")).value!
        XCTAssertEqual(extent.oldestServerId, 71); XCTAssertEqual(extent.count, 50)
    }

    func testMarkReadClearsUnreadAndTellsTheServer() async throws {
        _ = await repo.connect(accountId: acc)
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.unreadCount == 1 }
        let r15 = await repo.markRead(accountId: acc, chatGid: "g1")
        XCTAssertNotNil(r15.value)
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.unreadCount == 0 }
        XCTAssertEqual(server.requests("chatsetlastreadmessagebyindex").last?["params"], ["g1", 100])
    }

    func testReadMarkerPushedFromAnotherDeviceClearsUnread() async throws {
        _ = await repo.connect(accountId: acc)
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.unreadCount == 1 }
        server.current.push(["method": "chatsetlastreadmessagebyindex", "result": "success", "data": ["gid": "g1", "id": 100]])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "g1")?.unreadCount == 0 }
    }

    func testKickedSignsOutInsteadOfReconnecting() async throws {
        _ = await repo.connect(accountId: acc)
        server.current.push(["method": "userkickoff", "reason": "elsewhere"])
        let status = try await eventually(repo.watchStatus(accountId: acc)) { if case .signedOut = $0 { true } else { false } }
        guard case .signedOut(_, let kicked) = status else { return XCTFail() }
        XCTAssertTrue(kicked)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(server.sockets.count, 1)
    }

    func testWithoutASavedPasswordChatIsSignedOut() async throws {
        _ = await store.delete("secret:acc")
        let r = await repo.connect(accountId: acc)
        guard case .auth? = r.failure else { return XCTFail("\(String(describing: r.failure))") }
        var s: ChatConnectionStatus?
        for await v in repo.watchStatus(accountId: acc) { s = v; break }
        XCTAssertEqual(s, .signedOut(message: "No saved ZenTao password"))
    }

    func testConnectsRacingInShareOneSignIn() async throws {
        async let a = repo.connect(accountId: acc), b = repo.connect(accountId: acc)
        _ = await (a, b)
        XCTAssertEqual(http.calls, 1); XCTAssertEqual(server.requests("userlogin").count, 1)
    }

    func testUntrustedCertificateWaitsForTheUserThenPinsIt() async throws {
        http.fallback = .failure(.untrustedCertificate(message: "no", host: "zt.test", fingerprint: "AB:CD", subject: "s", issuer: "i"))
        let r = await repo.connect(accountId: acc)
        guard case .untrustedCertificate? = r.failure else { return XCTFail() }
        let st = try await eventually(repo.watchStatus(accountId: acc)) { if case .needsTrust = $0 { true } else { false } }
        XCTAssertEqual(st, .needsTrust(host: "zt.test", fingerprint: "AB:CD", subject: "s", issuer: "i"))
        http.fallback = serverInfoOk()
        let r16 = await repo.trustCertificate(accountId: acc, fingerprint: "AB:CD")
        XCTAssertNotNil(r16.value)
        XCTAssertEqual(opened.current.last?.pinnedFingerprint, "AB:CD")
    }

    func testTypingAddressesPeerAndGroupMembers() async throws {
        server.onRequest = { [prev = server.onRequest] req in
            if req["method"] == "chatgetmembers" { return ["method": "chatgetmembers", "rid": req["rid"] ?? .null, "result": "success", "data": [40, 31, 32]] }
            return prev?(req)
        }
        try await connectAndWait()
        _ = await repo.sendTyping(accountId: acc, chatGid: "31&40", typing: true)
        _ = await repo.sendTyping(accountId: acc, chatGid: "g1", typing: true)
        _ = await repo.sendTyping(accountId: acc, chatGid: "g1", typing: false)
        let sent = server.requests("chattyping")
        XCTAssertEqual(sent.map { $0["users"] }, [[31], [31, 32], [31, 32]])
        XCTAssertEqual(server.requests("chatgetmembers").count, 1)
        let signals = repo.watchTyping(accountId: acc)
        let first = Task { () -> ChatTypingSignal? in for await s in signals { return s }; return nil }
        try await Task.sleep(nanoseconds: 30_000_000)
        server.current.push(["method": "chattyping", "result": "success", "data": ["cgid": "g1", "user": 31, "typing": "true"]])
        let sig = await first.value
        XCTAssertEqual(sig, ChatTypingSignal(chatGid: "g1", userId: 31, typing: true))
    }

    func testPresenceStarAndRoleNames() async throws {
        server.onRequest = { [prev = server.onRequest] req in
            if req["method"] == "sysgetdepts" { return ["method": "sysgetdepts", "rid": req["rid"] ?? .null, "result": "success", "data": ["roles": ["dev": "Developer", "qa": " Tester "]]] }
            return prev?(req)
        }
        try await connectAndWait()
        let r17 = await repo.setMyPresence(accountId: acc, presence: .busy)
        XCTAssertNotNil(r17.value)
        XCTAssertEqual(server.requests("userupdate").last?["params"]?[0]?["status"], "busy")
        let r18 = await repo.setChatStarred(accountId: acc, chatGid: "31&40", starred: true)
        XCTAssertNotNil(r18.value)
        let chats = try await eventually(repo.watchConversations(accountId: acc)) { self.byGid($0, "31&40")?.starred == true }
        XCTAssertEqual(chats.first?.gid, "31&40", "pinned chats come first")
        let r19 = await repo.roleNames(accountId: acc)
        XCTAssertEqual(r19.value, ["dev": "Developer", "qa": "Tester"])
        _ = await repo.roleNames(accountId: acc)
        XCTAssertEqual(server.requests("sysgetdepts").count, 1)
    }

    func testMessageInUnknownChatFetchesThatChat() async throws {
        try await connectAndWait()
        server.current.push(["method": "messagesend", "result": "success", "data": [serverMessage(300, cgid: "newgid")]])
        _ = try await eventually(repo.watchConversations(accountId: acc)) { $0.contains { $0.gid == "newgid" } }
        XCTAssertEqual(server.requests("chatgetbygid").last?["params"], ["newgid"])
    }
}

import CoreDomain
import XCTest
@testable import FeatureChat

final class RecordingRepository: StubChatRepository, @unchecked Sendable {
    var sentEmoji: [(code: String, replyTo: Int?)] = []
    var retracted: [String] = []
    var extents: [Outcome<ChatTimelineExtent>] = []
    var olderPages: [Int] = []
    var olderCalls: [(before: Int?, pageSize: Int?)] = []
    var total = 0
    var refreshed = 0
    override func sendEmoji(accountId: String, chatGid: String, code: String, replyToId: Int?) async -> Outcome<Void> { sentEmoji.append((code, replyToId)); return .success(()) }
    override func retract(accountId: String, messageGid: String) async -> Outcome<Void> { retracted.append(messageGid); return .success(()) }
    override func timelineExtent(accountId: String, chatGid: String) async -> Outcome<ChatTimelineExtent> { extents.count > 1 ? extents.removeFirst() : extents[0] }
    override func messageCount(accountId: String, chatGid: String) async -> Outcome<Int> { .success(total) }
    override func refreshMessages(accountId: String, chatGid: String) async -> Outcome<Void> { refreshed += 1; return .success(()) }
    override func loadOlderMessages(accountId: String, chatGid: String, beforeServerId: Int?, inWindow: Bool, pageSize: Int?) async -> Outcome<Int> {
        olderCalls.append((beforeServerId, pageSize)); return .success(olderPages.isEmpty ? 0 : olderPages.removeFirst())
    }
}

final class UseCaseTests: XCTestCase {
    // MARK: reactions

    private func reaction(_ gid: String, by user: Int, on target: Int, emoji: String = "👍", at s: TimeInterval, mine: Bool = false, state: SendState = .sent, deleted: Bool = false) -> ChatMessage {
        Make.message(gid, sender: user, at: Make.t0.addingTimeInterval(s), content: .emoji(emoji), mine: mine, state: state, replyTo: target, deleted: deleted)
    }

    func testBuildReactionsGroupsByEmojiAndKeepsLatestPerPerson() {
        let replies = [
            reaction("r1", by: 7, on: 100, at: 1), reaction("r2", by: 8, on: 100, at: 2), reaction("r3", by: 7, on: 100, emoji: "🎉", at: 3),
            reaction("r4", by: 7, on: 100, at: 4, mine: true), reaction("r5", by: 9, on: 100, at: 5, deleted: true),
            reaction("r6", by: 9, on: 100, at: 6, state: .failed), Make.message("t", content: .text("reply"), replyTo: 100),
        ]
        let out = BuildReactions()(replies)
        XCTAssertEqual(out.keys.sorted(), [100])
        let thumbs = out[100]!.first { $0.emoji == "👍" }!
        XCTAssertEqual(thumbs.userIds, [7, 8])           // r4 replaced r1 in place
        XCTAssertEqual(thumbs.mine?.gid, "r4")
        XCTAssertEqual(out[100]!.first { $0.emoji == "🎉" }!.count, 1)
        XCTAssertEqual(out[100]!.map(\.emoji), ["👍", "🎉"])
    }

    func testToggleReactionSendsEncodedEmojiThenRetracts() async {
        let repo = RecordingRepository()
        let target = Make.message("m", serverId: 100)
        let toggle = ToggleReaction(repo, now: { Make.t0.addingTimeInterval(30) })
        _ = await toggle(target, "👍", reactions: [])
        XCTAssertEqual(repo.sentEmoji.map(\.code), [":thumbsup:"]); XCTAssertEqual(repo.sentEmoji.first?.replyTo, 100)
        let mine = reaction("r1", by: 1, on: 100, at: 0, mine: true).with(serverId: 5)
        _ = await toggle(target, "👍", reactions: [MessageReaction(emoji: "👍", userIds: [1], mine: mine)])
        XCTAssertEqual(repo.retracted, ["r1"])
        let late = ToggleReaction(repo, now: { Make.t0.addingTimeInterval(500) })
        let r = await late(target, "👍", reactions: [MessageReaction(emoji: "👍", userIds: [1], mine: mine)])
        XCTAssertEqual(r.failure, .expired("Reaction can no longer be removed"))
        let unsent = await toggle(Make.message("x"), "👍", reactions: [])
        XCTAssertNotNil(unsent.failure)
    }

    func testIsReactionRow() {
        let row = IsReactionRow()
        XCTAssertTrue(row(replyToId: 5, deleted: false, contentType: "emotion", content: "😄"))
        XCTAssertTrue(row(replyToId: 5, deleted: true, contentType: "emotion", content: ""))
        XCTAssertFalse(row(replyToId: nil, deleted: false, contentType: "emotion", content: "😄"))
        XCTAssertFalse(row(replyToId: 5, deleted: false, contentType: "plain", content: "hello"))
    }

    // MARK: policies

    func testCanSendToChat() {
        var chat = Make.chat(); let can = CanSendToChat()
        XCTAssertTrue(can(chat, selfUserId: 1, selfAccount: "me"))
        chat.committers = "$ADMINS"; chat.adminIds = [2]; chat.ownerAccount = "boss"
        XCTAssertFalse(can(chat, selfUserId: 1, selfAccount: "me")); XCTAssertTrue(can(chat, selfUserId: 2, selfAccount: "x")); XCTAssertTrue(can(chat, selfUserId: 1, selfAccount: "boss"))
        chat.committers = "3, me"
        XCTAssertTrue(can(chat, selfUserId: 3, selfAccount: nil)); XCTAssertTrue(can(chat, selfUserId: 9, selfAccount: "me")); XCTAssertFalse(can(chat, selfUserId: 9, selfAccount: "you"))
    }

    func testUnreadCounts() {
        let chats = [Make.chat("1", type: .one2one, unread: 2), Make.chat("2", unread: 3), Make.chat("3", unread: 4, muted: true),
                     Make.chat("4", unread: 5, hidden: true), Make.chat("5", type: .bot, unread: 1), Make.chat("6", unread: 9, archived: true)]
        XCTAssertEqual(CountBadgeUnread()(chats), 6)
        XCTAssertEqual(CountTabUnread()(chats, .all), 10)   // muted still counts on its tab
        XCTAssertEqual(CountTabUnread()(chats, .groups), 7); XCTAssertEqual(CountTabUnread()(chats, .direct), 2); XCTAssertEqual(CountTabUnread()(chats, .bots), 1)
    }

    func testShouldNotify() {
        let n = ShouldNotifyChatMessage(); let m = Make.message()
        XCTAssertTrue(n(m, enabled: true, appFocused: false, visibleChat: nil))
        XCTAssertFalse(n(m, enabled: false, appFocused: false, visibleChat: nil))
        XCTAssertFalse(n(Make.message(mine: true), enabled: true, appFocused: false, visibleChat: nil))
        XCTAssertFalse(n(m, enabled: true, appFocused: true, visibleChat: ("a", "g")))
        XCTAssertTrue(n(m, enabled: true, appFocused: true, visibleChat: ("a", "g"), whileViewing: true))
        XCTAssertFalse(n(m, enabled: true, appFocused: false, visibleChat: nil, conversation: Make.chat(muted: true)))
        XCTAssertFalse(n(reaction("r", by: 1, on: 2, at: 0), enabled: true, appFocused: false, visibleChat: nil))
    }

    func testResolveTitleAndRoles() {
        let u = ChatUser(accountId: "a", userId: 5, account: "bob", realname: "")
        XCTAssertEqual(ResolveChatTitle()(Make.chat(type: .one2one), [:]), nil)
        var chat = Make.chat(type: .one2one); chat.peerUserId = 5
        XCTAssertEqual(ResolveChatTitle()(chat, [5: u]), "bob")
        XCTAssertEqual(ResolveChatTitle()(Make.chat(name: "  Team "), [:]), "Team")
        XCTAssertEqual(OrderChatRoles()(["dev", nil, "zz", "top", "aa", " qa "]), ["top", "dev", "qa", "aa", "zz", ""])
        XCTAssertEqual(chatRoleRank(of: "PM"), .lead); XCTAssertEqual(chatRoleRank(of: "opm"), .manager); XCTAssertNil(chatRoleRank(of: "dev"))
        XCTAssertEqual(chatRoleCodes(of: .manager), ["td", "pd", "qd", "opm"])
    }

    func testRetractWindowAndPin() async {
        let repo = RecordingRepository()
        let m = Make.message("m", mine: true, serverId: 1)
        let ok = RetractMessage(repo, now: { Make.t0.addingTimeInterval(119) }); let late = RetractMessage(repo, now: { Make.t0.addingTimeInterval(121) })
        XCTAssertTrue(ok.canRetract(m)); XCTAssertFalse(late.canRetract(m)); XCTAssertFalse(ok.canRetract(Make.message(serverId: 1)))
        var chat = Make.chat(); chat.adminIds = [4]; chat.ownerAccount = "o"
        let pin = PinChatMessage(repo)
        XCTAssertTrue(pin.canPin(chat, selfUserId: 4, selfAccount: nil)); XCTAssertTrue(pin.canPin(chat, selfUserId: 1, selfAccount: "o")); XCTAssertFalse(pin.canPin(chat, selfUserId: 1, selfAccount: nil))
        XCTAssertTrue(pin.canPin(Make.chat(type: .one2one), selfUserId: nil, selfAccount: nil))
    }

    // MARK: threads / roster / links

    func testReplyThreads() {
        let replies = [Make.message("a", at: Make.t0.addingTimeInterval(1), serverId: 11, replyTo: 10), Make.message("b", sender: 8, at: Make.t0.addingTimeInterval(2), serverId: 12, replyTo: 11),
                       Make.message("c", at: Make.t0.addingTimeInterval(3), serverId: 13, replyTo: 99), Make.message("loop1", serverId: 20, replyTo: 21), Make.message("loop2", serverId: 21, replyTo: 20)]
        let t = BuildReplyThread()
        XCTAssertEqual(t.rootOf(12, replies), 10)
        XCTAssertEqual(t(10, replies).replies.map(\.gid), ["a", "b"])
        XCTAssertEqual(t.countsByRoot(replies)[10], 2)
        let s = t.summariesByRoot(replies)[10]!
        XCTAssertEqual(s.replierIds, [8, 7]); XCTAssertEqual(s.count, 2)
        _ = t.rootOf(20, replies)   // a cycle terminates
    }

    /// A long chain (each reply answering the one before) and many replies to one message resolve to their roots; the
    /// parent map is read once per call, not once per reply.
    func testReplyThreadsLongChainsAndBusyRoots() {
        let n = 3000
        let chain = (1...n).map { Make.message("c\($0)", at: Make.t0.addingTimeInterval(Double($0)), serverId: 1000 + $0, replyTo: 1000 + $0 - 1) }
        let fan = (1...n).map { Make.message("f\($0)", sender: $0 % 3, at: Make.t0.addingTimeInterval(Double($0)), serverId: 10_000 + $0, replyTo: 5) }
        let t = BuildReplyThread()
        let summaries = t.summariesByRoot(chain + fan)
        XCTAssertEqual(summaries[1000]?.count, n)
        XCTAssertEqual(summaries[5]?.count, n)
        XCTAssertEqual(summaries[5]?.replierIds, [0, 2, 1])
        XCTAssertEqual(t.countsByRoot(chain), [1000: n])
        XCTAssertEqual(t(1000 + n, chain).replies.count, n)
        XCTAssertEqual(t.rootOf(1000 + n, chain), 1000)
    }

    func testTypingRoster() {
        let t0 = Make.t0
        func sig(_ u: Int, _ typing: Bool = true, _ gid: String = "g") -> ChatTypingSignal { .init(chatGid: gid, userId: u, typing: typing) }
        var r = TypingRoster().apply(sig(7), now: t0)
        XCTAssertEqual(r.typing(in: "g"), [7]); XCTAssertEqual(r.nextExpiry, t0.addingTimeInterval(5))
        XCTAssertEqual(r.prune(t0.addingTimeInterval(4)).typing(in: "g"), [7]); XCTAssertEqual(r.prune(t0.addingTimeInterval(5)).typing(in: "g"), [])
        r = r.apply(sig(7), now: t0.addingTimeInterval(3)); XCTAssertEqual(r.prune(t0.addingTimeInterval(6)).typing(in: "g"), [7])
        r = TypingRoster().apply(sig(7), now: t0).apply(sig(7, false), now: t0)
        XCTAssertTrue(r.expiries.isEmpty); XCTAssertNil(r.nextExpiry)
        XCTAssertEqual(TypingRoster().apply(sig(40), now: t0, selfUserId: 40).typing(in: "g"), [])
        r = TypingRoster().apply(sig(8), now: t0).apply(sig(7), now: t0.addingTimeInterval(1)).apply(sig(9, true, "o"), now: t0)
        XCTAssertEqual(r.typing(in: "g"), [8, 7]); XCTAssertEqual(r.typing(in: "o"), [9])
    }

    func testMergeRequestLinks() {
        let p = ParseMergeRequestLink()
        let gl = p("https://gitlab.example.com/grp/sub/proj/-/merge_requests/42?x=1")!
        XCTAssertEqual(gl.provider, .gitlab); XCTAssertEqual(gl.kind, .mergeRequest); XCTAssertEqual(gl.project, "grp/sub/proj"); XCTAssertEqual(gl.number, "42")
        XCTAssertEqual(p("https://github.com/o/r/pull/7")?.provider, .github)
        XCTAssertEqual(p("https://github.com/o/r/issues/7")?.kind, .issue)
        XCTAssertNil(p("https://gitea.example.com/o/r/issues/7"))
        XCTAssertNil(p("not a url"))
        XCTAssertTrue(ParseMergeRequestLink.same(p("https://github.com/O/R/pull/7")!, p("https://github.com/o/r/issues/7")!))
    }

    func testFindLinkedTicketAndStickerLinks() {
        XCTAssertEqual(FindLinkedTicket.parse("https://zt.example.com/task-view-12406.html")?.id, "12406")
        XCTAssertEqual(FindLinkedTicket.parse("https://zt.example.com/index.php?m=bug&f=view&bugID=9")?.type, "bug")
        XCTAssertNil(FindLinkedTicket.parse("https://zt.example.com/index.php?m=bug&f=browse"))
        let t = Ticket(id: "t", accountId: "a", projectId: "p", providerType: .zentao, externalKey: "12406", title: "x", body: "", priority: .medium, status: .todo, providerStatus: "wait", sourceHash: "h", externalType: "Task", url: "https://zt.example.com/task-view-12406.html")
        XCTAssertEqual(FindLinkedTicket()("https://zt.example.com/task-view-12406.html", [t])?.id, "t")
        XCTAssertNil(FindLinkedTicket()("https://other.example.com/task-view-12406.html", [t]))
        let sp = ParseStickerPackLink()
        XCTAssertEqual(sp("https://t.me/addstickers/Cats_01"), "Cats_01"); XCTAssertEqual(sp("Cats_01"), "Cats_01"); XCTAssertNil(sp("https://example.com/x"))
    }

    // MARK: history download

    func testDownloadHistoryPagesBackToTheStart() async {
        let repo = RecordingRepository()
        repo.total = 450
        repo.extents = [.success(.init(count: 200, oldestServerId: 251)), .success(.init(count: 400, oldestServerId: 51)), .success(.init(count: 450, oldestServerId: 1, reachesStart: true))]
        repo.olderPages = [200, 50]
        var out: [ChatHistoryProgress] = []
        for await p in DownloadChatHistory(repo)(accountId: "a", chatGid: "g") { out.append(p.value!) }
        XCTAssertEqual(repo.olderCalls.map(\.before), [251, 51]); XCTAssertEqual(repo.olderCalls.map(\.pageSize), [200, 200])
        XCTAssertEqual(out.last, ChatHistoryProgress(stored: 450, total: 450, complete: true))
        XCTAssertEqual(out.first, ChatHistoryProgress(stored: 200, total: 450))
    }

    func testDownloadHistoryAlreadyCompleteAndStalled() async {
        let repo = RecordingRepository()
        repo.extents = [.success(.init(count: 10, oldestServerId: 1, reachesStart: true))]
        var out: [ChatHistoryProgress] = []
        for await p in DownloadChatHistory(repo)(accountId: "a", chatGid: "g") { out.append(p.value!) }
        XCTAssertEqual(out, [ChatHistoryProgress(stored: 10, total: 10, complete: true)]); XCTAssertTrue(repo.olderCalls.isEmpty)
        let stalled = RecordingRepository(); stalled.total = 100
        stalled.extents = [.success(.init(count: 10, oldestServerId: 50))]; stalled.olderPages = [5, 5, 5]
        var s: [ChatHistoryProgress] = []
        for await p in DownloadChatHistory(stalled)(accountId: "a", chatGid: "g") { s.append(p.value!) }
        XCTAssertEqual(stalled.olderCalls.count, 1); XCTAssertTrue(s.last?.complete ?? false)
    }

    func testSendTextEncodesAndRejectsEmpty() async {
        final class R: StubChatRepository, @unchecked Sendable { var sent: [(String, Bool)] = []
            override func sendText(accountId: String, chatGid: String, text: String, replyToId: Int?, markdown: Bool) async -> Outcome<Void> { sent.append((text, markdown)); return .success(()) } }
        let r = R(); let send = SendTextMessage(r)
        _ = await send(accountId: "a", chatGid: "g", text: "  ok 👍 **b **x  ", markdown: true)
        XCTAssertEqual(r.sent.first?.0, "ok :thumbsup: **b** x"); XCTAssertEqual(r.sent.first?.1, true)
        let empty = await send(accountId: "a", chatGid: "g", text: "  \n")
        XCTAssertNotNil(empty.failure)
        let code = await SendCodeMessage(r)(accountId: "a", chatGid: "g", code: " ")
        XCTAssertEqual(code.failure, .validation("Cannot send empty code"))
        XCTAssertEqual(CreateGroupChat(r).self is CreateGroupChat, true)
        let g = await CreateGroupChat(r)(accountId: "a", name: "x", memberIds: [1, 1])
        XCTAssertEqual(g.failure, .unexpected("A group needs at least two people"))
    }
}

extension ChatMessage {
    func with(serverId: Int) -> ChatMessage { var m = self; m.serverId = serverId; return m }
}

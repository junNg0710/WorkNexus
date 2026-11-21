import CoreDomain
import Foundation
import XCTest
@testable import FeatureChat

// Ported from: test/domain/chat/{chat_ai_test_support,build_chat_transcript_test,suggest_chat_replies_test,
// summarize_chat_test,rewrite_chat_draft_test}.dart

/// Answers every prompt with a set reply and keeps what was asked, instead of calling an AI backend.
private final class FakeAi: ChatAiTextGenerator, @unchecked Sendable {
    var answer: Outcome<ChatAiReply> = .success(ChatAiReply(""))
    private(set) var asked: [(key: String, prompt: String, model: String?)] = []
    private(set) var cancelled: [String] = []
    func generate(key: String, prompt: String, model: String?) async -> Outcome<ChatAiReply> { asked.append((key, prompt, model)); return answer }
    func cancel(_ key: String) async { cancelled.append(key) }
}

/// A text message from `sender` (user id) at `minute` past 09:00.
private func chatText(_ text: String, sender: Int = 2, minute: Int = 0, mine: Bool = false, serverId: Int? = nil, replyTo: Int? = nil,
                      content: MessageContent? = nil, deleted: Bool = false, notice: Bool = false) -> ChatMessage {
    let at = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9, minute: minute))!
    return ChatMessage(accountId: "a", gid: "g\(minute)\(text)", chatGid: "c", senderId: sender, sentAt: at, content: content ?? .text(text),
                       isMine: mine, serverId: serverId, replyToId: replyTo, deleted: deleted, isNotice: notice)
}

private func chatName(_ id: Int) -> String {
    switch id { case 2: "Lan"; case 3: "Minh"; default: "User \(id)" }
}

final class BuildChatTranscriptTests: XCTestCase {
    private let build = BuildChatTranscript()

    func testWritesMessagesOldestFirstWithTimeAndSender() {
        let r = build([chatText("second", sender: 3, minute: 5), chatText("first", minute: 1), chatText("mine", sender: 1, minute: 9, mine: true)],
                      nameOf: chatName, selfName: "An")
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.text, "[18/11 09:01] Lan: first\n[18/11 09:05] Minh: second\n[18/11 09:09] An: mine")
    }

    func testTurnsMentionsIntoNamesAndLineBreaksIntoSpaces() {
        let r = build([chatText("hi [@Minh](@#3),\nsee this")], nameOf: chatName, selfName: "An")
        XCTAssertTrue(r.text.hasSuffix("Lan: hi @Minh, see this"), r.text)
    }

    func testLeavesOutDeletedMessagesAndNoticesNamesAttachments() {
        let r = build([
            chatText("gone", deleted: true),
            chatText("Lan joined", minute: 1, notice: true),
            chatText("", minute: 2, content: .image(ImageContent(fileId: 1, name: "a.png", size: 1, time: 1))),
            chatText("", minute: 3, content: .file(FileContent(fileId: 2, name: "spec.pdf", size: 1, time: 1))),
            chatText("", minute: 4, content: .unsupported("conference")),
        ], nameOf: chatName, selfName: "An")
        XCTAssertEqual(r.count, 2)
        XCTAssertTrue(r.text.contains("Lan: [image]"))
        XCTAssertTrue(r.text.contains("Lan: [file: spec.pdf]"))
    }

    func testMarksWhoAReplyAnswers() {
        let r = build([chatText("question", sender: 3, serverId: 10), chatText("answer", minute: 1, replyTo: 10)], nameOf: chatName, selfName: "An")
        XCTAssertTrue(r.text.contains("Lan (↪ Minh): answer"), r.text)
    }

    func testDropsTheOldestMessagesPastTheSizeLimitAndClipsLongOnes() {
        let small = BuildChatTranscript(maxChars: 70, maxMessageChars: 10)
        let r = small([chatText("oldest message", minute: 1), chatText("middle message", minute: 2), chatText("newest message", minute: 3)],
                      nameOf: chatName, selfName: "An")
        XCTAssertEqual(r.count, 2)
        XCTAssertFalse(r.text.contains("oldest"))
        XCTAssertTrue(r.text.contains("newest mes…"))
    }
}

final class SuggestChatRepliesTests: XCTestCase {
    private func run(_ answer: String) async -> (Outcome<[String]>, FakeAi) {
        let ai = FakeAi()
        ai.answer = .success(ChatAiReply(answer))
        let r = await SuggestChatReplies(ai)([chatText("Can you review my MR today?")], key: "k", selfName: "An", nameOf: chatName)
        return (r, ai)
    }

    func testAsksForRepliesOnBehalfOfTheUser() async {
        let (_, ai) = await run(#"["Sure"]"#)
        XCTAssertEqual(ai.asked.first?.key, "k")
        let prompt = ai.asked.first?.prompt ?? ""
        XCTAssertTrue(prompt.contains("replies An could send"))
        XCTAssertTrue(prompt.contains("Lan: Can you review my MR today?"))
    }

    func testReadsTheJsonListKeepingAtMostThree() async {
        let (r, _) = await run(#"Here: ["Sure, after lunch", "Which MR?", "Done", "Later"]"#)
        XCTAssertEqual(r.value, ["Sure, after lunch", "Which MR?", "Done"])
    }

    func testFallsBackToOneReplyALineWithoutNumbering() async {
        let (r, _) = await run("1. \"Sure\"\n- Which MR?\n\n• Tomorrow works")
        XCTAssertEqual(r.value, ["Sure", "Which MR?", "Tomorrow works"])
    }

    func testNoRepliesIsAFailure() async {
        let (r, _) = await run("[]")
        XCTAssertNotNil(r.failure)
    }
}

final class SummarizeChatTests: XCTestCase {
    private func run(_ ai: FakeAi) async -> Outcome<ChatSummary> {
        await SummarizeChat(ai)([chatText("ship it on Friday?"), chatText("yes", sender: 3, minute: 1)], key: "k", languageName: "Vietnamese",
                                selfName: "An", nameOf: chatName, model: "m")
    }

    func testAsksInTheLanguageGivenQuotingTheConversation() async {
        let ai = FakeAi(); ai.answer = .success(ChatAiReply(#"{"overview": "ok"}"#))
        _ = await run(ai)
        let asked = try? XCTUnwrap(ai.asked.first)
        XCTAssertEqual(asked?.key, "k"); XCTAssertEqual(asked?.model, "m")
        XCTAssertTrue(asked?.prompt.contains("Write in Vietnamese") == true)
        XCTAssertTrue(asked?.prompt.contains("Lan: ship it on Friday?") == true)
        XCTAssertTrue(asked?.prompt.contains("2 messages") == true)
    }

    func testReadsEverySectionOfTheJsonAnswer() async throws {
        let ai = FakeAi()
        ai.answer = .success(ChatAiReply("""
        Sure! ```json
        {"overview": "Release planning.",
         "keyPoints": ["Friday release", " "],
         "decisions": ["Ship on Friday"],
         "actionItems": [{"owner": "Minh", "task": "Tag the build", "due": "Fri"},
                         {"owner": "x"}],
         "openQuestions": ["Who writes the notes?"]}
        ```
        """, model: "gemini"))
        let result = await run(ai)
        let s = try XCTUnwrap(result.value)
        XCTAssertEqual(s.overview, "Release planning.")
        XCTAssertEqual(s.keyPoints, ["Friday release"])
        XCTAssertEqual(s.decisions, ["Ship on Friday"])
        XCTAssertEqual(s.actionItems, [ChatActionItem(task: "Tag the build", owner: "Minh", due: "Fri")])
        XCTAssertEqual(s.openQuestions, ["Who writes the notes?"])
        XCTAssertEqual(s.messageCount, 2)
        XCTAssertEqual(s.model, "gemini")
    }

    func testAnAnswerThatIsNotJsonBecomesTheOverview() async throws {
        let ai = FakeAi(); ai.answer = .success(ChatAiReply("  They agreed to ship on Friday.  "))
        let result = await run(ai)
        let s = try XCTUnwrap(result.value)
        XCTAssertEqual(s.overview, "They agreed to ship on Friday.")
        XCTAssertTrue(s.keyPoints.isEmpty)
    }

    func testPassesAFailureThrough() async {
        let ai = FakeAi(); ai.answer = .failure(.auth("bad key"))
        let result = await run(ai)
        XCTAssertEqual(result.failure, .auth("bad key"))
    }

    func testDoesNotCallTheModelWithoutMessages() async {
        let ai = FakeAi()
        let r = await SummarizeChat(ai)([chatText("gone", deleted: true)], key: "k", languageName: "English", selfName: "An", nameOf: chatName)
        XCTAssertNotNil(r.failure)
        XCTAssertTrue(ai.asked.isEmpty)
    }
}

final class RewriteChatDraftTests: XCTestCase {
    func testAsksForTheToneQuotingTheDraftAndTheContext() async {
        let ai = FakeAi(); ai.answer = .success(ChatAiReply("Could you review it today, please?"))
        let r = await RewriteChatDraft(ai)("review it today", tone: .formal, key: "k", context: [chatText("I pushed the fix")],
                                           selfName: "An", nameOf: chatName)
        XCTAssertEqual(r.value, "Could you review it today, please?")
        let prompt = ai.asked.first?.prompt ?? ""
        XCTAssertTrue(prompt.contains("polite, professional tone"))
        XCTAssertTrue(prompt.contains("review it today"))
        XCTAssertTrue(prompt.contains("Lan: I pushed the fix"))
    }

    func testTakesTheQuotesAndCodeFenceOffTheAnswer() async {
        let ai = FakeAi(); ai.answer = .success(ChatAiReply("```\n\"Shorter.\"\n```"))
        let r = await RewriteChatDraft(ai)("a much longer draft", tone: .shorter, key: "k")
        XCTAssertEqual(r.value, "Shorter.")
        XCTAssertFalse(ai.asked.first?.prompt.contains("context only") ?? true)
    }

    func testABlankDraftIsRefusedWithoutAsking() async {
        let ai = FakeAi()
        let r = await RewriteChatDraft(ai)("  ", tone: .clearer, key: "k")
        XCTAssertNotNil(r.failure)
        XCTAssertTrue(ai.asked.isEmpty)
    }

    func testShouldOfferChatSummaryFromTheThresholdUp() {
        XCTAssertFalse(ShouldOfferChatSummary()(unread: 19))
        XCTAssertTrue(ShouldOfferChatSummary()(unread: 20))
        XCTAssertTrue(ShouldOfferChatSummary(threshold: 5)(unread: 5))
    }

    func testTheSummaryLanguageIsThePickedOneElseTheAppsOutOfTheOffered() {
        let vi = ChatAiLanguage(code: "vi", englishName: "Vietnamese", nativeName: "Tiếng Việt", flag: "🇻🇳")
        let en = ChatAiLanguage(code: "en", englishName: "English", nativeName: "English", flag: "🇬🇧")
        let resolve = ResolveChatSummaryLanguage()
        XCTAssertEqual(resolve(picked: nil, appLanguage: "en", offered: [vi, en]), en)
        XCTAssertEqual(resolve(picked: "vi", appLanguage: "en", offered: [vi, en]), vi)
        XCTAssertEqual(resolve(picked: nil, appLanguage: "fr", offered: [vi, en]), vi)
        XCTAssertEqual(resolve(picked: nil, appLanguage: "vi", offered: []).englishName, "English")
        // The app in Simplified Chinese summarises in the languages' Chinese.
        let zh = ChatAiLanguage(code: "zh", englishName: "Chinese (Simplified)", nativeName: "中文", flag: "🇨🇳")
        XCTAssertEqual(resolve(picked: nil, appLanguage: "zh-Hans", offered: [vi, en, zh]), zh)
    }

    func testPeopleAreNamedByTheirRealNameElseByTheirId() {
        let users = [1: ChatUser(accountId: "a", userId: 1, account: "an", realname: "An"),
                     2: ChatUser(accountId: "a", userId: 2, account: "lan", realname: "")]
        let people = ChatAiPeople(users: users, selfUserId: 1)
        XCTAssertEqual(people.selfName, "An")
        XCTAssertEqual(people.name(of: 2), "User 2")
        XCTAssertEqual(ChatAiPeople(users: [:], selfUserId: nil).selfName, "Me")
    }
}

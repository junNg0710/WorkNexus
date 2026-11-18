import CoreDomain
import XCTest
@testable import FeatureChat

/// "Share in chat" from a ticket: the text goes to each picked chat, as plain text, and a failure stops it.
final class ShareTextToChatsTests: XCTestCase {
    final class Repo: StubChatRepository, @unchecked Sendable {
        var sent: [(String, String, Bool)] = []
        var failOn: String?
        override func sendText(accountId: String, chatGid: String, text: String, replyToId: Int?, markdown: Bool) async -> Outcome<Void> {
            if chatGid == failOn { return .failure(.network("down")) }
            sent.append((chatGid, text, markdown)); return .success(())
        }
    }

    func testTheTextGoesToEveryPickedChat() async {
        let repo = Repo()
        let r = await ShareTextToChats(repo)(accountId: "a", chatGids: ["g1", "g2"], text: " #7463 Blank space\nhttps://zt/bug-view-7463.html \n")
        guard case .success = r else { return XCTFail("\(r)") }
        XCTAssertEqual(repo.sent.map(\.0), ["g1", "g2"])
        XCTAssertEqual(repo.sent.first?.1, "#7463 Blank space\nhttps://zt/bug-view-7463.html")
        XCTAssertEqual(repo.sent.first?.2, false, "plain text: a ticket title is not Markdown")
    }

    func testAFailureStopsAndNothingIsSentWithoutTextOrChats() async {
        let repo = Repo(); repo.failOn = "g1"
        guard case .failure = await ShareTextToChats(repo)(accountId: "a", chatGids: ["g1", "g2"], text: "x") else { return XCTFail() }
        XCTAssertTrue(repo.sent.isEmpty)
        guard case .failure = await ShareTextToChats(repo)(accountId: "a", chatGids: [], text: "x") else { return XCTFail() }
        guard case .failure = await ShareTextToChats(repo)(accountId: "a", chatGids: ["g2"], text: "  ") else { return XCTFail() }
        XCTAssertTrue(repo.sent.isEmpty)
    }
}

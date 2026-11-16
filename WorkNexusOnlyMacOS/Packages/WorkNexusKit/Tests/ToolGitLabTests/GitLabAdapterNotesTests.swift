import CoreDomain
import XCTest
@testable import ToolGitLab

/// Ports of test/data/gitlab_adapter_notes_test.dart.
final class GitLabAdapterNotesTests: XCTestCase {
    private let net = StubNetwork.shared
    private let issue = Fixtures.ticket(type: "Issue")

    override func setUp() { net.reset() }

    func testCommentsAndActivityShareOneNotesRequest() async {
        net.reset { _ in .json(#"[{"id":1,"body":"looks good"},{"id":2,"body":"assigned to @me","system":true}]"#) }
        let adapter = Fixtures.adapter()
        let comments = await adapter.listComments(issue)
        let activity = await adapter.listActivity(issue)
        XCTAssertEqual(comments.value?.count, 1)
        XCTAssertEqual(activity.value?.count, 1)
        XCTAssertEqual(net.requests.count, 1)
    }

    func testActivitySummaryStripsMarkupAndKeepsFirstLine() async {
        net.reset { _ in .json(#"[{"id":2,"body":"**added 2 commits**\n\n<ul><li>abc</li></ul>","system":true}]"#) }
        let activity = await Fixtures.adapter().listActivity(issue)
        XCTAssertEqual(activity.value?.first?.action, "added 2 commits")
    }

    func testFailedNotesRequestIsAskedAgain() async {
        let calls = Counter()
        net.reset { _ in calls.next() == 1 ? .json("{}", status: 500) : .json(#"[{"id":1,"body":"back"}]"#) }
        let adapter = Fixtures.adapter()
        let first = await adapter.listComments(issue)
        let second = await adapter.listComments(issue)
        XCTAssertNotNil(first.failure)
        XCTAssertEqual(second.value?.count, 1)
        XCTAssertEqual(net.requests.count, 2)
    }

    // The adapter is pooled for the session: a later refresh (which starts with getTicket) must not be served the
    // notes of an earlier one.
    func testLaterDetailRefreshFetchesNotesAgain() async {
        let calls = Counter()
        net.reset { r in
            if r.encodedPath.hasSuffix("/notes") { let n = calls.next(); return .json(#"[{"id":\#(n),"body":"note \#(n)"}]"#) }
            return .json("{}", status: 500)   // getTicket fails — it still has to drop the cached notes
        }
        let adapter = Fixtures.adapter()
        _ = await adapter.listComments(issue)
        _ = await adapter.getTicket(issue)
        let again = await adapter.listComments(issue)
        XCTAssertEqual(again.value?.first?.body, "note 2")
        XCTAssertEqual(net.requests.filter { $0.encodedPath.hasSuffix("/notes") }.count, 2)
    }
}

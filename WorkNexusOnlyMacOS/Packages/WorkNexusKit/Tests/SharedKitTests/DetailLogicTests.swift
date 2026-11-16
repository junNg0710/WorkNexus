import CoreDomain
import XCTest
@testable import SharedKit

/// Ported from: lib/shared/detail/presentation/util/activity_action_parts.dart behaviour + detail helpers.
final class DetailLogicTests: XCTestCase {
    func testAssignedToSplitsTheUser() {
        XCTAssertEqual(activityActionParts("assigned to Thanh"), [ActivityPart("assigned to ", .plain), ActivityPart("Thanh", .user)])
    }

    func testFieldChangeSplitsNameAndValue() {
        XCTAssertEqual(activityActionParts("Status: active → resolved"), [ActivityPart("Status: ", .plain), ActivityPart("active → resolved", .value)])
    }

    func testMentionsBecomeUserParts() {
        XCTAssertEqual(activityActionParts("pinged @ryan.le and @cat"),
                       [ActivityPart("pinged ", .plain), ActivityPart("@ryan.le", .user), ActivityPart(" and ", .plain), ActivityPart("@cat", .user)])
        XCTAssertEqual(activityActionParts("closed"), [ActivityPart("closed", .plain)])
    }

    func testActivityKindFromTheLeadingVerb() {
        XCTAssertEqual(activityKindOf("Created the bug"), .created); XCTAssertEqual(activityKindOf("opened"), .created)
        XCTAssertEqual(activityKindOf("assigned to X"), .assigned); XCTAssertEqual(activityKindOf("edited · title"), .edited)
        XCTAssertEqual(activityKindOf("resolved (fixed)"), .resolved); XCTAssertEqual(activityKindOf("merged"), .merged)
        XCTAssertEqual(activityKindOf("activated"), .reopened); XCTAssertEqual(activityKindOf("confirmed"), .confirmed)
        XCTAssertEqual(activityKindOf("closed"), .closed); XCTAssertEqual(activityKindOf("whatever"), .other)
    }

    func testTitleWithRefAndDiffCounts() {
        let gh = makeTicket("a", key: "42", title: "Crash")
        XCTAssertEqual(ticketTitleWithRef(gh), "#42 Crash")
        XCTAssertEqual(ticketTitleWithRef(makeTicket("b", provider: .jira, key: "PROJ-7", title: "X")), "PROJ-7 X")
        let diff = "--- a\n+++ b\n@@ -1 +1,2 @@\n-old\n+new\n+more\n context"
        XCTAssertEqual(countDiffLines(diff).additions, 2); XCTAssertEqual(countDiffLines(diff).deletions, 1)
        XCTAssertEqual(countDiffLines(nil).additions, 0)
    }

    func testAttachmentKinds() {
        XCTAssertEqual(AttachmentKinds.ext(of: TicketAttachment(id: "1", title: "Shot.PNG", url: "u")), "png")
        XCTAssertEqual(AttachmentKinds.ext(of: TicketAttachment(id: "1", title: "x", url: "u", extension: "MP4")), "mp4")
        XCTAssertTrue(AttachmentKinds.video.contains("mov")); XCTAssertTrue(AttachmentKinds.image.contains("heic"))
    }

    func testSyntheticLabelsAreHidden() {
        XCTAssertEqual(SyntheticLabels.visible(["bug", "zentao-product:1", "github-repo:o/r", "ui"]), ["bug", "ui"])
        XCTAssertEqual(SyntheticLabels.gitlabMine("a"), "gitlab-mine:a"); XCTAssertTrue(SyntheticLabels.isSynthetic("zentao-execution:3"))
    }

    func testRecentRepoCommitShortSha() {
        XCTAssertEqual(RepoCommit(sha: "0123456789abcdef", title: "t").shortSha, "01234567")
        XCTAssertEqual(RepoCommit(sha: "0123456789abcdef", shortSha: "0123456", title: "t").shortSha, "0123456")
    }
}


// MARK: debounce (scope_filter_field.dart), back mouse button (detail_overlay.dart)

@MainActor
final class FilterDebounceTests: XCTestCase {
    func testTypingIsAppliedAfterThePauseAndTheLastQueryWins() async throws {
        let debounce = FilterDebounce()
        var applied: [String] = []
        debounce.submit("a", delay: .milliseconds(40)) { applied.append($0) }
        debounce.submit("ab", delay: .milliseconds(40)) { applied.append($0) }
        XCTAssertTrue(applied.isEmpty, "nothing is applied before the pause")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(applied, ["ab"])
    }

    func testClearingIsImmediateAndCancelsAPendingQuery() async throws {
        let debounce = FilterDebounce()
        var applied: [String] = []
        debounce.submit("abc", delay: .milliseconds(40)) { applied.append($0) }
        debounce.submit("", delay: .milliseconds(40)) { applied.append($0) }
        XCTAssertEqual(applied, [""])
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(applied, [""], "the cancelled query must not arrive late")
    }

    func testCancelDropsAPendingQuery() async throws {
        let debounce = FilterDebounce()
        var applied: [String] = []
        debounce.submit("x", delay: .milliseconds(30)) { applied.append($0) }
        debounce.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(FilterDebounce.defaultDelay, .milliseconds(150))
    }
}

final class BackMouseButtonTests: XCTestCase {
    func testOnlyButtonThreeIsBack() {
        XCTAssertTrue(BackMouseButton.isBack(3))
        XCTAssertFalse(BackMouseButton.isBack(4), "forward")
        XCTAssertFalse(BackMouseButton.isBack(2), "middle")
    }
}

import CoreDomain
import XCTest
@testable import ToolGitLab

/// Ports of test/data/gitlab_normalize_test.dart, gitlab_label_color_test.dart, gitlab_draft_title_test.dart.
final class GitLabNormalizeTests: XCTestCase {
    private let acct = "gl-acme"

    private func issue(state: String = "opened", labels: [String] = [], full: String? = "group/web#42") -> GitLabIssue {
        GitLabIssue(id: 1001, iid: 42, projectId: 7, title: "An issue", description: "body", state: state,
                    labels: labels.map { GitLabLabel(name: $0) }, webUrl: "https://gl/group/web/-/issues/42",
                    references: full.map { GitLabReferences(full: $0) }, updatedAt: "2026-07-01T10:00:00Z")
    }

    private func mr(state: String = "opened", draft: Bool = false, full: String? = "group/web!7") -> GitLabMergeRequest {
        GitLabMergeRequest(id: 2001, iid: 7, projectId: 7, title: "An MR", description: "body", state: state, draft: draft,
                           sourceBranch: "feature/x", targetBranch: "main", webUrl: "https://gl/group/web/-/merge_requests/7",
                           references: full.map { GitLabReferences(full: $0) })
    }

    private func decodeMr(_ json: String) throws -> GitLabMergeRequest {
        try GitLabClient.decodeObject(Data(json.utf8), as: GitLabMergeRequest.self)
    }

    private func entity(_ t: Ticket) -> GitLabItemEntity? { if case .gitlabItem(let e)? = t.providerEntity { return e } else { return nil } }

    // MARK: issues

    func testOpenedIssueIsTodoWithStableIdsAndProjectPath() {
        let t = normalizeGitLabIssue(issue(), accountId: acct)
        XCTAssertEqual(t.id, "gl-acme:issue:1001")
        XCTAssertEqual(t.externalKey, "42")
        XCTAssertEqual(t.externalType, "Issue")
        XCTAssertEqual(t.providerType, .gitlab)
        XCTAssertEqual(t.projectId, "gl-acme:group/web")
        XCTAssertEqual(t.status, .todo)
        XCTAssertEqual(t.providerStatus, "opened")
        XCTAssertEqual(t.url, "https://gl/group/web/-/issues/42")
    }

    func testClosedIssueIsDone() {
        let t = normalizeGitLabIssue(issue(state: "closed"), accountId: acct)
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.providerStatus, "closed")
    }

    func testInProgressLabelPromotesOpenedIssue() {
        XCTAssertEqual(normalizeGitLabIssue(issue(labels: ["Doing"]), accountId: acct).status, .inprogress)
    }

    func testBlockedLabelWins() {
        XCTAssertEqual(normalizeGitLabIssue(issue(labels: ["blocked"]), accountId: acct).status, .blocked)
    }

    func testPriorityLabels() {
        XCTAssertEqual(normalizeGitLabIssue(issue(labels: ["priority::high"]), accountId: acct).priority, .high)
        XCTAssertEqual(normalizeGitLabIssue(issue(), accountId: acct).priority, .medium)
        XCTAssertNil(gitLabPriorityFromLabels(["bug"]))
    }

    func testFallsBackToNumericProjectIdWithoutReferences() {
        XCTAssertEqual(normalizeGitLabIssue(issue(full: nil), accountId: acct).projectId, "gl-acme:7")
    }

    func testSourceHashMatchesDartIntHash() {
        // Dart: intHash('t b') = ((('t'*31)+' ')*31)+'b' & 0x7fffffff → hex
        var h = 0
        for c in "t b".utf16 { h = (h * 31 + Int(c)) & 0x7fffffff }
        XCTAssertEqual(contentHash(title: "t", body: "b"), String(h, radix: 16))
        XCTAssertEqual(contentHash(title: "", body: ""), String(32, radix: 16))   // single space → 32
    }

    // MARK: merge requests

    func testCarriesUserAvatarsMilestoneAndTimeStatsIntoCachedDetail() throws {
        let m = try decodeMr("""
        {"id":2001,"iid":7,"project_id":7,"title":"An MR","state":"opened","references":{"full":"group/web!7"},
         "author":{"id":1,"username":"thanh","name":"Thanh","avatar_url":"https://cdn.example.com/thanh.png"},
         "assignees":[{"id":1,"username":"thanh","name":"Thanh","avatar_url":"https://cdn.example.com/thanh.png"}],
         "reviewers":[{"id":2,"username":"reviewer","name":"Reviewer","avatar_url":"https://cdn.example.com/reviewer.png"}],
         "milestone":{"id":12,"iid":3,"title":"Release 1.0"},
         "time_stats":{"time_estimate":7200,"total_time_spent":3600,"human_time_estimate":"2h","human_total_time_spent":"1h"}}
        """)
        let e = try XCTUnwrap(entity(normalizeGitLabMergeRequest(m, accountId: acct)))
        XCTAssertEqual(e.authorAvatarUrl, "https://cdn.example.com/thanh.png")
        XCTAssertEqual(e.userAvatarUrls, ["Thanh": "https://cdn.example.com/thanh.png", "Reviewer": "https://cdn.example.com/reviewer.png"])
        XCTAssertEqual(e.milestoneId, 12)
        XCTAssertEqual(e.milestoneTitle, "Release 1.0")
        // Display names for showing, usernames for matching the account.
        XCTAssertEqual(e.assignees, ["Thanh"])
        XCTAssertEqual(e.assigneeLogins, ["thanh"])
        XCTAssertEqual(e.humanTimeEstimate, "2h")
        XCTAssertEqual(e.humanTotalTimeSpent, "1h")
    }

    func testCarriesWhoMergedItAndMergeOptions() throws {
        let m = try decodeMr("""
        {"id":2002,"iid":8,"project_id":7,"state":"merged","merged_by":{"id":3,"username":"kan","name":"Kan"},
         "merged_at":"2026-10-01T11:30:00Z","merge_commit_sha":"a78f2b73deadbeef","squash_commit_sha":"c0ffee12",
         "squash":true,"force_remove_source_branch":true}
        """)
        let e = try XCTUnwrap(entity(normalizeGitLabMergeRequest(m, accountId: acct)))
        XCTAssertEqual(e.mergedBy, "Kan")
        XCTAssertNotNil(e.mergedAt)
        XCTAssertEqual(e.mergeCommitSha, "a78f2b73deadbeef")
        XCTAssertEqual(e.squashCommitSha, "c0ffee12")
        XCTAssertEqual(e.squash, true)
        XCTAssertEqual(e.removeSourceBranch, true)
    }

    func testDraftMrIsInProgressWithRawStatusDraft() {
        let t = normalizeGitLabMergeRequest(mr(draft: true), accountId: acct)
        XCTAssertEqual(t.status, .inprogress)
        XCTAssertEqual(t.providerStatus, "draft")
        XCTAssertEqual(t.externalType, "MergeRequest")
        XCTAssertEqual(t.id, "gl-acme:mr:2001")
    }

    func testReadyOpenedMrIsReview() {
        let t = normalizeGitLabMergeRequest(mr(), accountId: acct)
        XCTAssertEqual(t.status, .review)
        XCTAssertEqual(t.providerStatus, "opened")
    }

    func testMergedAndClosedMrsAreDone() {
        let merged = normalizeGitLabMergeRequest(mr(state: "merged"), accountId: acct)
        XCTAssertEqual(merged.status, .done)
        XCTAssertEqual(merged.providerStatus, "merged")
        XCTAssertEqual(normalizeGitLabMergeRequest(mr(state: "closed"), accountId: acct).status, .done)
        XCTAssertEqual(mapGitLabMrStatus("locked", false, []), .blocked)
    }

    func testCarriesMrMetadataInProviderEntity() throws {
        let e = try XCTUnwrap(entity(normalizeGitLabMergeRequest(mr(), accountId: acct)))
        XCTAssertEqual(e.projectPath, "group/web")
        XCTAssertEqual(e.projectId, 7)
        XCTAssertEqual(e.sourceBranch, "feature/x")
        XCTAssertEqual(e.targetBranch, "main")
        XCTAssertEqual(e.draft, false)
    }

    func testProjectPathFrom() {
        XCTAssertEqual(projectPathFrom("group/web#42", "#", 7), "group/web")
        XCTAssertEqual(projectPathFrom("a/b/c!12", "!", 7), "a/b/c")
        XCTAssertEqual(projectPathFrom(nil, "#", 7), "7")
    }

    // MARK: label colours

    private let labelMr = """
    {"id":111,"iid":987,"project_id":9,"title":"Draft: fix","state":"opened","draft":true,
     "labels":[{"id":1,"name":"do-not-merge","color":"#dc143c","text_color":"#FFFFFF"}],
     "references":{"full":"root/tbchat_socialfi!987"}}
    """

    func testWithLabelsDetailsParsesNameAndColor() throws {
        let m = try decodeMr(labelMr)
        XCTAssertEqual(m.labelNames, ["do-not-merge"])
        XCTAssertEqual(m.labelColorMap, ["do-not-merge": "#dc143c"])
        XCTAssertEqual(m.labelTextColorMap, ["do-not-merge": "#FFFFFF"])
    }

    func testNormalizedTicketCarriesLabelColors() throws {
        let t = normalizeGitLabMergeRequest(try decodeMr(labelMr), accountId: "acc")
        let e = try XCTUnwrap(entity(t))
        XCTAssertEqual(e.labelColors, ["do-not-merge": "#dc143c"])
        XCTAssertEqual(e.labelTextColors, ["do-not-merge": "#FFFFFF"])
        XCTAssertEqual(t.labels, ["do-not-merge"])
    }

    func testBareStringLabelsStillParseWithoutColors() throws {
        let m = try decodeMr(labelMr.replacingOccurrences(of: ##"[{"id":1,"name":"do-not-merge","color":"#dc143c","text_color":"#FFFFFF"}]"##,
                                                          with: ##"["do-not-merge"]"##))
        XCTAssertEqual(m.labelNames, ["do-not-merge"])
        XCTAssertTrue(m.labelColorMap.isEmpty)
    }

    // MARK: draft title

    func testReadyTitleStripsEveryPrefixGitLabTreatsAsDraft() {
        XCTAssertEqual(readyTitle("Draft: Fix login"), "Fix login")
        XCTAssertEqual(readyTitle("[Draft] Fix login"), "Fix login")
        XCTAssertEqual(readyTitle("(draft) Fix login"), "Fix login")
        XCTAssertEqual(readyTitle("WIP: Fix login"), "Fix login")
        XCTAssertEqual(readyTitle("Draft: [WIP] Fix login"), "Fix login")
    }

    func testReadyTitleLeavesTitleThatOnlyMentionsDraftAlone() {
        XCTAssertEqual(readyTitle("Fix draft autosave"), "Fix draft autosave")
    }

    func testDraftTitleAddsCanonicalPrefixExactlyOnce() {
        XCTAssertEqual(draftTitle("Fix login"), "Draft: Fix login")
        XCTAssertEqual(draftTitle("WIP: Fix login"), "Draft: Fix login")
    }
}

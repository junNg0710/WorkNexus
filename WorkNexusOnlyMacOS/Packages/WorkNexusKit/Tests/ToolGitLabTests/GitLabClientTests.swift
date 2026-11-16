import XCTest
@testable import ToolGitLab

/// Ports of test/data/gitlab_client_test.dart + gitlab_client_current_user_test.dart (fake dio → URLProtocol stub).
final class GitLabClientTests: XCTestCase {
    private let net = StubNetwork.shared
    private let png: [UInt8] = [0x89, 0x50, 0x4e, 0x47]

    override func setUp() { net.reset() }

    func testPaginatedListRequestsUseSharedPageSize() async throws {
        net.reset { _ in .json("[]") }
        _ = try await Fixtures.client().projects()
        XCTAssertEqual(net.requests.count, 1)
        XCTAssertEqual(net.requests[0].query["per_page"], "500")
        XCTAssertEqual(net.requests[0].encodedPath, "/api/v4/projects")
        XCTAssertEqual(net.requests[0].header("PRIVATE-TOKEN"), "pat123")
    }

    func testPaginationFollowsXNextPageAndStopsWhenItDoesNotAdvance() async throws {
        net.reset { req in
            switch req.query["page"] {
            case "1": return .json(#"[{"id":1,"name":"a"}]"#, headers: ["X-Next-Page": "2"])
            case "2": return .json(#"[{"id":2,"name":"b"}]"#, headers: ["X-Next-Page": "2"])   // does not advance
            default: return .json("[]")
            }
        }
        let projects = try await Fixtures.client().projects()
        XCTAssertEqual(projects.map(\.id), [1, 2])
        XCTAssertEqual(net.requests.count, 2)
    }

    func testMyMergeRequestFeedsRequestAssignedAndReviewScopes() async throws {
        net.reset { _ in .json("[]") }
        let client = Fixtures.client()
        _ = try await client.assignedMergeRequests()
        _ = try await client.reviewMergeRequests(username: "alice")
        XCTAssertEqual(net.requests.count, 2)
        XCTAssertEqual(net.requests[0].encodedPath, "/api/v4/merge_requests")
        XCTAssertEqual(net.requests[0].query["scope"], "assigned_to_me")
        XCTAssertEqual(net.requests[1].encodedPath, "/api/v4/merge_requests")
        XCTAssertEqual(net.requests[1].query["scope"], "reviews_for_me")
        XCTAssertNil(net.requests[1].query["reviewer_username"])
    }

    func testMrMetadataMutationsUseGitLab163CompatiblePayloads() async throws {
        let client = Fixtures.client()
        try await client.updateMergeRequest("group%2Fweb", "42", labels: ["backend", "review"], milestoneId: 12)
        try await client.setMergeRequestTimeEstimate("group%2Fweb", "42", "2h")
        try await client.addMergeRequestSpentTime("group%2Fweb", "42", "30m")
        XCTAssertEqual(net.requests.count, 3)
        XCTAssertEqual(net.requests[0].method, "PUT")
        XCTAssertEqual(net.requests[0].json?["labels"] as? String, "backend,review")
        XCTAssertEqual(net.requests[0].json?["milestone_id"] as? Int, 12)
        XCTAssertEqual(net.requests[0].json?.count, 2)
        XCTAssertEqual(net.requests[1].encodedPath, "/api/v4/projects/group%2Fweb/merge_requests/42/time_estimate")
        XCTAssertEqual(net.requests[1].json?["duration"] as? String, "2h")
        XCTAssertEqual(net.requests[2].encodedPath, "/api/v4/projects/group%2Fweb/merge_requests/42/add_spent_time")
        XCTAssertEqual(net.requests[2].json?["duration"] as? String, "30m")
    }

    func testMrMetadataOptionsUseProjectLabelAndMilestoneApis() async throws {
        net.reset { req in
            req.encodedPath.hasSuffix("/labels")
                ? .json(##"[{"name":"backend","color":"#428BCA"}]"##)
                : .json(#"[{"id":12,"iid":3,"title":"Release 1.0"}]"#)
        }
        let client = Fixtures.client()
        let labels = try await client.projectLabels("group%2Fweb")
        let milestones = try await client.projectMilestones("group%2Fweb")
        XCTAssertEqual(labels.first?.name, "backend")
        XCTAssertEqual(labels.first?.color, "#428BCA")
        XCTAssertEqual(milestones.first?.title, "Release 1.0")
        XCTAssertEqual(net.requests[1].query["state"], "active")
        XCTAssertEqual(net.requests[1].query["include_parent_milestones"], "true")
    }

    func testReviewFeedFallsBackToReviewerUsernameWhenScopeUnsupported() async throws {
        net.reset { req in
            req.query["scope"] == "reviews_for_me" ? .json(#"{"error":"scope does not have a valid value"}"#, status: 400) : .json("[]")
        }
        _ = try await Fixtures.client().reviewMergeRequests(username: "alice")
        XCTAssertEqual(net.requests.count, 2)
        XCTAssertEqual(net.requests[0].query["scope"], "reviews_for_me")
        XCTAssertEqual(net.requests[1].query["reviewer_username"], "alice")
        XCTAssertNil(net.requests[1].query["scope"])
    }

    func testReviewFeedRethrowsOtherFailures() async {
        net.reset { _ in .json(#"{"message":"boom"}"#, status: 500) }
        do { _ = try await Fixtures.client().reviewMergeRequests(username: "alice"); XCTFail("expected throw") }
        catch { XCTAssertEqual(net.requests.count, 1) }
    }

    func testFetchBytesRoutesBareUploadsLinkToMarkdownUploadsApiWithPat() async throws {
        net.reset { [png] _ in .image(png) }
        let bytes = try await Fixtures.client().fetchBytes(
            "/uploads/11043117eeafd1cd26d74dbdcf8279a0/pasted_image_1778757174593.png", projectPath: "root/tbchat", projectId: 42)
        XCTAssertEqual(bytes, Data(png))
        let req = try XCTUnwrap(net.requests.first)
        // The numeric project id is preferred, on the PAT-readable API endpoint — NOT the web path.
        XCTAssertEqual(req.encodedPath, "/api/v4/projects/42/uploads/11043117eeafd1cd26d74dbdcf8279a0/pasted_image_1778757174593.png")
        XCTAssertEqual(req.header("PRIVATE-TOKEN"), "pat123")
    }

    func testFetchBytesFallsBackToUrlEncodedProjectPathWhenNoIdIsKnown() async throws {
        net.reset { [png] _ in .image(png) }
        _ = try await Fixtures.client().fetchBytes("/uploads/abc123/img.png", projectPath: "group/web")
        // `group/web` is a single, percent-encoded path segment (`group%2Fweb`).
        XCTAssertEqual(net.requests.first?.url.absoluteString, "https://gitlab.example.com/api/v4/projects/group%2Fweb/uploads/abc123/img.png")
    }

    func testFetchBytesReturnsNilForNonImageResponse() async throws {
        net.reset { _ in .html() }
        let bytes = try await Fixtures.client().fetchBytes("/uploads/abc123/img.png", projectId: 42)
        XCTAssertNil(bytes)
    }

    func testFetchBytesFetchesAbsoluteImageUrlAsIsWithoutPat() async throws {
        net.reset { [png] _ in .image(png) }
        _ = try await Fixtures.client().fetchBytes("https://cdn.example.com/pic.png", projectId: 42)
        let req = try XCTUnwrap(net.requests.first)
        XCTAssertEqual(req.url.absoluteString, "https://cdn.example.com/pic.png")
        // The PAT must never leak to a third-party host.
        XCTAssertNil(req.header("PRIVATE-TOKEN"))
    }

    func testBaseUrlNormalization() {
        XCTAssertEqual(GitLabClient.normalizeBase(" gitlab.example.com/ "), "https://gitlab.example.com")
        XCTAssertEqual(GitLabClient.normalizeBase("https://gitlab.example.com/api/v4"), "https://gitlab.example.com")
        XCTAssertEqual(GitLabClient.normalizeBase(""), "")
    }

    func testCurrentUserIsFetchedOncePerClient() async throws {
        net.reset { _ in .json(#"{"id": 7, "username": "me"}"#) }
        let client = Fixtures.client()
        let first = try await client.currentUser()
        let again = try await client.currentUser()
        XCTAssertEqual(first.username, "me")
        XCTAssertEqual(again.username, "me")
        XCTAssertEqual(net.requests.count, 1)
    }

    func testFailedCurrentUserLookupIsAskedAgain() async throws {
        let calls = Counter()
        net.reset { _ in calls.next() == 1 ? .json(#"{"message": "down"}"#, status: 503) : .json(#"{"id": 7, "username": "me"}"#) }
        let client = Fixtures.client()
        do { _ = try await client.currentUser(); XCTFail("expected throw") } catch {}
        let user = try await client.currentUser()
        XCTAssertEqual(user.username, "me")
        XCTAssertEqual(net.requests.count, 2)
    }

    func testVersionIsNilOnFailure() async {
        net.reset { _ in .json("{}", status: 500) }
        let v = await Fixtures.client().version()
        XCTAssertNil(v)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}

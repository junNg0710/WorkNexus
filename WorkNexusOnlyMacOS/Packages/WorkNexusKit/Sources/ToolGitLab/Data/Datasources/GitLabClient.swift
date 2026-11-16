import Foundation

/// Ported from: lib/tools/gitlab/data/datasources/gitlab_client.dart (+ lib/core/network/api_paging.dart)
/// HTTP transport for the GitLab REST v4 API, bound to one account's base URL + Personal Access Token.
/// The PAT is attached as `PRIVATE-TOKEN` — only for requests to the instance host, so it is never leaked to a
/// third-party host (e.g. an external image URL fetched by `fetchBytes`). List endpoints return a bare JSON
/// array; `paginate` walks pages via the `X-Next-Page` response header.
final class GitLabClient: Sendable {
    /// Items requested per page from list endpoints (`kDefaultApiPageLimit`).
    static let pageLimit = 500

    let baseUrl: String
    let token: String
    let host: String
    let transport: GitLabHTTPTransport
    private let apiBase: String
    private let userCache = GitLabCurrentUserCache()

    /// `session == nil` (production) accepts self-signed certificates for self-hosted instances but keeps normal
    /// validation for gitlab.com; tests inject a stubbed session.
    init(baseUrl: String, token: String, session: URLSession? = nil) {
        let normalized = Self.normalizeBase(baseUrl)
        self.baseUrl = normalized
        self.token = token
        self.host = (URL(string: normalized)?.host ?? "").lowercased()
        self.apiBase = "\(normalized)/api/v4"
        self.transport = GitLabHTTPTransport(session: session, trustsInsecure: { $0.lowercased() != "gitlab.com" })
    }

    static func normalizeBase(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return u }
        if !u.hasPrefix("http") { u = "https://\(u)" }
        if u.hasSuffix("/") { u.removeLast() }
        // Tolerate a pasted API base — keep the web root.
        if u.hasSuffix("/api/v4") { u.removeLast("/api/v4".count) }
        return u
    }

    // MARK: identity

    /// The token's user, asked once per client; a failed request is not kept.
    func currentUser() async throws -> GitLabUser {
        try await userCache.get { [self] in try await getObject("/user", as: GitLabUser.self) }
    }

    /// The instance version string (`GET /version`); nil on any failure.
    func version() async -> String? {
        struct Version: Decodable { var version: String? }
        return (try? await getObject("/version", as: Version.self))?.version
    }

    /// Resolves a username to a user (`GET /users?username=…`); nil when none matches.
    func userByUsername(_ username: String) async throws -> GitLabUser? {
        try await getList("/users", query: [("username", username)], as: GitLabUser.self, single: true).first
    }

    // MARK: assigned feed (global)

    func assignedIssues() async throws -> [GitLabIssue] {
        try await paginate("/issues", query: [("scope", "assigned_to_me"), ("state", "opened"), ("with_labels_details", "true")])
    }

    func assignedMergeRequests() async throws -> [GitLabMergeRequest] {
        try await paginate("/merge_requests", query: [("scope", "assigned_to_me"), ("state", "opened"), ("with_labels_details", "true")])
    }

    /// Review queue: `scope=reviews_for_me`, falling back to `reviewer_username` on instances without that scope.
    func reviewMergeRequests(username: String) async throws -> [GitLabMergeRequest] {
        do {
            return try await paginate("/merge_requests", query: [("scope", "reviews_for_me"), ("state", "opened"), ("with_labels_details", "true")])
        } catch let GitLabHTTPError.status(code, body) where Self.isUnsupportedReviewsScope(code, body) {
            return try await paginate("/merge_requests", query: [("reviewer_username", username), ("state", "opened"), ("with_labels_details", "true")])
        }
    }

    private static func isUnsupportedReviewsScope(_ code: Int, _ body: String) -> Bool {
        guard code == 400 else { return false }
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = obj["error"] as? String {
            return err.contains("scope")
        }
        return body.contains("scope does not have a valid value")
    }

    // MARK: projects + project-scoped items

    func projects() async throws -> [GitLabProject] {
        try await paginate("/projects", query: [("membership", "true"), ("order_by", "last_activity_at")])
    }

    func projectIssues(_ projectId: String, state: String? = nil, scope: String? = nil, assigneeUsername: String? = nil,
                       authorUsername: String? = nil, orderBy: String? = nil, sort: String? = nil,
                       maxPages: Int = 20) async throws -> [GitLabIssue] {
        var q: [(String, String)] = [("with_labels_details", "true")]
        q.appendIf("state", state); q.appendIf("scope", scope); q.appendIf("assignee_username", assigneeUsername)
        q.appendIf("author_username", authorUsername); q.appendIf("order_by", orderBy); q.appendIf("sort", sort)
        return try await paginate("/projects/\(projectId)/issues", query: q, maxPages: maxPages)
    }

    func projectMergeRequests(_ projectId: String, state: String? = nil, scope: String? = nil, assigneeUsername: String? = nil,
                              authorUsername: String? = nil, reviewerUsername: String? = nil, orderBy: String? = nil,
                              sort: String? = nil, maxPages: Int = 20) async throws -> [GitLabMergeRequest] {
        var q: [(String, String)] = [("with_labels_details", "true")]
        q.appendIf("state", state); q.appendIf("scope", scope); q.appendIf("assignee_username", assigneeUsername)
        q.appendIf("author_username", authorUsername); q.appendIf("reviewer_username", reviewerUsername)
        q.appendIf("order_by", orderBy); q.appendIf("sort", sort)
        return try await paginate("/projects/\(projectId)/merge_requests", query: q, maxPages: maxPages)
    }

    // MARK: single detail

    func issue(_ projectId: String, _ iid: String) async throws -> GitLabIssue {
        try await getObject("/projects/\(projectId)/issues/\(iid)", query: [("with_labels_details", "true")], as: GitLabIssue.self)
    }

    func mergeRequest(_ projectId: String, _ iid: String, includeRebaseInProgress: Bool = false) async throws -> GitLabMergeRequest {
        var q: [(String, String)] = [("with_labels_details", "true")]
        if includeRebaseInProgress { q.append(("include_rebase_in_progress", "true")) }
        return try await getObject("/projects/\(projectId)/merge_requests/\(iid)", query: q, as: GitLabMergeRequest.self)
    }

    // MARK: notes

    func issueNotes(_ projectId: String, _ iid: String) async throws -> [GitLabNote] {
        try await paginate("/projects/\(projectId)/issues/\(iid)/notes", query: [("sort", "asc"), ("order_by", "created_at")])
    }

    func mrNotes(_ projectId: String, _ iid: String) async throws -> [GitLabNote] {
        try await paginate("/projects/\(projectId)/merge_requests/\(iid)/notes", query: [("sort", "asc"), ("order_by", "created_at")])
    }

    func postIssueNote(_ projectId: String, _ iid: String, _ body: String) async throws -> GitLabNote {
        try await sendObject("POST", "/projects/\(projectId)/issues/\(iid)/notes", body: ["body": body], as: GitLabNote.self)
    }

    func postMrNote(_ projectId: String, _ iid: String, _ body: String) async throws -> GitLabNote {
        try await sendObject("POST", "/projects/\(projectId)/merge_requests/\(iid)/notes", body: ["body": body], as: GitLabNote.self)
    }

    // MARK: members, labels, milestones

    func members(_ projectId: String) async throws -> [GitLabUser] {
        try await paginate("/projects/\(projectId)/members/all")
    }

    func projectLabels(_ projectId: String) async throws -> [GitLabLabel] {
        try await paginate("/projects/\(projectId)/labels")
    }

    func projectMilestones(_ projectId: String) async throws -> [GitLabMilestone] {
        try await paginate("/projects/\(projectId)/milestones", query: [("state", "active"), ("include_parent_milestones", "true")])
    }

    // MARK: MR commits + diffs (detail view)

    func mergeRequestCommits(_ projectId: String, _ iid: String) async throws -> [GitLabCommitRow] {
        try await paginate("/projects/\(projectId)/merge_requests/\(iid)/commits", maxPages: 5)
    }

    func mergeRequestDiffs(_ projectId: String, _ iid: String) async throws -> [GitLabDiffRow] {
        try await paginate("/projects/\(projectId)/merge_requests/\(iid)/diffs", maxPages: 5)
    }

    // MARK: helpers

    /// Walks a paginated list endpoint via `X-Next-Page`. Stops when the header is empty or doesn't advance
    /// (defensive against a server that ignores `page`), capped at `maxPages`.
    func paginate<T: Decodable>(_ path: String, query: [(String, String)] = [], maxPages: Int = 20) async throws -> [T] {
        var out: [T] = []
        var page = 1
        for _ in 0..<maxPages {
            let q = [("per_page", "\(Self.pageLimit)"), ("page", "\(page)")] + query
            let res = try await transport.send(try request("GET", path, query: q))
            out.append(contentsOf: try Self.decodeList(res.data, as: T.self))
            guard let next = res.header("x-next-page").flatMap({ Int($0) }), next > page else { break }
            page = next
        }
        return out
    }

    func getList<T: Decodable>(_ path: String, query: [(String, String)] = [], as: T.Type, single: Bool = false) async throws -> [T] {
        let res = try await transport.send(try request("GET", path, query: query))
        return try Self.decodeList(res.data, as: T.self)
    }

    func getObject<T: Decodable>(_ path: String, query: [(String, String)] = [], as type: T.Type) async throws -> T {
        try Self.decodeObject(try await transport.send(try request("GET", path, query: query)).data, as: type)
    }

    func sendObject<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil, as type: T.Type) async throws -> T {
        try Self.decodeObject(try await transport.send(try request(method, path, body: body)).data, as: type)
    }

    /// Fire-and-forget mutation; the response body is ignored.
    func sendVoid(_ method: String, _ path: String, body: [String: Any]? = nil) async throws {
        _ = try await transport.send(try request(method, path, body: body))
    }

    func url(_ path: String, query: [(String, String)] = []) throws -> URL {
        guard var comps = URLComponents(string: apiBase) else { throw GitLabHTTPError.invalidURL(apiBase) }
        comps.percentEncodedPath += path   // `path` may carry an already-encoded project ref (`group%2Fweb`)
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let u = comps.url else { throw GitLabHTTPError.invalidURL(path) }
        return u
    }

    func request(_ method: String, _ path: String, query: [(String, String)] = [], body: [String: Any]? = nil) throws -> URLRequest {
        var req = URLRequest(url: try url(path, query: query))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        authorize(&req)
        return req
    }

    /// PAT only for instance-host requests — never for a third-party host.
    func authorize(_ req: inout URLRequest) {
        if req.url?.host?.lowercased() == host { req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN") }
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    static func decodeList<T: Decodable>(_ data: Data, as: T.Type) throws -> [T] {
        // A non-array body (e.g. an error object with a 200) yields an empty page, like the Dart client.
        guard let first = data.first(where: { !$0.isWhitespace }), first == UInt8(ascii: "[") else { return [] }
        return try decoder.decode([T].self, from: data)
    }

    static func decodeObject<T: Decodable>(_ data: Data, as: T.Type) throws -> T {
        guard let first = data.first(where: { !$0.isWhitespace }), first == UInt8(ascii: "{") else { throw GitLabHTTPError.notAnObject }
        return try decoder.decode(T.self, from: data)
    }
}

private extension UInt8 {
    var isWhitespace: Bool { self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09 }
}

extension Array where Element == (String, String) {
    mutating func appendIf(_ key: String, _ value: String?) { if let value { append((key, value)) } }
}

/// Caches the first `GET /user` per client (a failed request is not kept).
actor GitLabCurrentUserCache {
    private var task: Task<GitLabUser, Error>?
    func get(_ fetch: @escaping @Sendable () async throws -> GitLabUser) async throws -> GitLabUser {
        if let task { return try await task.value }
        let t = Task { try await fetch() }
        task = t
        do { return try await t.value } catch {
            if task == t { task = nil }
            throw error
        }
    }
}

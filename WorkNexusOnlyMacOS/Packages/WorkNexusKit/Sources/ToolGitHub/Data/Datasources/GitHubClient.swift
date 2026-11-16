import Foundation

/// Ported from: lib/tools/github/data/datasources/github_client.dart (+ lib/core/network/api_paging.dart)
/// HTTP transport for the GitHub REST API, bound to one account's base URL + Personal Access Token. The PAT is
/// attached as `Authorization: Bearer` (with the `Accept` + API-version headers) — but only for requests to the
/// API host (and, without the JSON headers, the web host for private inline assets), never to a third party.
///
/// github.com's API lives on `https://api.github.com`; GitHub Enterprise Server uses `https://<host>/api/v3`.
/// Lists are bare JSON arrays (Search wraps them in `{ items }`) and paginate through the RFC-5988 `Link`
/// response header (`rel="next"`).
final class GitHubClient: Sendable {
    /// Items requested per page from list endpoints (`kDefaultApiPageLimit`).
    static let pageLimit = 500
    static let apiVersion = "2022-11-28"

    /// The instance web root (`https://github.com` or the GHES root); asset URLs resolve against it.
    let webBase: String
    let apiBase: String
    let token: String
    let apiHost: String
    let webHost: String
    let transport: GitHubHTTPTransport

    /// `session == nil` (production) accepts self-signed certificates for GitHub Enterprise Server but keeps
    /// normal validation for github.com / api.github.com; tests inject a stubbed session.
    init(baseUrl: String, token: String, session: URLSession? = nil) {
        let r = Self.resolve(baseUrl)
        apiBase = r.apiBase; apiHost = r.host.lowercased(); webBase = r.webBase
        webHost = (URL(string: r.webBase)?.host ?? "").lowercased()
        self.token = token
        transport = GitHubHTTPTransport(session: session, trustsInsecure: {
            let h = $0.lowercased()
            return h != "github.com" && h != "api.github.com"
        })
    }

    /// Resolves a user-entered base URL into the API base, the API host and the web root. github.com →
    /// `api.github.com`; a self-hosted host → `<host>/api/v3`. (Deviation: a custom port is kept.)
    static func resolve(_ url: String) -> (apiBase: String, host: String, webBase: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { u = "https://github.com" }
        if !u.hasPrefix("http") { u = "https://\(u)" }
        if u.hasSuffix("/") { u.removeLast() }
        if u.hasSuffix("/api/v3") { u.removeLast("/api/v3".count) }   // tolerate a pasted API base
        let comps = URLComponents(string: u)
        let host = (comps?.host ?? "").lowercased()
        if host == "github.com" || host == "www.github.com" || host == "api.github.com" {
            return ("https://api.github.com", "api.github.com", "https://github.com")
        }
        let scheme = (comps?.scheme).flatMap { $0.isEmpty ? nil : $0 } ?? "https"
        let authority = (comps?.host ?? "") + (comps?.port.map { ":\($0)" } ?? "")
        return ("\(scheme)://\(authority)/api/v3", comps?.host ?? "", "\(scheme)://\(authority)")
    }

    // MARK: identity

    /// The authenticated user (`GET /user`) — verifies the token and resolves the account login.
    func currentUser() async throws -> GitHubUser { try await getObject("/user") }

    // MARK: assigned feed (global, via the Search API)

    func assignedIssues() async throws -> [GitHubIssue] { try await search("is:open is:issue assignee:@me") }
    func assignedPulls() async throws -> [GitHubIssue] { try await search("is:open is:pr assignee:@me") }
    func reviewPulls() async throws -> [GitHubIssue] { try await search("is:open is:pr review-requested:@me") }

    // MARK: repos + repo-scoped items

    func repos() async throws -> [GitHubRepo] {
        try await paginate("/user/repos", query: [("sort", "updated"), ("affiliation", "owner,collaborator,organization_member")])
    }

    func repoIssues(_ repo: String, state: String? = nil, sort: String? = nil, direction: String? = nil, maxPages: Int = 20) async throws -> [GitHubIssue] {
        try await paginate("/repos/\(repo)/issues", query: Self.listQuery(state, sort, direction), maxPages: maxPages)
    }

    func repoPulls(_ repo: String, state: String? = nil, sort: String? = nil, direction: String? = nil, maxPages: Int = 20) async throws -> [GitHubPull] {
        try await paginate("/repos/\(repo)/pulls", query: Self.listQuery(state, sort, direction), maxPages: maxPages)
    }

    private static func listQuery(_ state: String?, _ sort: String?, _ direction: String?) -> [(String, String)] {
        var q: [(String, String)] = []
        q.appendIf("state", state); q.appendIf("sort", sort); q.appendIf("direction", direction)
        return q
    }

    // MARK: single detail

    func issue(_ repo: String, _ number: String) async throws -> GitHubIssue { try await getObject("/repos/\(repo)/issues/\(number)") }
    func pull(_ repo: String, _ number: String) async throws -> GitHubPull { try await getObject("/repos/\(repo)/pulls/\(number)") }

    // MARK: comments + activity

    func issueComments(_ repo: String, _ number: String) async throws -> [GitHubComment] {
        try await paginate("/repos/\(repo)/issues/\(number)/comments")
    }

    func postIssueComment(_ repo: String, _ number: String, _ body: String) async throws -> GitHubComment {
        try await sendObject("POST", "/repos/\(repo)/issues/\(number)/comments", body: ["body": body])
    }

    func issueEvents(_ repo: String, _ number: String) async throws -> [GitHubEvent] {
        try await paginate("/repos/\(repo)/issues/\(number)/events")
    }

    // MARK: members (assignee picker)

    func assignees(_ repo: String) async throws -> [GitHubUser] { try await paginate("/repos/\(repo)/assignees") }

    // MARK: mutations

    /// Update an issue/PR (a PR is an issue): reassign and/or open/close via `PATCH /repos/:repo/issues/:number`.
    func updateIssue(_ repo: String, _ number: String, assignees: [String]? = nil, state: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let assignees { body["assignees"] = assignees }
        if let state { body["state"] = state }
        try await sendVoid("PATCH", "/repos/\(repo)/issues/\(number)", body: body)
    }

    func mergePull(_ repo: String, _ number: String, mergeMethod: String = "merge") async throws {
        try await sendVoid("PUT", "/repos/\(repo)/pulls/\(number)/merge", body: ["merge_method": mergeMethod])
    }

    /// GitHub's "Update branch" (the API has no rebase, it merges the base in). Resolves a `behind` state.
    func updateBranch(_ repo: String, _ number: String) async throws {
        try await sendVoid("PUT", "/repos/\(repo)/pulls/\(number)/update-branch")
    }

    /// Request `reviewers` (logins) on a PR. Additive — GitHub ignores logins that are already requested.
    func requestReviewers(_ repo: String, _ number: String, _ reviewers: [String]) async throws {
        try await sendVoid("POST", "/repos/\(repo)/pulls/\(number)/requested_reviewers", body: ["reviewers": reviewers])
    }

    // MARK: PR commits + files (detail view)

    func pullCommits(_ repo: String, _ number: String) async throws -> [GitHubCommitRow] {
        try await paginate("/repos/\(repo)/pulls/\(number)/commits", maxPages: 5)
    }

    func pullFiles(_ repo: String, _ number: String) async throws -> [GitHubFileRow] {
        try await paginate("/repos/\(repo)/pulls/\(number)/files", maxPages: 5)
    }

    // MARK: assets

    /// Fetches raw bytes for an authenticated asset (e.g. an inline image in an issue/PR body). `url` resolves
    /// against the instance web root; the PAT is attached only for instance hosts (a CDN image never gets it),
    /// and only an image response is accepted. Nil on any non-image response.
    func fetchBytes(_ url: String) async throws -> Data? {
        guard let base = URL(string: webBase + "/"),
              let resolved = (URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed).union(CharacterSet(charactersIn: "%#"))) ?? url))
                  .flatMap({ URL(string: $0.absoluteString, relativeTo: base)?.absoluteURL }) else { return nil }
        var req = URLRequest(url: resolved)
        authorize(&req)
        let res = try await transport.send(req, accept: { $0 < 500 })
        let type = (res.header("content-type") ?? "").lowercased()
        guard res.status == 200, !res.data.isEmpty, type.hasPrefix("image") else { return nil }
        return res.data
    }

    // MARK: helpers

    /// Walks a paginated list endpoint (bare JSON array) via the `Link` header's `rel="next"`, capped at `maxPages`.
    func paginate<T: Decodable>(_ path: String, query: [(String, String)] = [], maxPages: Int = 20) async throws -> [T] {
        var out: [T] = []
        var page = 1
        for _ in 0..<maxPages {
            let q = [("per_page", "\(Self.pageLimit)"), ("page", "\(page)")] + query
            let res = try await transport.send(try request("GET", path, query: q))
            out.append(contentsOf: try Self.decodeList(res.data, as: T.self))
            guard let next = Self.nextPage(res.header("link")), next > page else { break }
            page = next
        }
        return out
    }

    /// Walks the Search API (`/search/issues`, results in `{ items: [...] }`). Capped low — the assigned/review
    /// feeds are small and search is rate-limited.
    func search(_ q: String, maxPages: Int = 3) async throws -> [GitHubIssue] {
        var out: [GitHubIssue] = []
        var page = 1
        for _ in 0..<maxPages {
            let query = [("q", q), ("per_page", "\(Self.pageLimit)"), ("page", "\(page)")]
            let res = try await transport.send(try request("GET", "/search/issues", query: query))
            out.append(contentsOf: try Self.decodeObject(res.data, as: GitHubSearchResult<GitHubIssue>.self).items ?? [])
            guard let next = Self.nextPage(res.header("link")), next > page else { break }
            page = next
        }
        return out
    }

    /// Parses the `page` of the `rel="next"` link from an RFC-5988 `Link` header, e.g.
    /// `<https://api.github.com/…?page=2>; rel="next", <…?page=5>; rel="last"`.
    static func nextPage(_ link: String?) -> Int? {
        guard let link, !link.isEmpty,
              let re = try? NSRegularExpression(pattern: #"<([^>]*)>[^<]*?rel="next""#) else { return nil }
        let ns = link as NSString
        for m in re.matches(in: link, range: NSRange(location: 0, length: ns.length)) {
            let url = ns.substring(with: m.range(at: 1))
            if let page = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "page" })?.value, let n = Int(page) { return n }
        }
        return nil
    }

    func getObject<T: Decodable>(_ path: String, query: [(String, String)] = []) async throws -> T {
        try Self.decodeObject(try await transport.send(try request("GET", path, query: query)).data, as: T.self)
    }

    func sendObject<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        try Self.decodeObject(try await transport.send(try request(method, path, body: body)).data, as: T.self)
    }

    /// Fire-and-forget mutation; the response body is ignored.
    func sendVoid(_ method: String, _ path: String, body: [String: Any]? = nil) async throws {
        _ = try await transport.send(try request(method, path, body: body))
    }

    func url(_ path: String, query: [(String, String)] = []) throws -> URL {
        guard var comps = URLComponents(string: apiBase) else { throw GitHubHTTPError.invalidURL(apiBase) }
        comps.percentEncodedPath += path
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let u = comps.url else { throw GitHubHTTPError.invalidURL(path) }
        return u
    }

    func request(_ method: String, _ path: String, query: [(String, String)] = [], body: [String: Any]? = nil) throws -> URLRequest {
        var req = URLRequest(url: try url(path, query: query))
        req.httpMethod = method
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        authorize(&req)
        return req
    }

    /// PAT only for API-host requests (full GitHub headers) and the same-provider web host (token only, so
    /// private-repo `user-attachments/assets/…` authorize) — never for a third-party host.
    func authorize(_ req: inout URLRequest) {
        let host = req.url?.host?.lowercased()
        if host == apiHost {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        } else if host == webHost {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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
        guard let first = data.first(where: { !$0.isWhitespace }), first == UInt8(ascii: "{") else { throw GitHubHTTPError.notAnObject }
        return try decoder.decode(T.self, from: data)
    }
}

private extension UInt8 {
    var isWhitespace: Bool { self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09 }
}

extension Array where Element == (String, String) {
    mutating func appendIf(_ key: String, _ value: String?) { if let value { append((key, value)) } }
}

import CoreDomain
import Foundation

/// The classic `{root}/{module}-{method}-{args}.json?zentaosid=` channel of `ZenTaoClient`, for what REST v1
/// lacks. Ported from zentao_client.dart. The authenticated v1 token doubles as the `zentaosid` session id.
extension ZenTaoClient {
    // MARK: List views

    /// Bugs for a product via the classic `bug-browse-...json` action, which - unlike REST v1 - honours ZenTao's
    /// `browseType` tab views (`all` / `unclosed` / `openedbyme` / `assigntome` / `resolvedbyme` /
    /// `assignedbyme`). URL: `{base}/bug-browse-{productID}-0-{browseType}-0-{orderBy}-0-{recPerPage}-{pageID}.json`.
    func classicProductBugs(_ productId: String, browseType: String, recPerPage: Int = 500, pageID: Int = 1,
                            orderBy: String = "id_desc", cancel: CancelSignal? = nil) async throws -> ZenTaoProductBugsResponse {
        let token = try await ensureToken()
        let path = "bug-browse-\(productId)-0-\(browseType)-0-\(orderBy)-0-\(recPerPage)-\(pageID)"
        let target = try url("\(baseUrl)/\(path).json", query: [("zentaosid", token)])
        let res = try await run(cancel: cancel) { [self] in try await perform(ZenTaoRequest(url: target)) }
        return bugListView(res.data)
    }

    /// One page of execution `executionId`'s bugs, every product and status, via the classic
    /// `execution-bug-...json` action (REST v1 has no execution bug list). ZenTao 18.x signature:
    /// `{base}/execution-bug-{executionID}-{productID}-{branch}-{orderBy}-{build}-{type}-{param}-{recTotal}-{recPerPage}-{pageID}.json`.
    func classicExecutionBugs(_ executionId: String, recPerPage: Int, pageID: Int,
                              orderBy: String = "id_desc") async throws -> ZenTaoProductBugsResponse {
        let token = try await ensureToken()
        let path = "execution-bug-\(executionId)-0-all-\(orderBy)-0-all-0-0-\(recPerPage)-\(pageID)"
        let res = try await perform(ZenTaoRequest(url: try url("\(baseUrl)/\(path).json", query: [("zentaosid", token)])))
        return bugListView(res.data)
    }

    /// A classic bug-list view's bugs and total; empty when the reply holds no view.
    func bugListView(_ raw: Any?) -> ZenTaoProductBugsResponse {
        var data = raw
        if let s = data as? String {
            guard let decoded = try? jsonDecode(s) else { return ZenTaoProductBugsResponse(total: 0, bugs: []) }
            data = decoded
        }
        var payload: Any? = asMap(data).map { $0["data"].flatMap { isNull($0) ? nil : $0 } ?? data }
        if let s = payload as? String { payload = try? jsonDecode(s) }
        guard let map = asMap(payload) else { return ZenTaoProductBugsResponse(total: 0, bugs: []) }
        let bugs = listOrMapValues(map["bugs"]).compactMap { asMap($0).map(ZenTaoEntity.init(json:)) }
        let total = asMap(map["pager"]).map { zentaoInt($0["recTotal"]) ?? bugs.count } ?? bugs.count
        return ZenTaoProductBugsResponse(total: total, bugs: bugs)
    }

    /// One page of an execution's tasks, whoever they are assigned to, via the classic
    /// `execution-task-...json` action - unlike REST v1 it honours a status view `browseType`
    /// (`wait` / `doing` / `pause` / `done` / `closed` / `cancel` / `all` / ...). URL:
    /// `{base}/execution-task-{executionID}-{browseType}-0-{orderBy}-0-{recPerPage}-{pageID}.json`.
    func classicExecutionTasks(_ executionId: String, browseType: String, recPerPage: Int, pageID: Int,
                               orderBy: String = "id_desc", cancel: CancelSignal? = nil) async throws -> ZenTaoExecutionTasksResponse {
        let token = try await ensureToken()
        let path = "execution-task-\(executionId)-\(browseType)-0-\(orderBy)-0-\(recPerPage)-\(pageID)"
        let target = try url("\(baseUrl)/\(path).json", query: [("zentaosid", token)])
        let res = try await run(cancel: cancel) { [self] in try await perform(ZenTaoRequest(url: target)) }
        let payload = classicView(res)
        // The view always sends `tasks`, even empty. A reply without it is a refusal - 18.x answers an expired
        // session with `{locate: user-login}` - and read as an empty view it would hide the column's cached tasks.
        guard let payload, payload["tasks"] != nil else {
            throw ZenTaoError.http(status: res.status, message: "ZenTao task view reply had no task list", hasResponse: true)
        }
        return ZenTaoExecutionTasksResponse(classicView: payload)
    }

    // MARK: Messages

    /// The user's web notifications (the bell menu), via the classic `message-ajaxGetDropmenu-all` page - REST
    /// v1 has no message endpoint. The reply's `data` is the page's view, carrying `allMessages` (by day).
    func messages() async throws -> JSON {
        guard let payload = classicView(try await messageGet("ajaxGetDropmenu-all")), payload["allMessages"] != nil else {
            throw ZenTaoError.http(status: nil, message: "ZenTao messages reply had no message list", hasResponse: false)
        }
        return payload
    }

    /// Runs a classic message action, e.g. `ajaxMarkRead-all` or `ajaxDelete-12`. They answer with an empty body.
    func messageAction(_ action: String) async throws {
        let res = try await messageGet(action)
        if res.status != 200 {
            throw ZenTaoError.http(status: res.status, message: "ZenTao message action failed", hasResponse: true)
        }
    }

    private func messageGet(_ action: String) async throws -> ZenTaoResponse {
        let token = try await ensureToken()
        return try await perform(ZenTaoRequest(
            url: try url("\(baseUrl)/message-\(action).json", query: [("zentaosid", token)]),
            headers: ["Cookie": "zentaosid=\(token)"]))
    }

    // MARK: Payload helpers

    /// The view map of a classic `{status, data}` reply, whose `data` is itself JSON-encoded; nil when the
    /// reply is not that (e.g. a login page).
    func classicView(_ res: ZenTaoResponse) -> JSON? { asMap(classicPayloadObject(res.data)) }

    /// A classic page's payload: its `data` (JSON in a JSON string, sometimes twice over) decoded; nil when it
    /// isn't JSON (a login redirect).
    func classicPayloadObject(_ raw: Any?) -> Any? {
        var body = raw
        var n = 0
        while n < 2, let s = body as? String {
            guard let decoded = try? jsonDecode(s) else { return nil }
            body = decoded
            n += 1
        }
        var data: Any? = body
        if let m = asMap(body) { data = isNull(m["data"]) ? body : m["data"] }
        guard let s = data as? String else { return data }
        return try? jsonDecode(s)
    }

    /// A classic `{path}.json` page's payload (a map or a list), for what REST v1 lacks - e.g. a document's history.
    func getClassicJson(_ path: String) async throws -> Any? {
        let token = try await ensureToken()
        let res = try await perform(ZenTaoRequest(url: try url("\(baseUrl)/\(path).json", query: [("zentaosid", token)])))
        return classicPayloadObject(res.data)
    }

    // MARK: Classic POST / GET

    /// POSTs to a classic ZenTao action, e.g. `action-comment-bug-4302`, at `{base}/{actionPath}.json?zentaosid={token}`
    /// with a form-urlencoded body. ZenTao guards state-changing POSTs with a CSRF check that requires the
    /// `Origin`/`Referer` host to match the site - GET reads are exempt, which is why reads worked while every
    /// write silently bounced to the login page. We present the site as origin (as the web client does) and
    /// include a form `uid` (namespaces any inline uploads; the web always sends one).
    func classicActionPost(_ actionPath: String, _ form: ZenTaoForm) async throws -> ZenTaoResponse {
        var withUid = ZenTaoForm()
        withUid.put("uid", formUid())
        withUid.merge(form)
        return try await classicPost(actionPath, .form(withUid))
    }

    /// POSTs `body` - a field map (form-urlencoded; list values are sent as repeated `key=` pairs, so name array
    /// fields `key[]`) or multipart (files) - to classic action `actionPath`.
    func classicPost(_ actionPath: String, _ body: ZenTaoBody) async throws -> ZenTaoResponse {
        let token = try await ensureToken()
        return try await perform(ZenTaoRequest(
            method: "POST",
            url: try url("\(baseUrl)/\(actionPath).json", query: [("zentaosid", token)]),
            headers: classicHeaders(token),
            body: body))
    }

    /// GETs classic page `path` as JSON (`{base}/{path}.json`).
    func classicGet(_ path: String) async throws -> ZenTaoResponse {
        let token = try await ensureToken()
        return try await perform(ZenTaoRequest(
            url: try url("\(baseUrl)/\(path).json", query: [("zentaosid", token)]),
            headers: classicHeaders(token)))
    }

    func classicHeaders(_ token: String) -> [String: String] {
        [
            "Cookie": "zentaosid=\(token)",
            "Token": token,
            "Origin": Self.origin(of: baseUrl),
            "Referer": "\(baseUrl)/index.html",
            "X-Requested-With": "XMLHttpRequest",
        ]
    }

    /// Dart `Uri.origin`: scheme, host and a non-default port.
    static func origin(of base: String) -> String {
        guard let u = URL(string: base), let scheme = u.scheme, let host = u.host else { return base }
        if let port = u.port, !(scheme == "http" && port == 80), !(scheme == "https" && port == 443) {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    // MARK: Detail fallback

    /// Classic detail JSON: `GET {base}/{type}-view-{id}.json`. Used as a fallback when the REST v1 detail
    /// endpoint returns an empty body (older installs / permission quirks). The payload is `{status, data}`
    /// where `data` (sometimes a JSON string) holds `{ <type>:{...}, actions:{...|[...]}, users:{...} }`.
    /// Returns the entity map with an embedded `actions` field, or nil.
    func classicViewJson(_ type: String, _ id: String) async throws -> JSON? {
        let token = try await ensureToken()
        let res = try await perform(ZenTaoRequest(url: try url("\(baseUrl)/\(type)-view-\(id).json", query: [("zentaosid", token)])))
        var data = res.data
        if let s = data as? String {
            guard let decoded = try? jsonDecode(s) else { return nil }
            data = decoded
        }
        guard let map = asMap(data) else { return nil }
        if let status = str(map["status"]), status != "success" { return nil }
        var payload: Any? = isNull(map["data"]) ? data : map["data"]
        if let s = payload as? String {
            guard let decoded = try? jsonDecode(s) else { return nil }
            payload = decoded
        }
        guard let p = asMap(payload) else { return nil }
        var result = asMap(p[type]) ?? [:]
        if isNull(result["actions"]), !isNull(p["actions"]) { result["actions"] = p["actions"] }
        return result.isEmpty ? nil : result
    }
}

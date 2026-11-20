import CoreDomain
import Foundation

/// REST v1 endpoints (`{root}/api.php/v1`) of `ZenTaoClient`. Ported from zentao_client.dart / zentao_api.dart.
extension ZenTaoClient {
    private func getV1(_ path: String, query: [(String, String)] = []) async throws -> ZenTaoResponse {
        try await perform(ZenTaoRequest(url: try url("\(v1)\(path)", query: query)))
    }

    /// "Assigned to me" for one kind (`fields` = bug|task|story), one page (`GET /user`).
    func assigned(type: String, fields: String, page: Int, limit: Int) async throws -> ZenTaoAssignedResponse {
        let res = try await getV1("/user", query: [("type", type), ("fields", fields), ("page", "\(page)"), ("limit", "\(limit)")])
        return ZenTaoAssignedResponse(json: try responseMap(res.data))
    }

    /// Users the current account may assign to (`GET /users`); `page` (1-based) reads past the first `limit`.
    func users(limit: Int, page: Int? = nil) async throws -> ZenTaoUsersResponse {
        var query = [("limit", "\(limit)")]
        if let page { query.append(("page", "\(page)")) }
        let res = try await getV1("/users", query: query)
        return ZenTaoUsersResponse(json: try responseMap(res.data))
    }

    /// The signed-in user's profile (`GET /user`), plus the "my work" blocks named in `fields`
    /// (`?fields=task,bug,...`), each list capped at `limit` items. Kept as a raw map: the shape varies by
    /// block and server version, so callers parse it leniently.
    func userInfo(fields: String? = nil, limit: Int? = nil) async throws -> JSON {
        var query: [(String, String)] = []
        if let fields { query.append(("fields", fields)) }
        if let limit { query.append(("limit", "\(limit)")) }
        let res = try await getV1("/user", query: query)
        try ensureOk(res)
        return try responseMap(res.data)
    }

    /// A REST v1 GET at `path` (e.g. `/doclibs`), answered as a JSON object.
    func getV1Json(_ path: String, query: [(String, String)] = []) async throws -> JSON {
        let res = try await getV1(path, query: query)
        try ensureOk(res)
        return try responseMap(res.data)
    }

    /// Every department as one flat list. Some servers send a flat list (each with its `parent`); others a tree whose
    /// departments carry their sub-departments in `items` (ZenTao's own `GET /departments`: "VN" holds "Flutter VN"…) or
    /// `children`, or a map keyed by id: those are flattened too, a child taking the department it sits in as its parent
    /// when it does not say.
    func departments() async throws -> [JSON] {
        let res = try await getV1("/departments")
        try ensureOk(res)
        var decoded = res.data
        if let s = decoded as? String { decoded = try jsonDecode(s) }
        let items: Any? = (decoded as? [Any]) ?? asMap(decoded)?["departments"] ?? asMap(decoded).map { Array($0.values) }
        guard let list = items as? [Any] ?? asMap(items).map({ Array($0.values) }) else {
            throw ZenTaoError.format("ZenTao departments response is not a list")
        }
        return Self.flattenDepartments(list, parent: nil)
    }

    static func flattenDepartments(_ items: [Any], parent: Any?) -> [JSON] {
        var out: [JSON] = []
        for raw in items {
            guard var d = asMap(raw) else { continue }
            var children: [Any] = []
            for key in ["items", "children"] {
                children += (d[key] as? [Any]) ?? asMap(d[key]).map { Array($0.values) } ?? []
                d[key] = nil
            }
            if let parent, (zentaoInt(d["parent"]) ?? 0) == 0 { d["parent"] = parent }
            out.append(d)
            out += flattenDepartments(children, parent: d["id"])
        }
        return out
    }

    /// Every user the account may see, page by page. A server may cap a page below `pageSize`, so reading goes on until
    /// the total it gives is reached or a page brings nobody new (a page past the end repeats the first, or is empty);
    /// `until` stops it as soon as one user read matches.
    func allUsers(pageSize: Int = 1000, maxPages: Int = 50, until: ((ZenTaoUser) -> Bool)? = nil) async throws -> [ZenTaoUser] {
        var out: [ZenTaoUser] = []
        var seen: Set<String> = []
        for page in 1...maxPages {
            let res = try await users(limit: pageSize, page: page)
            let fresh = res.users.filter { seen.insert($0.account ?? $0.id ?? "").inserted }
            out += fresh
            if fresh.isEmpty || fresh.contains(where: { until?($0) ?? false }) { break }
            if let total = res.total, out.count >= total { break }
        }
        return out
    }

    /// Updates the signed-in user through ZenTao REST v1 (`PUT /users/{id}`).
    func updateUser(_ userId: Int, fields: JSON) async throws -> JSON {
        let body = try JSONSerialization.data(withJSONObject: fields)
        let res = try await perform(ZenTaoRequest(method: "PUT", url: try url("\(v1)/users/\(userId)"), body: .json(body)))
        try ensureOk(res)
        let updated = try responseMap(res.data)
        if str(updated["status"]) == "fail" || str(updated["result"]) == "fail" {
            throw ZenTaoError.http(status: res.status, message: str(updated["message"]) ?? "ZenTao rejected profile update", hasResponse: true)
        }
        return updated
    }

    /// Makes a todo of the signed-in user (`POST /todos`); the new todo's id when the reply names it. ZenTao answers a
    /// refusal as an HTTP error with `error`, or as `result: fail` with `message` (a string, or the fields at fault).
    func createTodo(fields: JSON) async throws -> Int? {
        let body = try JSONSerialization.data(withJSONObject: fields)
        let res = try await perform(ZenTaoRequest(method: "POST", url: try url("\(v1)/todos"), body: .json(body)))
        let reply = (try? responseMap(res.data)) ?? [:]
        let refused = str(reply["status"]) == "fail" || str(reply["result"]) == "fail" || reply["error"] != nil
        if res.status >= 400 || refused {
            let said = reply["error"] ?? reply["message"]
            let message = str(said) ?? said.flatMap { $0 is NSNull ? nil : jsonEncode($0) } ?? "HTTP \(res.status)"
            throw ZenTaoError.http(status: res.status, message: message, hasResponse: true)
        }
        return zentaoInt(reply["id"]).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Product list used by the ZenTao Sources tab. `merged` asks for ZenTao's program > line > product tree.
    func products(page: Int, limit: Int, merged: Bool = false) async throws -> ZenTaoProductsResponse {
        var q: [(String, String)] = [("page", "\(page)"), ("limit", "\(limit)")]
        if merged { q.append(("mergeChildren", "1")) }
        return ZenTaoProductsResponse(json: try responseMap(try await getV1("/products", query: q).data))
    }

    /// All bugs for a product via REST v1 `GET /products/{id}/bugs`. This endpoint does NOT honour ZenTao's
    /// `browseType` tab views (it always returns every bug) - use `classicProductBugs` for the tab slices.
    func productBugs(_ productId: String, page: Int, limit: Int) async throws -> ZenTaoProductBugsResponse {
        let res = try await getV1("/products/\(productId)/bugs", query: [("page", "\(page)"), ("limit", "\(limit)")])
        return ZenTaoProductBugsResponse(json: try responseMap(res.data))
    }

    /// Projects for this account (`GET /projects`), used to group executions.
    func projects(page: Int, limit: Int) async throws -> ZenTaoProjectsResponse {
        let res = try await getV1("/projects", query: [("page", "\(page)"), ("limit", "\(limit)")])
        return ZenTaoProjectsResponse(json: try responseMap(res.data))
    }

    /// The account's programs (`GET /programs`), to name projects' programs.
    func programs(page: Int, limit: Int) async throws -> ZenTaoProgramsResponse {
        let res = try await getV1("/programs", query: [("page", "\(page)"), ("limit", "\(limit)")])
        return ZenTaoProgramsResponse(json: try responseMap(res.data))
    }

    /// Full detail for one entity, e.g. `GET /bugs/4302`. Empty (no id) when the reply holds no object: ZenTao
    /// answers some items with an empty 200, and the caller then reads the classic page instead.
    func entity(_ type: String, _ id: String) async throws -> ZenTaoEntity {
        let res = try await getV1("/\(type)/\(id)")
        var data = res.data
        if let s = data as? String {
            guard let decoded = try? jsonDecode(s) else { return ZenTaoEntity() }
            data = decoded
        }
        return asMap(data).map(ZenTaoEntity.init(json:)) ?? ZenTaoEntity()
    }

    /// The ids of the products execution `executionId` is linked to (`GET /executions/{id}`, `products`).
    func executionProducts(_ executionId: String) async throws -> [String] {
        let res = try await getV1("/executions/\(executionId)")
        guard let products = try responseMap(res.data)["products"] as? [Any] else { return [] }
        return products.compactMap { asMap($0) }.compactMap { zentaoInt($0["id"]) }.filter { $0 > 0 }.map(String.init)
    }

    /// Executions of a project (`GET /projects/{id}/executions`).
    func projectExecutions(_ projectId: String, page: Int, limit: Int) async throws -> ZenTaoExecutionsResponse {
        let res = try await getV1("/projects/\(projectId)/executions", query: [("page", "\(page)"), ("limit", "\(limit)")])
        return ZenTaoExecutionsResponse(json: try responseMap(res.data))
    }
}

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

    /// Users the current account may assign to (`GET /users`).
    func users(limit: Int) async throws -> ZenTaoUsersResponse {
        let res = try await getV1("/users", query: [("limit", "\(limit)")])
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

    func departments() async throws -> [JSON] {
        let res = try await getV1("/departments")
        try ensureOk(res)
        var decoded = res.data
        if let s = decoded as? String { decoded = try jsonDecode(s) }
        let items: Any? = (decoded as? [Any]) ?? asMap(decoded)?["departments"]
        guard let list = items as? [Any] else { throw ZenTaoError.format("ZenTao departments response is not a list") }
        return list.compactMap(asMap)
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

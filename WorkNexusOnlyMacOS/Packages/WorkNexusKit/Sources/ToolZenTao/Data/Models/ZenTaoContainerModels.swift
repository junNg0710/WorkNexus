import Foundation

// Ported from: lib/tools/zentao/data/models/zentao_container_models.dart
// DTOs for the containers ZenTao files work under - products, projects and their programs.

/// A program or product-line node of ZenTao's product tree: id and name.
struct ZenTaoProductNode { var id: String; var name: String }

struct ZenTaoProduct {
    var id: String
    var name: String
    var programId: String?
    var programName: String?
    var lineId: String?
    var lineName: String?

    init(json: JSON, program: ZenTaoProductNode? = nil, line: ZenTaoProductNode? = nil) {
        id = str(json["id"]) ?? ""
        name = str(json["name"]) ?? id
        programId = program?.id; programName = program?.name; lineId = line?.id; lineName = line?.name
    }
}

/// `GET /products` -> `{ total, products: [...] }`. With `mergeChildren=1` the list is ZenTao's tree instead:
/// program nodes (`type: "program"`) holding products and product-line nodes (`type: "line"`); anything else is
/// a product. Read in ZenTao's order, flat, each product carrying its program and line.
struct ZenTaoProductsResponse {
    var total: Int
    var products: [ZenTaoProduct]

    init(json: JSON) {
        var out: [ZenTaoProduct] = []
        func walk(_ nodes: Any?, program: ZenTaoProductNode? = nil, line: ZenTaoProductNode? = nil) {
            for raw in listOrMapValues(nodes) {
                guard let node = asMap(raw) else { continue }
                let kind = str(node["type"])
                let me = ZenTaoProductNode(id: str(node["id"]) ?? "", name: str(node["name"]) ?? "")
                if kind == "program" {
                    walk(node["children"], program: me)           // a sub-program files its products under itself
                } else if kind == "line" {
                    walk(node["children"], program: program, line: me)
                } else {
                    out.append(ZenTaoProduct(json: node, program: program, line: line))
                }
            }
        }
        walk(json["products"])
        products = out
        total = zentaoInt(json["total"]) ?? 0
    }
}

struct ZenTaoProject {
    var id: String
    var name: String
    var programId: String?
    var programName: String?

    /// A project's program is its `parent` (`GET /projects` sends the rows as they are); `program` where a
    /// server sends one. The name comes from `/programs` unless the row carries `programName`.
    init(json: JSON) {
        id = str(json["id"]) ?? ""
        name = str(isNull(json["name"]) ? json["title"] : json["name"]) ?? id
        func idOf(_ raw: Any?) -> String? {
            guard let v = str(raw)?.trimmingCharacters(in: .whitespaces), !v.isEmpty, v != "0" else { return nil }
            return v
        }
        programId = idOf(json["parent"]) ?? idOf(json["program"])
        if let n = str(json["programName"])?.trimmingCharacters(in: .whitespaces), !n.isEmpty { programName = n }
    }
}

struct ZenTaoProjectsResponse {
    var total: Int
    var projects: [ZenTaoProject]
    init(json: JSON) {
        total = zentaoInt(json["total"]) ?? 0
        projects = (json["projects"] as? [Any] ?? []).compactMap { asMap($0).map(ZenTaoProject.init(json:)) }
    }
}

/// `GET /programs` -> program names by id, in ZenTao's order (sub-programs in `children` included).
struct ZenTaoProgramsResponse {
    var total: Int
    var names: [(id: String, name: String)]
    init(json: JSON) {
        var out: [(String, String)] = []
        func walk(_ nodes: Any?) {
            for raw in listOrMapValues(nodes) {
                guard let m = asMap(raw) else { continue }
                let id = str(m["id"]) ?? ""
                let name = str(m["name"])?.trimmingCharacters(in: .whitespaces) ?? ""
                if !id.isEmpty, !name.isEmpty, !out.contains(where: { $0.0 == id }) { out.append((id, name)) }
                walk(m["children"])
            }
        }
        walk(json["programs"])
        names = out
        total = zentaoInt(json["total"]) ?? 0
    }
}

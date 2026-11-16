import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/entities/{zentao_product_group,zentao_project_group}.dart
/// A folder of the ZenTao products tree: a program (with its product lines as sub-folders) or a product line.
public struct ZenTaoProductGroup: Sendable {
    /// `program:<id>` or `line:<id>`.
    public var id: String
    public var name: String
    public var products: [ProviderProduct]
    public var lines: [ZenTaoProductGroup]
    public init(id: String, name: String, products: [ProviderProduct], lines: [ZenTaoProductGroup] = []) {
        self.id = id; self.name = name; self.products = products; self.lines = lines
    }
    /// Every product in the folder, its lines' included.
    public var allProducts: [ProviderProduct] { lines.flatMap(\.allProducts) + products }
}

private func byName<T>(_ items: [T], _ name: (T) -> String) -> [T] {
    items.sorted { name($0).lowercased() < name($1).lowercased() }
}

/// The products as ZenTao groups them: `groups` in ZenTao's order, then the products in no program or line.
public struct ZenTaoProductTree: Sendable {
    public var groups: [ZenTaoProductGroup]
    public var ungrouped: [ProviderProduct]
    public init(groups: [ZenTaoProductGroup], ungrouped: [ProviderProduct]) { self.groups = groups; self.ungrouped = ungrouped }

    private final class Folder {
        let id: String, name: String
        var products: [ProviderProduct] = []
        var lines: [String: Folder] = [:]
        var lineOrder: [String] = []
        init(_ id: String, _ name: String) { self.id = id; self.name = name }
        func toGroup() -> ZenTaoProductGroup {
            ZenTaoProductGroup(id: id, name: name, products: products, lines: lineOrder.compactMap { lines[$0]?.toGroup() })
        }
    }

    /// Builds the tree from `products` in the order ZenTao listed them. When none carries a program or line they
    /// stay one flat list, sorted by name: no folder is ever made up.
    public static func of(_ products: [ProviderProduct]) -> ZenTaoProductTree {
        if !products.contains(where: { $0.programId != nil || $0.lineId != nil }) {
            return ZenTaoProductTree(groups: [], ungrouped: byName(products) { $0.name })
        }
        var folders: [String: Folder] = [:]
        var order: [String] = []
        var ungrouped: [ProviderProduct] = []
        func folder(_ key: String, _ name: String) -> Folder {
            if let f = folders[key] { return f }
            let f = Folder(key, name); folders[key] = f; order.append(key); return f
        }
        for p in products {
            if let programId = p.programId {
                let program = folder("program:\(programId)", p.programName ?? programId)
                if let lineId = p.lineId {
                    let key = "line:\(lineId)"
                    if program.lines[key] == nil {
                        program.lines[key] = Folder(key, p.lineName ?? lineId); program.lineOrder.append(key)
                    }
                    program.lines[key]!.products.append(p)
                } else {
                    program.products.append(p)
                }
            } else if let lineId = p.lineId {
                folder("line:\(lineId)", p.lineName ?? lineId).products.append(p)
            } else {
                ungrouped.append(p)
            }
        }
        return ZenTaoProductTree(groups: order.compactMap { folders[$0]?.toGroup() }, ungrouped: byName(ungrouped) { $0.name })
    }
}

/// A program's folder of ZenTao projects.
public struct ZenTaoProjectGroup: Sendable {
    /// `program:<id>`.
    public var id: String
    public var name: String
    public var projects: [ProviderProject]
    public init(id: String, name: String, projects: [ProviderProject]) { self.id = id; self.name = name; self.projects = projects }
}

/// The projects as ZenTao groups them: `groups` by program, then the projects in no (named) program.
public struct ZenTaoProjectTree: Sendable {
    public var groups: [ZenTaoProjectGroup]
    public var ungrouped: [ProviderProject]
    public init(groups: [ZenTaoProjectGroup], ungrouped: [ProviderProject]) { self.groups = groups; self.ungrouped = ungrouped }

    public static func of(_ projects: [ProviderProject]) -> ZenTaoProjectTree {
        func hasProgram(_ p: ProviderProject) -> Bool { p.programId != nil && !(p.programName ?? "").isEmpty }
        if !projects.contains(where: hasProgram) {
            return ZenTaoProjectTree(groups: [], ungrouped: byName(projects) { $0.name })
        }
        var order: [String] = []
        var groups: [String: (name: String, list: [ProviderProject])] = [:]
        var ungrouped: [ProviderProject] = []
        for p in projects {
            if let id = p.programId, let name = p.programName, !name.isEmpty {
                let key = "program:\(id)"
                if groups[key] == nil { groups[key] = (name, []); order.append(key) }
                groups[key]!.list.append(p)
            } else {
                ungrouped.append(p)
            }
        }
        return ZenTaoProjectTree(
            groups: order.map { ZenTaoProjectGroup(id: $0, name: groups[$0]!.name, projects: groups[$0]!.list) },
            ungrouped: byName(ungrouped) { $0.name })
    }
}

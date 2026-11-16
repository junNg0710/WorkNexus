import CoreDomain
import Foundation

/// Ported from: lib/tools/gitlab/domain/entities/gitlab_project_tree.dart
/// Short project name: `icom / Server / storage` → `storage`.
public func gitlabShortProjectName(_ project: ProviderProject) -> String {
    let parts = project.name.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    return parts.last ?? project.name
}

/// A node in the GitLab group/subgroup tree.
public struct GitLabGroupNode: Sendable, Hashable, Identifiable {
    public var name: String
    /// Full path (e.g. `icom/Server/socialfi`).
    public var fullPath: String
    public var subgroups: [GitLabGroupNode]
    public var projects: [ProviderProject]
    public var id: String { fullPath }

    public init(name: String, fullPath: String, subgroups: [GitLabGroupNode] = [], projects: [ProviderProject] = []) {
        self.name = name; self.fullPath = fullPath; self.subgroups = subgroups; self.projects = projects
    }

    /// Recursively counts all projects inside this group and its subgroups.
    public var totalProjectCount: Int { projects.count + subgroups.reduce(0) { $0 + $1.totalProjectCount } }
}

/// The hierarchical project tree for a GitLab account.
public struct GitLabProjectTree: Sendable, Hashable {
    public var rootGroups: [GitLabGroupNode]
    public var rootProjects: [ProviderProject]

    public init(rootGroups: [GitLabGroupNode] = [], rootProjects: [ProviderProject] = []) {
        self.rootGroups = rootGroups; self.rootProjects = rootProjects
    }

    /// Builds the tree from `ProviderProject`s whose `name` is the namespaced `Group / Sub / Project`.
    public static func build(_ projects: [ProviderProject]) -> GitLabProjectTree {
        if projects.isEmpty { return GitLabProjectTree() }
        let root = Builder(name: "", fullPath: "")
        var rootProjects: [ProviderProject] = []
        for p in projects {
            let parts = p.name.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count <= 1 { rootProjects.append(p); continue }
            var current = root
            var path = ""
            for (i, token) in parts.dropLast().enumerated() {
                if i > 0 { path += "/" }
                path += token
                if let existing = current.subgroups[token] { current = existing }
                else {
                    let b = Builder(name: token, fullPath: path)
                    current.subgroups[token] = b
                    current = b
                }
            }
            current.projects.append(p)
        }
        return GitLabProjectTree(
            rootGroups: root.sortedSubgroups(),
            rootProjects: rootProjects.sorted { $0.name.lowercased() < $1.name.lowercased() }
        )
    }

    private final class Builder {
        let name: String, fullPath: String
        var subgroups: [String: Builder] = [:]
        var projects: [ProviderProject] = []
        init(name: String, fullPath: String) { self.name = name; self.fullPath = fullPath }

        func sortedSubgroups() -> [GitLabGroupNode] {
            subgroups.values.map { $0.node() }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
        func node() -> GitLabGroupNode {
            GitLabGroupNode(name: name, fullPath: fullPath, subgroups: sortedSubgroups(),
                            projects: projects.sorted { $0.name.lowercased() < $1.name.lowercased() })
        }
    }
}

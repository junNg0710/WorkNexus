/// Ported from: lib/tools/zentao/domain/usecases/build_subtask_tree.dart
import CoreDomain
import Foundation

/// One subtask in its family tree: the `subtask` and its own `children`, in the order ZenTao listed them.
public struct SubtaskNode: Hashable, Sendable {
    public let subtask: TicketSubtask
    public let children: [SubtaskNode]
    public init(subtask: TicketSubtask, children: [SubtaskNode] = []) { self.subtask = subtask; self.children = children }

    public var hasChildren: Bool { !children.isEmpty }
}

/// One row of the subtask list as it shows now: the node and how many levels below the open task it sits.
public struct SubtaskRowItem: Hashable, Sendable {
    public let node: SubtaskNode
    public let depth: Int
}

/// A task's subtasks as a tree: its direct subtasks (`roots`), each holding its own, and how many subtasks there are at
/// every level (`total`).
public struct SubtaskTree: Hashable, Sendable {
    public let roots: [SubtaskNode]
    public let total: Int
    public init(roots: [SubtaskNode], total: Int) { self.roots = roots; self.total = total }

    /// Whether any direct subtask has subtasks of its own.
    public var isNested: Bool { roots.contains { $0.hasChildren } }

    /// The rows showing now, depth first: a subtask's own subtasks follow it only while it is in `expanded`.
    /// (Dart: `_SubtaskListState._visible`.)
    public func visible(expanded: Set<String>) -> [SubtaskRowItem] {
        var rows: [SubtaskRowItem] = []
        func walk(_ nodes: [SubtaskNode], _ depth: Int) {
            for n in nodes {
                rows.append(SubtaskRowItem(node: n, depth: depth))
                if expanded.contains(n.subtask.id) { walk(n.children, depth + 1) }
            }
        }
        walk(roots, 0)
        return rows
    }
}

/// Input for `BuildSubtaskTree`: the open task's `parentId` and the `subtasks` ZenTao listed on it (every descendant,
/// flat).
public struct SubtaskTreeInput: Sendable {
    public let parentId: String
    public let subtasks: [TicketSubtask]
    public init(parentId: String, subtasks: [TicketSubtask]) { self.parentId = parentId; self.subtasks = subtasks }
}

/// Nests a task's flat subtask list by each subtask's parent. A subtask whose parent is the task itself, unknown, or not
/// in the list is a direct subtask, so nothing ZenTao listed ever goes missing - including subtasks whose parents loop
/// back on each other, which join the direct ones.
public struct BuildSubtaskTree: Sendable {
    public init() {}

    public func callAsFunction(_ input: SubtaskTreeInput) -> SubtaskTree {
        let subtasks = input.subtasks
        let ids = Set(subtasks.map(\.id))
        var childrenOf: [String: [TicketSubtask]] = [:]
        var roots: [TicketSubtask] = []
        for s in subtasks {
            if let parent = s.parentId, parent != input.parentId, parent != s.id, ids.contains(parent) {
                childrenOf[parent, default: []].append(s)
            } else {
                roots.append(s)
            }
        }

        var placed = Set<String>()
        func build(_ s: TicketSubtask) -> SubtaskNode {
            placed.insert(s.id)
            var children: [SubtaskNode] = []
            for child in childrenOf[s.id] ?? [] where !placed.contains(child.id) { children.append(build(child)) }
            return SubtaskNode(subtask: s, children: children)
        }

        var nodes = roots.map(build)
        // A parent loop never reaches a root; surface its members as direct subtasks rather than dropping them.
        for s in subtasks where !placed.contains(s.id) { nodes.append(build(s)) }
        return SubtaskTree(roots: nodes, total: subtasks.count)
    }
}

import CoreDomain

/// Ported from: lib/shared/board/domain/usecases/derive_board_facets.dart
public enum BoardFacetScope: Sendable { case bug, task, gitlabMergeRequest, none }

public enum BoardFacetKind: String, CaseIterable, Sendable {
    case status, assignee, resolvedBy, openedBy, confirmed, reviewer, severity, priority, bugType, resolution, module
}

public struct BoardFacetOption: Hashable, Sendable {
    public var value: String
    public var count: Int
    public var label: String?
    public init(value: String, count: Int, label: String? = nil) { self.value = value; self.count = count; self.label = label }
}

/// A value a tool knows is valid for a facet (listed even when no loaded ticket has it).
public struct BoardFacetChoice: Hashable, Sendable {
    public var value: String
    public var label: String?
    public init(_ value: String, label: String? = nil) { self.value = value; self.label = label }
}

public struct BoardFacetCatalog: Sendable {
    public var choices: [BoardFacetKind: [BoardFacetChoice]]
    public init(_ choices: [BoardFacetKind: [BoardFacetChoice]]) { self.choices = choices }
}

public struct BoardFacetGroup: Hashable, Sendable {
    public var kind: BoardFacetKind
    public var options: [BoardFacetOption]
    public init(kind: BoardFacetKind, options: [BoardFacetOption]) { self.kind = kind; self.options = options }
}

public struct BoardFacets: Hashable, Sendable {
    public var groups: [BoardFacetGroup]
    public init(groups: [BoardFacetGroup]) { self.groups = groups }
    public static let empty = BoardFacets(groups: [])
}

public struct BoardFacetsInput: Sendable {
    public var tickets: [Ticket]
    public var scope: BoardFacetScope
    public var catalog: BoardFacetCatalog?
    public init(tickets: [Ticket], scope: BoardFacetScope, catalog: BoardFacetCatalog? = nil) {
        self.tickets = tickets; self.scope = scope; self.catalog = catalog
    }
}

/// Derives the filter facet groups (with counts) a board offers from the tickets it holds.
public struct DeriveBoardFacets: Sendable {
    public init() {}

    public func callAsFunction(_ input: BoardFacetsInput) -> BoardFacets {
        let kinds: [BoardFacetKind]
        switch input.scope {
        case .none: return .empty
        case .bug: kinds = [.module, .assignee, .resolvedBy, .openedBy, .status, .severity, .priority, .bugType, .resolution, .confirmed]
        case .task: kinds = [.module, .assignee, .status, .priority]
        case .gitlabMergeRequest: kinds = [.assignee, .reviewer, .priority]
        }
        var groups: [BoardFacetGroup] = []
        for kind in kinds {
            var counts: [String: Int] = [:]
            var firstSeen: [String] = []
            for t in input.tickets {
                for v in valuesFor(kind, t) {
                    if counts[v] == nil { firstSeen.append(v) }
                    counts[v, default: 0] += 1
                }
            }
            let known = input.catalog?.choices[kind]
            if known == nil && kind == .module { continue }
            if known == nil && counts.count < 2 { continue }
            var derived = firstSeen.filter { v in known == nil || !known!.contains { $0.value == v } }
                .map { BoardFacetOption(value: $0, count: counts[$0]!) }
            if kind == .status {
                derived.sort { statusOrder($0.value) < statusOrder($1.value) }   // statuses read in column order
            } else {
                derived = derived.enumerated().sorted { a, b in
                    a.element.count != b.element.count ? a.element.count > b.element.count : a.offset < b.offset
                }.map(\.element)
            }
            let options = (known ?? []).map { BoardFacetOption(value: $0.value, count: counts[$0.value] ?? 0, label: $0.label) } + derived
            if options.isEmpty { continue }
            groups.append(BoardFacetGroup(kind: kind, options: options))
        }
        return BoardFacets(groups: groups)
    }

    private func valuesFor(_ kind: BoardFacetKind, _ t: Ticket) -> [String] {
        func nonEmpty(_ s: String?) -> [String] { (s ?? "").isEmpty ? [] : [s!] }
        switch kind {
        case .status: return zentaoStatusOf(t).map { [$0] } ?? []
        case .resolvedBy: if case .zentaoBug(let e) = t.providerEntity { return nonEmpty(e.resolvedBy) }; return []
        case .openedBy: if case .zentaoBug(let e) = t.providerEntity { return nonEmpty(e.openedBy) }; return []
        case .confirmed: if case .zentaoBug(let e) = t.providerEntity { return ["\(e.confirmed ?? 0)"] }; return []
        case .assignee:
            if case .gitlabItem(let e) = t.providerEntity, !e.assignees.isEmpty { return e.assignees }
            return [t.assignee ?? ""]
        case .reviewer:
            if case .gitlabItem(let e) = t.providerEntity, !e.reviewers.isEmpty { return e.reviewers }
            return [""]
        case .severity: return t.severity.map { ["\($0)"] } ?? []
        case .priority: return [t.priority.rawValue]
        case .bugType: if case .zentaoBug(let e) = t.providerEntity { return nonEmpty(e.bugType?.lowercased()) }; return []
        case .resolution: if case .zentaoBug(let e) = t.providerEntity { return nonEmpty(e.resolution?.lowercased()) }; return []
        case .module:
            let id = zentaoModuleOf(t) ?? ""
            return id.isEmpty || id == "0" ? [] : [id]   // "0" is ZenTao's "no module"
        }
    }

    private func statusOrder(_ value: String) -> Int {
        if let c = BoardZenTaoBugColumn(rawValue: value) { return c.order }
        if let c = BoardZenTaoTaskColumn(rawValue: value) { return c.order }
        return 99
    }
}

import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/domain/usecases/{build_zentao_module_tree,list_task_bugs,is_due_this_week,filter_zentao_doc_libs,toggle_zentao_doc_pin,update_zentao_profile}.dart
/// A row of the module tree: the module's own `name` (last part of its path), its `depth` and ticket `count`.
public struct ZenTaoModuleNode: Hashable, Sendable {
    public var id: String, name: String, depth: Int, count: Int
    public init(id: String, name: String, depth: Int, count: Int) { self.id = id; self.name = name; self.depth = depth; self.count = count }
}

public struct ZenTaoModuleTree: Hashable, Sendable {
    public var nodes: [ZenTaoModuleNode]
    public var total: Int
    public init(nodes: [ZenTaoModuleNode], total: Int) { self.nodes = nodes; self.total = total }
    public static let empty = ZenTaoModuleTree(nodes: [], total: 0)
}

/// A ZenTao board's module tree: each module named by the last part of its path, indented under its parents,
/// with the count of tickets the board would show on picking it. `paths` is id -> "Live stream/Share" in ZenTao's order.
public struct BuildZenTaoModuleTree: Sendable {
    public init() {}
    public func callAsFunction(paths: [(id: String, path: String)], tickets: [Ticket], hideEmpty: Bool = false,
                               selected: String? = nil) -> ZenTaoModuleTree {
        var counts: [String: Int] = [:]
        for t in tickets { if let m = zentaoModuleOf(t) { counts[m, default: 0] += 1 } }
        let modules = paths.compactMap { e -> (id: String, parts: [String], count: Int)? in
            let parts = Self.parts(e.path)
            return e.id != "0" && !parts.isEmpty ? (e.id, parts, counts[e.id] ?? 0) : nil
        }
        var busy = Set<String>()
        for m in modules where !(m.count == 0 && m.id != selected) {
            for i in 1...m.parts.count { busy.insert(m.parts.prefix(i).joined(separator: "/")) }
        }
        return ZenTaoModuleTree(
            nodes: modules.compactMap { m in
                (!hideEmpty || busy.contains(m.parts.joined(separator: "/")))
                    ? ZenTaoModuleNode(id: m.id, name: m.parts.last!, depth: m.parts.count - 1, count: m.count) : nil
            },
            total: tickets.count)
    }
    private static func parts(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// The bugs related to ZenTao task `task` among `tickets`: the account's bugs whose `task` is its id. Newest first.
public struct ListTaskBugs: Sendable {
    public init() {}
    public func callAsFunction(task: Ticket, tickets: [Ticket]) -> [Ticket] {
        tickets.filter {
            guard $0.providerType == .zentao, $0.accountId == task.accountId,
                  case .zentaoBug(let b) = $0.providerEntity else { return false }
            return b.task == task.externalKey
        }.sorted { (Int($0.externalKey) ?? 0) > (Int($1.externalKey) ?? 0) }
    }
}

/// The target deadline from a ZenTao ticket's entity or `deadline:` label.
public func extractZenTaoDeadline(_ ticket: Ticket) -> Date? {
    func parse(_ s: String) -> Date? { ZenTaoDayParser.parse(s) }
    switch ticket.providerEntity {
    case .zentaoBug(let b): if let d = b.deadline, !d.isEmpty { return parse(d) }
    case .zentaoTask(let t): if let d = t.deadline, !d.isEmpty { return parse(d) }
    default: break
    }
    for l in ticket.labels where l.hasPrefix("deadline:") { return parse(String(l.dropFirst(9))) }
    return nil
}

/// Whether a date falls within the current ISO-8601 week (Monday 00:00 to Sunday 23:59:59.999), local time zone.
public struct IsDueThisWeek: Sendable {
    public init() {}
    public func callAsFunction(_ date: Date, now: Date = Date()) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return false }
        return date >= week.start && date < week.end
    }
}

/// Narrows libs to those whose name contains `query` (case-insensitive), keeping the server's order.
public struct FilterZenTaoDocLibs: Sendable {
    public init() {}
    public func callAsFunction(_ libs: [ZenTaoDocLib], query: String) -> [ZenTaoDocLib] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? libs : libs.filter { $0.name.lowercased().contains(q) }
    }
}

/// Pins a library or a document to the top of an account's Docs pane, or unpins it when already there.
public struct ToggleZenTaoDocPin: Sendable {
    private let repository: ZenTaoDocRepository
    public init(_ repository: ZenTaoDocRepository) { self.repository = repository }
    public func callAsFunction(accountId: String, lib: ZenTaoDocLib? = nil, doc: ZenTaoDocSummary? = nil) async -> Outcome<Void> {
        var it = repository.watchPins(accountId: accountId).makeAsyncIterator()
        let pins = await it.next() ?? ZenTaoDocPins()
        let next: ZenTaoDocPins
        if let lib { next = pins.togglingLib(lib) } else if let doc { next = pins.togglingDoc(doc) } else { return .success(()) }
        return await repository.savePins(accountId: accountId, pins: next)
    }
}

public struct UpdateZenTaoProfile: Sendable {
    private let repository: ZenTaoProfileRepository
    public init(_ repository: ZenTaoProfileRepository) { self.repository = repository }
    public func callAsFunction(account: Account, changes: ZenTaoProfileUpdate) async -> Outcome<ZenTaoProfile> {
        if changes.realname.trimmingCharacters(in: .whitespaces).isEmpty { return .failure(.parse("Name is required")) }
        let email = changes.email.trimmingCharacters(in: .whitespaces)
        if !email.isEmpty, email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) == nil {
            return .failure(.parse("Invalid email address"))
        }
        var next = changes
        next.realname = changes.realname.trimmingCharacters(in: .whitespaces)
        next.email = email
        next.mobile = changes.mobile.trimmingCharacters(in: .whitespaces)
        next.phone = changes.phone.trimmingCharacters(in: .whitespaces)
        return await repository.update(account: account, changes: next)
    }
}

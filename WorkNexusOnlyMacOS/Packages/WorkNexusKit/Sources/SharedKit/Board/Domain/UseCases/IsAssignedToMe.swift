import CoreDomain
import Foundation

/// Ported from: lib/shared/board/domain/usecases/is_assigned_to_me.dart
/// Whether a ticket is assigned to the account's own user (handle compare, tolerant of `. _ - space`).
public struct IsAssignedToMe: Sendable {
    public init() {}
    public func callAsFunction(_ ticket: Ticket, _ account: Account) -> Bool {
        func isMe(_ n: String?) -> Bool { Self.isHandleOf(n, account) }
        switch ticket.providerType {
        case .zentao: return isMe(ticket.assignee)
        case .gitlab, .github: return isMe(ticket.assignee) || Self.logins(ticket.providerEntity).contains(where: isMe)
        default: return false
        }
    }

    public static func isHandleOf(_ name: String?, _ account: Account) -> Bool {
        let me = account.handle.trimmingCharacters(in: .whitespaces).lowercased()
        guard !me.isEmpty, let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        if n == me { return true }
        func clean(_ s: String) -> String { s.filter { !"._-".contains($0) && !$0.isWhitespace } }
        let cleanN = clean(n)
        return !cleanN.isEmpty && cleanN == clean(me)
    }

    private static func logins(_ e: TicketProviderEntity?) -> [String] {
        switch e {
        case .gitlabItem(let g): return g.assigneeLogins
        case .githubItem(let g): return g.assigneeLogins
        default: return []
        }
    }
}

/// Ported from: lib/shared/board/domain/usecases/is_related_to_me.dart
/// Mine in any role: assigned to me, or opened / resolved / finished by me (ZenTao "Related to me").
public struct IsRelatedToMe: Sendable {
    public init() {}
    public func callAsFunction(_ ticket: Ticket, _ account: Account) -> Bool {
        if IsAssignedToMe()(ticket, account) { return true }
        let handles: [String?]
        switch ticket.providerEntity {
        case .zentaoBug(let e): handles = [e.openedByHandle, e.resolvedByHandle]
        case .zentaoTask(let e): handles = [e.openedByHandle, e.finishedByHandle]
        default: handles = []
        }
        return handles.contains { IsAssignedToMe.isHandleOf($0, account) }
    }
}

/// Not in the Flutter app: a team group as the scope of a board.
import CoreDomain
import Foundation

/// What was read of one person's work.
public enum ZentaoTeamLoad: Equatable, Sendable {
    case loading
    case loaded(count: Int, total: Int, truncated: Bool)
    case failed(String)

    public var isFailed: Bool { if case .failed = self { true } else { false } }
    public var isLoading: Bool { if case .loading = self { true } else { false } }
}

/// A team group a board shows in place of one execution or product: the tickets read from each of its people.
public struct ZentaoTeamScope: Equatable {
    public var group: ZenTaoTeamGroup
    /// Per login.
    public var loads: [String: ZentaoTeamLoad] = [:]
    /// Local ids of the tickets read so far, across every person.
    public var ids: Set<String> = []

    public init(group: ZenTaoTeamGroup) { self.group = group }
    public var accountId: String { group.accountId }
    public var logins: [String] { group.members.map(\.login) }

    public var isLoading: Bool { loads.values.contains { $0.isLoading } }
    public var failed: [String] { logins.filter { loads[$0]?.isFailed == true } }
    /// Every person's read failed: there is nothing to show.
    public var allFailed: Bool { !logins.isEmpty && failed.count == logins.count }
    public var truncated: Bool { loads.values.contains { if case .loaded(_, _, true) = $0 { true } else { false } } }

    /// The team's tickets of one kind among `all`: read ones that are assigned to a member (a ticket reassigned since
    /// leaves the team's view as soon as the store knows).
    func tickets(in all: [Ticket], bugs: Bool) -> [Ticket] {
        let type = bugs ? "bug" : "task", members = Set(logins)
        return all.filter {
            ids.contains($0.id) && $0.accountId == accountId && ($0.externalType ?? "").lowercased() == type && members.contains($0.assignee ?? "")
        }
    }
}

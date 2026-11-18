import CoreDomain
import Foundation

/// Ported from: lib/tools/gitlab/domain/usecases/build_gitlab_mr_board.dart + build_gitlab_issue_board.dart
/// Deviation: the Dart use cases take a `BoardQuery` and run `FilterTickets` first; here callers pass the
/// already-filtered tickets (the shared board engine owns filtering), so this layer stays free of `SharedKit`.

/// Each column is ordered by `sort` (the board's Sort button; priority, then most recently updated, by default) through
/// the shared `CompareTickets.board`.

public struct GitLabMrBoardColumn: Sendable {
    public let column: GitLabMrColumn
    public let tickets: [Ticket]
    public var count: Int { tickets.count }
}

public struct GitLabMrBoardModel: Sendable {
    public let columns: [GitLabMrBoardColumn]
    public var total: Int { columns.reduce(0) { $0 + $1.count } }
    public func column(_ column: GitLabMrColumn) -> GitLabMrBoardColumn { columns.first { $0.column == column }! }
}

/// Groups merge requests into the native lifecycle columns, keyed off the raw `providerStatus`
/// (`draft`/`opened`/`merged`/`closed`).
public struct BuildGitLabMrBoard: Sendable {
    /// The order of the cards within each column.
    public var sort: TicketSort
    public init(sort: TicketSort = .boardDefault) { self.sort = sort }

    public func callAsFunction(_ tickets: [Ticket]) -> GitLabMrBoardModel {
        var byColumn: [GitLabMrColumn: [Ticket]] = [:]
        for t in tickets where Self.isGitLabMr(t) { byColumn[Self.column(for: t), default: []].append(t) }
        return GitLabMrBoardModel(columns: GitLabMrColumn.columns.map {
            GitLabMrBoardColumn(column: $0, tickets: CompareTickets.boardOrdered(byColumn[$0] ?? [], by: sort))
        })
    }

    static func isGitLabMr(_ t: Ticket) -> Bool {
        t.providerType == .gitlab && (t.externalType ?? "").lowercased() == "mergerequest"
    }

    public static func column(for t: Ticket) -> GitLabMrColumn {
        switch t.providerStatus.lowercased() {
        case "draft": .draft
        case "merged": .merged
        case "closed": .closed
        default: .review
        }
    }
}

public struct GitLabIssueBoardColumn: Sendable {
    public let column: GitLabIssueColumn
    public let tickets: [Ticket]
    public var count: Int { tickets.count }
}

public struct GitLabIssueBoardModel: Sendable {
    public let columns: [GitLabIssueBoardColumn]
    public var total: Int { columns.reduce(0) { $0 + $1.count } }
    public func column(_ column: GitLabIssueColumn) -> GitLabIssueBoardColumn { columns.first { $0.column == column }! }
}

/// Groups issues into open / in-progress / closed. `closed` is keyed off the raw `providerStatus`; an open issue
/// lands in in-progress when its normalized status is `inprogress` (a "doing/wip" label).
public struct BuildGitLabIssueBoard: Sendable {
    /// The order of the cards within each column.
    public var sort: TicketSort
    public init(sort: TicketSort = .boardDefault) { self.sort = sort }

    public func callAsFunction(_ tickets: [Ticket]) -> GitLabIssueBoardModel {
        var byColumn: [GitLabIssueColumn: [Ticket]] = [:]
        for t in tickets where t.providerType == .gitlab && (t.externalType ?? "").lowercased() == "issue" {
            byColumn[Self.column(for: t), default: []].append(t)
        }
        return GitLabIssueBoardModel(columns: GitLabIssueColumn.columns.map {
            GitLabIssueBoardColumn(column: $0, tickets: CompareTickets.boardOrdered(byColumn[$0] ?? [], by: sort))
        })
    }

    public static func column(for t: Ticket) -> GitLabIssueColumn {
        if t.providerStatus.lowercased() == "closed" { return .closed }
        return t.status == .inprogress ? .inProgress : .open
    }
}

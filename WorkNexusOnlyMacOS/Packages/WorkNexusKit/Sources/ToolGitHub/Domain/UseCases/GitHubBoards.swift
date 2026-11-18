import CoreDomain
import Foundation

/// Ported from: lib/tools/github/domain/usecases/build_github_pr_board.dart + build_github_issue_board.dart
/// Deviation: the Dart use cases take a `BoardQuery` and run `FilterTickets` first; here callers pass the
/// already-filtered tickets (the shared board engine owns filtering), so this layer stays free of `SharedKit`.

/// Each column is ordered by `sort` (the board's Sort button; priority, then most recently updated, by default) through
/// the shared `CompareTickets.board`.

public struct GitHubPrBoardColumn: Sendable {
    public let column: GitHubPrColumn
    public let tickets: [Ticket]
    public var count: Int { tickets.count }
}

public struct GitHubPrBoardModel: Sendable {
    public let columns: [GitHubPrBoardColumn]
    public var total: Int { columns.reduce(0) { $0 + $1.count } }
    public func column(_ column: GitHubPrColumn) -> GitHubPrBoardColumn { columns.first { $0.column == column }! }
}

/// Groups pull requests into the native lifecycle columns, keyed off the raw `providerStatus`
/// (`draft`/`open`/`merged`/`closed`).
public struct BuildGitHubPrBoard: Sendable {
    /// The order of the cards within each column.
    public var sort: TicketSort
    public init(sort: TicketSort = .boardDefault) { self.sort = sort }

    public func callAsFunction(_ tickets: [Ticket]) -> GitHubPrBoardModel {
        var byColumn: [GitHubPrColumn: [Ticket]] = [:]
        for t in tickets where t.providerType == .github && (t.externalType ?? "").lowercased() == "pullrequest" {
            byColumn[Self.column(for: t), default: []].append(t)
        }
        return GitHubPrBoardModel(columns: GitHubPrColumn.columns.map {
            GitHubPrBoardColumn(column: $0, tickets: CompareTickets.boardOrdered(byColumn[$0] ?? [], by: sort))
        })
    }

    public static func column(for t: Ticket) -> GitHubPrColumn {
        switch t.providerStatus.lowercased() {
        case "draft": .draft
        case "merged": .merged
        case "closed": .closed
        default: .review
        }
    }
}

public struct GitHubIssueBoardColumn: Sendable {
    public let column: GitHubIssueColumn
    public let tickets: [Ticket]
    public var count: Int { tickets.count }
}

public struct GitHubIssueBoardModel: Sendable {
    public let columns: [GitHubIssueBoardColumn]
    public var total: Int { columns.reduce(0) { $0 + $1.count } }
    public func column(_ column: GitHubIssueColumn) -> GitHubIssueBoardColumn { columns.first { $0.column == column }! }
}

/// Groups issues into open / in-progress / closed. `closed` is keyed off the raw `providerStatus`; an open issue
/// lands in in-progress when its normalized status is `inprogress` (a "doing/wip" label).
public struct BuildGitHubIssueBoard: Sendable {
    /// The order of the cards within each column.
    public var sort: TicketSort
    public init(sort: TicketSort = .boardDefault) { self.sort = sort }

    public func callAsFunction(_ tickets: [Ticket]) -> GitHubIssueBoardModel {
        var byColumn: [GitHubIssueColumn: [Ticket]] = [:]
        for t in tickets where t.providerType == .github && (t.externalType ?? "").lowercased() == "issue" {
            byColumn[Self.column(for: t), default: []].append(t)
        }
        return GitHubIssueBoardModel(columns: GitHubIssueColumn.columns.map {
            GitHubIssueBoardColumn(column: $0, tickets: CompareTickets.boardOrdered(byColumn[$0] ?? [], by: sort))
        })
    }

    public static func column(for t: Ticket) -> GitHubIssueColumn {
        if t.providerStatus.lowercased() == "closed" { return .closed }
        return t.status == .inprogress ? .inProgress : .open
    }
}

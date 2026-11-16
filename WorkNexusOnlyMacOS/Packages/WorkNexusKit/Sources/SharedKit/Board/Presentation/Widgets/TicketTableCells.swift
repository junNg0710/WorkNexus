import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/ticket_table_cells.dart
/// The standard cells tool tables compose their columns from.
public struct TableIdCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    public init(_ ticket: Ticket) { self.ticket = ticket }
    public var body: some View { Text(ticket.externalKey).font(theme.typography.mono).foregroundStyle(theme.colors.tx2) }
}

public struct TableTitleCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    public init(_ ticket: Ticket) { self.ticket = ticket }
    public var body: some View {
        Text(ticket.title).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).lineLimit(1)
    }
}

public struct TableTextCell: View {
    @Environment(\.appTheme) private var theme
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View { Text(text).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).lineLimit(1) }
}

public struct TableStatusCell: View {
    @Environment(\.appTheme) private var theme
    let label: String; let color: Color
    public init(_ label: String, _ color: Color) { self.label = label; self.color = color }
    public var body: some View {
        HStack(spacing: theme.spacing.s6) { BoardColumnDot(color); TableTextCell(label) }
    }
}

public struct TablePriorityCell: View {
    let ticket: Ticket
    public init(_ ticket: Ticket) { self.ticket = ticket }
    public var body: some View {
        if hasExplicitPriority(ticket) { PriorityTag(ticket.providerType, ticket.priority).minimumScaleFactor(0.6) }
    }
}

public struct TableSeverityCell: View {
    let ticket: Ticket
    public init(_ ticket: Ticket) { self.ticket = ticket }
    public var body: some View { if let s = ticket.severity { SeverityTag(s) } }
}

public struct TableAssigneeCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    public init(_ ticket: Ticket) { self.ticket = ticket }
    public var body: some View {
        AssigneeChip(ticket.assignee, accent: theme.colors.accent, accountId: ticket.providerType == .zentao ? ticket.accountId : nil)
    }
}

public struct TableUpdatedCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket; let dateFormat: String
    public init(_ ticket: Ticket, dateFormat: String = "iso") { self.ticket = ticket; self.dateFormat = dateFormat }
    public var body: some View {
        Text(formatWhen(ticket.updatedAt, format: dateFormat)).font(theme.typography.mono).foregroundStyle(theme.colors.tx3).lineLimit(1)
    }
}

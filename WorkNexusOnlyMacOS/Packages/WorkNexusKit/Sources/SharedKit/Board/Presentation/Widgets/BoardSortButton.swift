import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/board_sort_button.dart
/// The toolbar's Sort button: the field the board's cards are ordered by and its direction; a menu of `fields` to pick
/// another, or the same one again to flip the direction. The order is the session's, shared by every board
/// (`AppNavController.boardSort`).
public struct BoardSortButton: View {
    @Environment(\.appTheme) private var theme
    let nav: AppNavController; let fields: [TicketSortField]

    public init(nav: AppNavController, fields: [TicketSortField] = TicketSortField.boardFields) {
        self.nav = nav; self.fields = fields
    }

    public var body: some View {
        let sort = nav.boardSort
        let c = theme.colors
        let changed = sort != .boardDefault
        let ink = changed ? c.accent : c.tx2
        AppMenuButton(help: appString("boardSort", "Sort cards"), items: {
            fields.map { f in AppNativeMenu.Item(boardSortLabel(f), checked: f == nav.boardSort.field) { nav.sortBoardCards(by: f) } }
        }) {
            HStack(spacing: theme.spacing.s6) {
                Image(systemName: sort.descending ? "arrow.down" : "arrow.up").font(.system(size: theme.sizes.icon14)).foregroundStyle(ink)
                Text(boardSortLabel(sort.field)).font(theme.typography.metaStrong).foregroundStyle(ink).lineLimit(1)
            }
            .padding(.horizontal, theme.spacing.s12).frame(height: theme.sizes.control32)
            .background(changed ? c.sel : c.panel, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay {
                if theme.showOutline { RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.line, lineWidth: theme.borders.hairline) }
            }
            .contentShape(RoundedRectangle(cornerRadius: theme.radii.md))
        }
        .fixedSize()
        .accessibilityLabel(appString("boardSort", "Sort cards"))
    }
}

/// What a sort field is called on the board's Sort button.
public func boardSortLabel(_ field: TicketSortField) -> String {
    switch field {
    case .id: appString("boardSortCreated", "Created")
    case .title: appString("tableColumnTitle", "Title")
    case .priority: appString("priority", "Priority")
    case .severity: appString("severity", "Severity")
    case .status: appString("status", "Status")
    case .assignee: appString("assignedTo", "Assigned to")
    case .estimate: appString("estimate", "Estimate")
    case .left: appString("tableColumnLeft", "Left")
    case .resolution: appString("resolution", "Resolution")
    case .updated: appString("updated", "Updated")
    case .deadline: appString("fieldDeadline", "Deadline")
    }
}

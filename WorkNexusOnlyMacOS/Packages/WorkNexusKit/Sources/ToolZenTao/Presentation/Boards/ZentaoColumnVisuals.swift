/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_bug_column_parts,zentao_task_column_parts,zentao_status_filter_option}.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// A ZenTao board column's header label and status-dot colour.
public enum ZentaoColumnVisual {
    public static func bug(_ column: ZenTaoBugColumn, _ c: AppPalette) -> (label: String, color: Color) {
        switch column {
        case .newUnconfirmed: (appString("boardBugColNew", "New / Unconfirmed"), c.tx3)
        case .confirmedToFix: (appString("boardBugColConfirmed", "Confirmed / To Fix"), c.accent)
        case .resolvedVerify: (appString("boardBugColResolved", "Resolved / Verify"), c.green)
        case .postponed: (appString("boardBugColPostponed", "Postponed"), c.amber)
        case .nonFix: (appString("boardBugColNonFix", "Non-Fix"), c.red)
        case .closed: (appString("boardBugColClosed", "Closed"), c.tx2)
        }
    }

    public static func task(_ column: ZenTaoTaskColumn, _ c: AppPalette) -> (label: String, color: Color) {
        switch column {
        case .notStarted: (appString("boardTaskColNotStarted", "Not Started"), c.tx3)
        case .inProgress: (appString("boardTaskColInProgress", "In Progress"), c.accent)
        case .paused: (appString("boardTaskColPaused", "Paused"), c.amber)
        case .doneVerify: (appString("boardTaskColDoneVerify", "Done / Verify"), c.green)
        case .closed: (appString("boardTaskColClosed", "Closed"), c.tx2)
        case .canceled: (appString("boardTaskColCanceled", "Canceled"), c.red)
        }
    }

    /// A status filter option named and coloured like its board column (the table's Status cell). `bugBoard` picks the
    /// bug columns over the task ones.
    public static func statusFilterOption(bugBoard: Bool, palette: AppPalette) -> FacetStatusOption {
        { option, active, onTap in
            var label = option.value
            var color: Color?
            if bugBoard, let col = ZenTaoBugColumn(rawValue: option.value) { (label, color) = (bug(col, palette).label, bug(col, palette).color) }
            if !bugBoard, let col = ZenTaoTaskColumn(rawValue: option.value) { (label, color) = (task(col, palette).label, task(col, palette).color) }
            return FilterChipOption(label: label, active: active, onTap: onTap, dotColor: color, count: option.count)
        }
    }
}

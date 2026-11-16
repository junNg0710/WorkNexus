import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/bug_task_select.dart
/// The bug's task. ZenTao lists tasks per execution, so until one is picked the field asks for the execution
/// instead: it lists the executions, and picking one sets the bug's (which loads its tasks).
struct BugTaskSelect: View {
    @Environment(\.appTheme) private var theme
    let options: BugFormOptions
    let execution: String
    let task: String
    let onExecution: (String) -> Void
    let onTask: (String) -> Void

    var body: some View {
        if execution != "0" {
            OptionSelect(options: options.tasks, value: task, noneValue: "0", onChanged: onTask)
        } else {
            SearchableDropdownField<FormOption>(
                items: options.executions, value: nil, labelOf: \.label,
                hintText: appString("taskNeedsExecution", "Pick an execution first"),
                searchHint: appString("searchExecutions", "Search executions…"), emptyLabel: appString("noMatches", "No matches"),
                popoverMinWidth: theme.sizes.dialogMd, labelMaxLines: 2) { onExecution($0.value) }
        }
    }
}

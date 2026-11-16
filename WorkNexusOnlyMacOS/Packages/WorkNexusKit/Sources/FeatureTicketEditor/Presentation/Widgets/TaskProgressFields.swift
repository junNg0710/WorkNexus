import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/task_progress_fields.dart
/// An existing task's status and hours consumed / left, as ZenTao's edit form has them (a new task has neither yet).
struct TaskProgressFields: View {
    @Environment(\.appTheme) private var theme
    let controller: TaskEditorController
    let draft: TaskDraft

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s14) {
            EditorField(label: appString("status", "Status")) {
                OptionSelect(options: ZenTaoChoices.withValue(ZenTaoChoices.taskStatuses, draft.status), value: draft.status) { v in
                    controller.edit { $0.status = v }
                }
            }
            EditorField(label: appString("fieldConsumed", "Consumed (h)")) {
                EditorTextInput(initial: FormValueFormat.hoursText(draft.consumed), numeric: true) { v in
                    controller.edit { $0.consumed = FormValueFormat.parseHours(v) }
                }
            }
            EditorField(label: appString("fieldLeft", "Left (h)")) {
                EditorTextInput(initial: FormValueFormat.hoursText(draft.left), numeric: true) { v in
                    controller.edit { $0.left = FormValueFormat.parseHours(v) }
                }
            }
        }
    }
}

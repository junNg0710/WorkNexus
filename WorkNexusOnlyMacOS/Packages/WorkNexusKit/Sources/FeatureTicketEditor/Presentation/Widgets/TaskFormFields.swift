import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/task_form_fields.dart
/// Start date and deadline side by side with a dash between.
struct TaskTimeframeInput: View {
    @Environment(\.appTheme) private var theme
    let estStarted: String
    let deadline: String
    let onEstStartedChanged: (String) -> Void
    let onDeadlineChanged: (String) -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s4) {
            EditorDateInput(value: estStarted, onChanged: onEstStartedChanged)
            Text("-").font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx3)
            EditorDateInput(value: deadline, onChanged: onDeadlineChanged)
        }
    }
}

/// Priority picker and estimate (hours) input in one compact row.
struct TaskPriorityEstimateInput: View {
    @Environment(\.appTheme) private var theme
    let priority: Int
    let estimate: Double
    let onPriorityChanged: (Int) -> Void
    let onEstimateChanged: (String) -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s10) {
            EditorLevelInput(level: .priority, value: priority, onChanged: onPriorityChanged).frame(maxWidth: .infinity)
            EditorTextInput(initial: FormValueFormat.hoursText(estimate), numeric: true, onChanged: onEstimateChanged)
                .frame(width: theme.sizes.dialogSm / 4)
        }
    }
}

/// Radio choice of `TaskAfterSave` (where saving a new task goes next).
struct TaskNextActionSelector: View {
    @Environment(\.appTheme) private var theme
    let action: TaskAfterSave
    let onChanged: (TaskAfterSave) -> Void

    private func label(_ a: TaskAfterSave) -> String {
        switch a {
        case .openTask: appString("taskAfterSaveOpen", "Open the task")
        case .continueAdding: appString("taskAfterSaveContinue", "Add another task")
        case .backToList: appString("taskAfterSaveList", "Back to the list")
        }
    }

    var body: some View {
        HStack(spacing: theme.spacing.s16) {
            ForEach(TaskAfterSave.allCases, id: \.self) { option in
                Button { onChanged(option) } label: {
                    HStack(spacing: theme.spacing.s6) {
                        Circle().stroke(action == option ? theme.colors.accent : theme.colors.line2, lineWidth: action == option ? theme.borders.heavy + 2 : theme.borders.medium)
                            .frame(width: theme.sizes.icon16, height: theme.sizes.icon16)
                        Text(label(option)).font(theme.typography.paragraph).foregroundStyle(action == option ? theme.colors.tx : theme.colors.tx2)
                    }
                    .padding(theme.spacing.s2).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

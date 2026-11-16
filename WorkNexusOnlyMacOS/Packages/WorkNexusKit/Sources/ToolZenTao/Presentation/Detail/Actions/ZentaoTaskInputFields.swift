/// Ported from: detail/{task_hours_field,task_action_date_field,task_input_problem_text}.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A labelled field for a number of hours.
struct ZentaoTaskHoursField: View {
    @Environment(\.appTheme) private var theme
    let label: String; @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZentaoFieldLabel(label)
            TextField("", text: $text).textFieldStyle(.plain).font(theme.typography.body).foregroundStyle(theme.colors.tx)
                .onChange(of: text) { _, new in
                    let kept = new.filter { "0123456789.,".contains($0) }
                    if kept != new { text = kept }
                }
                .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control32)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }
}

/// A labelled date and time (to the minute), as ZenTao's task forms take "actual begin / end". A disabled field only
/// shows its value, as ZenTao locks a begin that is already recorded.
struct ZentaoTaskDateField: View {
    let label: String; let value: Date; var enabled = true; let onChanged: (Date) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZentaoFieldLabel(label)
            AppDateField(value: value, withTime: true, enabled: enabled) { if let d = $0 { onChanged(d) } }
        }
    }
}

/// Why a task form's input would be refused, as the text under the fields it is about.
enum ZentaoTaskProblemText {
    static func text(_ p: ZenTaoTaskInputProblem) -> String {
        switch p {
        case .invalidHours: appString("zentaoHoursInvalid", "Enter hours as a number, 0 or more")
        case .leftRequired: appString("zentaoHoursLeftRequired", "Enter the hours left (more than 0)")
        case .spentRequired: appString("zentaoHoursSpentRequired", "Enter the hours worked — none are logged yet")
        case .endBeforeBegin: appString("zentaoEndBeforeBegin", "The end can't be before the begin")
        }
    }
}

struct ZentaoTaskProblemLine: View {
    @Environment(\.appTheme) private var theme
    let problem: ZenTaoTaskInputProblem
    init(_ problem: ZenTaoTaskInputProblem) { self.problem = problem }
    var body: some View {
        Text(ZentaoTaskProblemText.text(problem)).font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
            .padding(.top, theme.spacing.s6)
    }
}

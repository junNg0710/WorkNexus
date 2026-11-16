import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/detail/time_tracking_editor.dart
/// What the time-tracking form hands to the service: blank fields are nil, the reset boxes clear the value.
struct GitlabTimeTrackingInput: Equatable {
    var estimate: String?
    var spent: String?
    var resetEstimate: Bool
    var resetSpent: Bool

    init(estimate: String, spent: String, resetEstimate: Bool, resetSpent: Bool) {
        func blank(_ s: String) -> String? { s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s.trimmingCharacters(in: .whitespaces) }
        self.estimate = blank(estimate); self.spent = blank(spent); self.resetEstimate = resetEstimate; self.resetSpent = resetSpent
    }
}

/// The estimate and "add time spent" form of the Time tracking section, with a Save footer.
struct GitlabTimeTrackingEditor: View {
    @Environment(\.appTheme) private var theme
    let currentEstimate: String?
    let currentSpent: String?
    let onSave: (_ estimate: String?, _ spent: String?, _ resetEstimate: Bool, _ resetSpent: Bool) async -> Outcome<Void>
    let onClose: () -> Void
    @State private var estimate = ""
    @State private var spent = ""
    @State private var resetEstimate = false
    @State private var resetSpent = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                GitlabTimeField(label: appString("estimate", "Estimate"), hint: appString("estimateDurationHint", "For example, 2h 30m"),
                                text: $estimate, disabled: resetEstimate, onSubmit: save)
                Toggle(appString("resetEstimate", "Reset estimate"), isOn: $resetEstimate).toggleStyle(.checkbox)
                    .font(theme.typography.paragraph).padding(.bottom, theme.spacing.s6)
                GitlabTimeField(label: appString("addTimeSpent", "Add time spent"), hint: appString("spentDurationHint", "For example, 30m"),
                                text: $spent, disabled: resetSpent, onSubmit: save)
                if let total = currentSpent, !total.isEmpty {
                    Text(appFormat("currentTotal", "Current total: %1$@", total)).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                }
                Toggle(appString("resetSpentTime", "Reset spent time"), isOn: $resetSpent).toggleStyle(.checkbox).font(theme.typography.paragraph)
            }
            .padding(theme.spacing.s16).frame(maxWidth: .infinity, alignment: .leading)
            GitlabEditorFooter(busy: busy, error: error, onSave: save)
        }
        .frame(width: 340).background(theme.colors.card)
        .onAppear { estimate = currentEstimate ?? "" }
    }

    private func save() {
        guard !busy else { return }
        busy = true; error = nil
        let i = GitlabTimeTrackingInput(estimate: estimate, spent: spent, resetEstimate: resetEstimate, resetSpent: resetSpent)
        Task {
            let result = await onSave(i.estimate, i.spent, i.resetEstimate, i.resetSpent)
            busy = false
            switch result {
            case .success: onClose()
            case .failure(let f): error = f.message
            }
        }
    }
}

private struct GitlabTimeField: View {
    @Environment(\.appTheme) private var theme
    let label: String; let hint: String
    @Binding var text: String
    let disabled: Bool; let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            Text(label).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
            TextField(hint, text: $text).textFieldStyle(.plain).font(theme.typography.body).disabled(disabled).onSubmit(onSubmit)
                .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control32)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                .opacity(disabled ? 0.5 : 1)
        }
    }
}

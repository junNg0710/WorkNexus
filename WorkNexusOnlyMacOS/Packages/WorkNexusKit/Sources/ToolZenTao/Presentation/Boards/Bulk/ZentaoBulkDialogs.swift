/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// What a bulk action would do, said before it is applied: how many tickets change and why the others do not.
struct ZentaoBulkSummary: View {
    @Environment(\.appTheme) private var theme
    let plan: ZenTaoBulkPlan

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            Text(plan.isEmpty ? appString("leaderBulkNothing", "Nothing to change")
                              : appFormat("leaderBulkWillChange", "%1$@ will change on ZenTao", "\(plan.tickets.count)"))
                .font(theme.typography.bodyStrong).foregroundStyle(plan.isEmpty ? theme.colors.tx3 : theme.colors.tx)
            let notAllowed = plan.skipped(.notAllowed).count, unchanged = plan.skipped(.unchanged).count
            if notAllowed > 0 {
                Text(appFormat("leaderBulkSkipNotAllowed", "%1$@ skipped: ZenTao does not allow it in their state", "\(notAllowed)"))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
            }
            if unchanged > 0 {
                Text(appFormat("leaderBulkSkipUnchanged", "%1$@ skipped: already so", "\(unchanged)"))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
            }
        }
    }
}

/// Hands every picked ticket to one person.
struct ZentaoBulkAssignDialog: View {
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let state: ZentaoUIState; let bugs: Bool; let model: ZentaoBulkModel; let onClose: () -> Void
    @State private var login: String?

    var body: some View {
        let targets = state.bulkTargets(bugs: bugs)
        let plan = login.map { PlanBulkAction()(targets, .assign(login: $0)) } ?? ZenTaoBulkPlan(tickets: [], skipped: [])
        ZentaoActionFrame(title: appFormat("leaderBulkAssignTitle", "Assign %1$@ tickets", "\(targets.count)"), icon: "person.badge.plus",
                          submitLabel: appFormat("leaderBulkApply", "Apply to %1$@", "\(plan.tickets.count)"), busy: false,
                          canSubmit: !plan.isEmpty, onSubmit: {
                              guard let login else { return }
                              onClose()
                              Task { await model.run(.assign(login: login), on: targets, state: state, bugs: bugs, toasts: toasts) }
                          }, onClose: onClose) {
            ZentaoFieldLabel(appString("fieldAssignTo", "Assign to"))
            // The people of the board's execution / product, read through the first picked ticket.
            if let first = targets.first { ZentaoAssigneeDropdown(deps: deps, ticket: first, value: login) { login = $0 } }
            ZentaoFieldGap()
            if login != nil { ZentaoBulkSummary(plan: plan) }
        }
    }
}

/// Sets the priority of every picked ticket.
struct ZentaoBulkPriorityDialog: View {
    @Environment(\.toasts) private var toasts
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool; let model: ZentaoBulkModel; let onClose: () -> Void
    @State private var pri: Int?

    var body: some View {
        let targets = state.bulkTargets(bugs: bugs)
        let plan = pri.map { PlanBulkAction()(targets, .priority($0)) } ?? ZenTaoBulkPlan(tickets: [], skipped: [])
        ZentaoActionFrame(title: appFormat("leaderBulkPriorityTitle", "Set the priority of %1$@ tickets", "\(targets.count)"), icon: "flag",
                          submitLabel: appFormat("leaderBulkApply", "Apply to %1$@", "\(plan.tickets.count)"), busy: false,
                          canSubmit: !plan.isEmpty, onSubmit: {
                              guard let pri else { return }
                              onClose()
                              Task { await model.run(.priority(pri), on: targets, state: state, bugs: bugs, toasts: toasts) }
                          }, onClose: onClose) {
            ZentaoFieldLabel(appString("priority", "Priority"))
            HStack(spacing: theme.spacing.s6) {
                ForEach(Priority.allCases, id: \.self) { p in
                    FilterOptionChip(FilterChipOption(label: "\(p.level + 1) · \(priorityName(p))", active: pri == p.level + 1,
                                                      onTap: { pri = p.level + 1 }))
                }
            }
            ZentaoFieldGap()
            if pri != nil { ZentaoBulkSummary(plan: plan) }
        }
    }
}

/// Closes every picked ticket ZenTao lets be closed (a resolved bug, a finished or cancelled task).
struct ZentaoBulkCloseDialog: View {
    @Environment(\.toasts) private var toasts
    let state: ZentaoUIState; let bugs: Bool; let model: ZentaoBulkModel; let onClose: () -> Void

    var body: some View {
        let targets = state.bulkTargets(bugs: bugs)
        let plan = PlanBulkAction()(targets, .close)
        ZentaoActionFrame(title: appFormat("leaderBulkCloseTitle", "Close %1$@ tickets", "\(targets.count)"), icon: "checkmark.circle",
                          submitLabel: appFormat("leaderBulkApply", "Apply to %1$@", "\(plan.tickets.count)"), busy: false,
                          canSubmit: !plan.isEmpty, onSubmit: {
                              onClose()
                              Task { await model.run(.close, on: targets, state: state, bugs: bugs, toasts: toasts) }
                          }, onClose: onClose) {
            ZentaoBulkSummary(plan: plan)
        }
    }
}

/// The tickets a bulk run could not change, each with ZenTao's reason, and a way to try those again.
struct ZentaoBulkFailuresDialog: View {
    @Environment(\.toasts) private var toasts
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let bugs: Bool; let model: ZentaoBulkModel; let onClose: () -> Void

    var body: some View {
        let failures = model.failures
        let items = failures?.tickets ?? []
        ZentaoActionFrame(title: appFormat("leaderBulkFailedTitle", "%1$@ tickets failed", "\(items.count)"), icon: "exclamationmark.triangle",
                          submitLabel: appString("leaderBulkRetry", "Retry failed"), busy: false, canSubmit: !items.isEmpty, onSubmit: {
                              guard let failures else { return }
                              model.failures = nil
                              onClose()
                              Task { await model.run(failures.action, on: failures.tickets, state: state, bugs: bugs, toasts: toasts) }
                          }, onClose: { model.failures = nil; onClose() }) {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                ForEach(items) { t in
                    VStack(alignment: .leading, spacing: theme.spacing.s2) {
                        Text(verbatim: "#\(t.externalKey) \(t.title)").font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                        Text(failures?.messages[t.id] ?? "").font(theme.typography.meta).foregroundStyle(theme.colors.red)
                    }
                }
            }
        }
    }
}

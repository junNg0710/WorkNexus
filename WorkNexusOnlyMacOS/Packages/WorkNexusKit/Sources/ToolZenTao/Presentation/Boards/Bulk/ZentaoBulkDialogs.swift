/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// What a bulk action would do, said before it is applied: how many tickets change and why the others do not; the
/// skipped tickets themselves are one click away.
struct ZentaoBulkSummary: View {
    @Environment(\.appTheme) private var theme
    let plan: ZenTaoBulkPlan
    @State private var showSkipped = false

    static func reason(_ r: ZenTaoBulkSkipReason) -> String {
        switch r {
        case .notAllowed: appString("leaderBulkReasonNotAllowed", "ZenTao does not allow it in its state")
        case .unchanged: appString("leaderBulkReasonUnchanged", "already so")
        case .notMember: appString("leaderBulkReasonNotMember", "not on its team")
        case .needsHours: appString("leaderBulkReasonNeedsHours", "needs hours left")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            Text(plan.isEmpty ? appString("leaderBulkNothing", "Nothing to change")
                              : appFormat("leaderBulkWillChange", "%1$@ will change on ZenTao", "\(plan.tickets.count)"))
                .font(theme.typography.bodyStrong).foregroundStyle(plan.isEmpty ? theme.colors.tx3 : theme.colors.tx)
            let notAllowed = plan.skipped(.notAllowed).count, unchanged = plan.skipped(.unchanged).count
            let notMember = plan.skipped(.notMember).count, needsHours = plan.skipped(.needsHours).count
            if notAllowed > 0 {
                Text(appFormat("leaderBulkSkipNotAllowed", "%1$@ skipped: ZenTao does not allow it in their state", "\(notAllowed)"))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
            }
            if unchanged > 0 {
                Text(appFormat("leaderBulkSkipUnchanged", "%1$@ skipped: already so", "\(unchanged)"))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
            }
            if notMember > 0 {
                Text(appFormat("leaderBulkSkipNotMember", "%1$@ skipped: not on the ticket's execution or product team", "\(notMember)"))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.amber)
            }
            if needsHours > 0 {
                Text(appFormat("leaderBulkSkipNeedsHours", "%1$@ skipped: tasks with no hours left, until you type them above", "\(needsHours)"))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.amber)
            }
            if !plan.skipped.isEmpty {
                Button(showSkipped ? appString("leaderBulkHideSkipped", "Hide the skipped tickets")
                                   : appString("leaderBulkShowSkipped", "Show the skipped tickets")) { showSkipped.toggle() }
                    .buttonStyle(.plain).font(theme.typography.metaStrong).foregroundStyle(theme.colors.accent).pointerStyle(.link)
                if showSkipped {
                    ForEach(plan.skipped, id: \.ticket.id) { s in
                        Text(verbatim: "#\(s.ticket.externalKey) \(s.ticket.title) · \(Self.reason(s.reason))")
                            .font(theme.typography.meta).foregroundStyle(theme.colors.tx2).lineLimit(1)
                    }
                }
            }
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
                              Task { await model.run(.priority(pri), plan: plan, state: state, bugs: bugs, toasts: toasts) }
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
                              Task { await model.run(.close, plan: plan, state: state, bugs: bugs, toasts: toasts) }
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
                              // Planned again: a ticket changed since the run may no longer need it.
                              Task { await model.run(failures.action, plan: PlanBulkAction()(failures.tickets, failures.action),
                                                     state: state, bugs: bugs, toasts: toasts) }
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
